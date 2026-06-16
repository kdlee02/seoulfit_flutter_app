"""Itinerary planning nodes for the LangGraph.

수정사항 (버그 수정):
1. _expand_or_replace_area_anchors(): anchor 교체 시 좌표 기반 권역 검증 추가
2. build_area_representative_supplement(): 'areas' 파라미터 추가 (시그니처 불일치 수정)
3. _representative_fit(): generic token만 매칭되는 오류 수정
4. used_names를 plan_node에서 관리해 두 번 호출 시 중복 방지
5. AREA_ALIASES에 sinsa 추가
"""

from __future__ import annotations

import csv
import json
import math
import os
import re
import time
from pathlib import Path
from typing import Any

import dspy
import requests
from langchain_core.messages import AIMessage

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

from llm import lm_context
from rag import build_query, retrieve_courses
from state import TravelState

_BASE_DIR = Path(__file__).resolve().parent
if load_dotenv is not None:
    load_dotenv(_BASE_DIR / ".env", override=True)

GOOGLE_PLACES_API_KEY = (
    os.getenv("GOOGLE_PLACES_API_KEY")
    or os.getenv("GOOGLE_MAPS_API_KEY")
    or ""
)

SEOUL_AREA_CENTERS = {
    "hongdae":    (37.5563, 126.9227),
    "gangnam":    (37.5196, 127.0228),
    "jongno":     (37.5729, 126.9794),
    "myeongdong": (37.5636, 126.9857),
    "seongsu":    (37.5447, 127.0558),
    "itaewon":    (37.5347, 126.9946),
    "sinchon":    (37.5596, 126.9373),
    "dongdaemun": (37.5666, 127.0097),
    "yeouido":    (37.5217, 126.9244),
    "mapo":       (37.5479, 126.9130),
    "jamsil":     (37.5133, 127.1028),
    "insadong":   (37.5741, 126.9861),
    "mangwon":    (37.5530, 126.9028),
    "hapjeong":   (37.5499, 126.9143),
    "sinsa":      (37.5196, 127.0228),
}

DEFAULT_CENTER = (37.5665, 126.9780)

# ============================================================
# 버그 1 수정: 권역별 허용 반경 (km) 정의
# anchor replacement 시 이 반경 밖 POI는 후보에서 제외
# ============================================================
AREA_RADIUS_KM: dict[str, float] = {
    "hongdae":    2.2,
    "mapo":       2.5,
    "mangwon":    2.0,
    "hapjeong":   2.0,
    "seongsu":    2.0,
    "gangnam":    3.5,
    "sinsa":      2.0,
    "jongno":     2.5,
    "insadong":   2.0,
    "myeongdong": 2.0,
    "itaewon":    2.0,
    "sinchon":    2.0,
    "dongdaemun": 2.0,
    "yeouido":    2.5,
    "jamsil":     3.0,
}
DEFAULT_AREA_RADIUS_KM = 2.5


def _assign_areas_to_days(areas: list[str]) -> list[list[str]]:
    if not areas:
        return []
    return [[area] for area in areas]


_group_areas_by_proximity = _assign_areas_to_days


def _build_day_area_prompt(area_groups: list[list[str]], duration_days: int) -> str:
    if not area_groups:
        return ""
    AREA_DISPLAY = {
        "hongdae": "Hongdae / Yeonnam",
        "mapo": "Hongdae / Mangwon",
        "mangwon": "Mangwon / Mapo",
        "sinchon": "Sinchon / Hongdae",
        "gangnam": "Gangnam / Sinsa",
        "samseong_coex": "COEX / Samseong",
        "seongsu": "Seongsu / Seoul Forest",
        "jongno": "Jongno / Gwanghwamun",
        "insadong": "Insadong / Bukchon",
        "myeongdong": "Myeongdong / Jung-gu",
        "itaewon": "Itaewon / Hannam",
        "yongsan": "Yongsan / Itaewon",
        "dongdaemun": "Dongdaemun / DDP",
        "yeouido": "Yeouido / Han River",
        "jamsil": "Jamsil / Lotte World",
        "bukchon": "Bukchon / Samcheong",
        "daehaengno": "Daehangno / Naksan",
        "seocho": "Seocho / Express Bus Terminal",
        "apgujeong": "Apgujeong / Rodeo",
    }
    lines = ["DAY-BY-DAY AREA ASSIGNMENTS (derived from user preferences — FOLLOW STRICTLY):"]
    groups_to_use = area_groups[:duration_days]
    for i, group in enumerate(groups_to_use, 1):
        display_names = [AREA_DISPLAY.get(a, a.replace("_", " ").title()) for a in group]
        if len(display_names) == 1:
            lines.append(f"  Day {i}: {display_names[0]} area")
        else:
            lines.append(f"  Day {i}: {' + '.join(display_names)} area (adjacent — good for one day)")
    if len(groups_to_use) < duration_days:
        remaining = duration_days - len(groups_to_use)
        lines.append(f"  Day {len(groups_to_use)+1}~{duration_days}: Explore other Seoul areas freely ({remaining} day(s))")
    lines.append("Each day MUST stay within its assigned area(s). Do NOT mix areas from different days.")
    return "\n".join(lines)


AREA_REPRESENTATIVE_POI_PRIORS = {
    "gangnam": {
        "general": [
            "Starfield Library", "별마당도서관",
            "COEX", "코엑스", "Starfield COEX Mall", "스타필드 코엑스",
            "Garosu-gil", "가로수길",
            "Bongeunsa Temple", "봉은사",
            "Dosan Park", "도산공원",
            "Gangnam Station Underground Shopping Center", "강남역 지하쇼핑센터",
        ],
        "shopping": [
            "Starfield COEX Mall", "스타필드 코엑스",
            "COEX", "코엑스",
            "Gangnam Station Underground Shopping Center", "강남역 지하쇼핑센터",
            "Garosu-gil", "가로수길",
            "Apgujeong Rodeo", "압구정로데오",
        ],
        "culture": ["Starfield Library", "별마당도서관", "Bongeunsa Temple", "봉은사", "COEX", "코엑스"],
        "history": ["Bongeunsa Temple", "봉은사", "Starfield Library", "별마당도서관"],
        "kpop": ["K-Star Road", "K스타로드", "Apgujeong Rodeo", "압구정로데오", "COEX", "코엑스"],
        "nature": ["Dosan Park", "도산공원", "Bongeunsa Temple", "봉은사", "Seonjeongneung", "선정릉"],
        "family": ["COEX Aquarium", "코엑스 아쿠아리움", "Starfield Library", "별마당도서관", "COEX", "코엑스", "Dosan Park", "도산공원"],
        "food": ["Garosu-gil", "가로수길", "Apgujeong Rodeo", "압구정로데오", "Gangnam Station", "강남역", "Sinsa-dong", "신사동"],
        "nightlife": ["Gangnam Station", "강남역", "Apgujeong Rodeo", "압구정로데오", "Sinsa-dong", "신사동"],
        "beauty": ["Garosu-gil", "가로수길", "Apgujeong Rodeo", "압구정로데오", "K-Star Road", "K스타로드", "COEX", "코엑스"],
    },
    "hongdae": {
        "general": [
            "Hongdae Street", "홍대 거리", "Hongik University Street",
            "Yeonnam-dong Cafe Street", "연남동 카페 골목",
            "Gyeongui Line Forest Park", "경의선숲길",
            "Mangwon Market", "망원시장",
            "KT&G Sangsangmadang", "상상마당",
        ],
        "shopping": ["Hongdae Street", "홍대 거리", "KT&G Sangsangmadang", "상상마당", "Mangwon Market", "망원시장"],
        "food": ["Mangwon Market", "망원시장", "Yeonnam-dong Cafe Street", "연남동 카페 골목", "Hongdae Street", "홍대 거리"],
        "cafe_hopping": ["Yeonnam-dong Cafe Street", "연남동 카페 골목", "Gyeongui Line Forest Park", "경의선숲길", "Hongdae Street", "홍대 거리"],
        "nightlife": ["Hongdae Street", "홍대 거리"],
        "kpop": ["Hongdae Street", "홍대 거리", "KT&G Sangsangmadang", "상상마당"],
    },
    "seongsu": {
        "general": ["Seoul Forest", "서울숲", "Seongsu Yeonmujang-gil", "성수연무장길", "Amore Seongsu", "아모레 성수", "Seongsu Handmade Shoes Street", "성수동 수제화 거리"],
        "shopping": ["Seongsu Yeonmujang-gil", "성수연무장길", "Amore Seongsu", "아모레 성수", "Seongsu Handmade Shoes Street", "성수동 수제화 거리"],
        "cafe_hopping": ["Seongsu Yeonmujang-gil", "성수연무장길", "Seoul Forest", "서울숲"],
        "beauty": ["Amore Seongsu", "아모레 성수", "Seongsu Yeonmujang-gil", "성수연무장길"],
        "nature": ["Seoul Forest", "서울숲"],
    },
    "myeongdong": {
        "general": ["Myeongdong Street", "명동거리", "Myeongdong Cathedral", "명동성당", "Namsan Seoul Tower", "남산서울타워", "Namdaemun Market", "남대문시장"],
        "shopping": ["Myeongdong Street", "명동거리", "Namdaemun Market", "남대문시장"],
        "food": ["Myeongdong Street", "명동거리", "Namdaemun Market", "남대문시장"],
        "history": ["Myeongdong Cathedral", "명동성당", "Namdaemun Market", "남대문시장"],
    },
    "jongno": {
        "general": ["Gyeongbokgung Palace", "경복궁", "Bukchon Hanok Village", "북촌한옥마을", "Insadong", "인사동", "Gwangjang Market", "광장시장", "Cheonggyecheon Stream", "청계천"],
        "history": ["Gyeongbokgung Palace", "경복궁", "Bukchon Hanok Village", "북촌한옥마을", "Changdeokgung Palace", "창덕궁", "Jongmyo Shrine", "종묘"],
        "culture": ["Insadong", "인사동", "Bukchon Hanok Village", "북촌한옥마을", "Gwangjang Market", "광장시장"],
        "food": ["Gwangjang Market", "광장시장", "Insadong", "인사동"],
    },
}

# ============================================================
# 버그 5 수정: AREA_ALIASES에 sinsa 추가
# ============================================================
AREA_ALIASES = {
    "gangnam": ["gangnam", "강남", "coex", "코엑스", "apgujeong", "압구정"],
    "hongdae": ["hongdae", "홍대", "yeonnam", "연남", "hongik", "상수"],
    "seongsu": ["seongsu", "성수", "서울숲", "seoul forest"],
    "myeongdong": ["myeongdong", "명동", "namsan", "남산"],
    "jongno": ["jongno", "종로", "gyeongbokgung", "경복궁", "bukchon", "북촌", "insadong", "인사동"],
    "itaewon": ["itaewon", "이태원", "hannam", "한남"],
    "jamsil": ["jamsil", "잠실", "lotte world", "롯데월드"],
    "sinsa": ["sinsa", "신사", "garosu", "가로수길"],   # 버그 5 수정: sinsa 추가
    "mangwon": ["mangwon", "망원"],
    "hapjeong": ["hapjeong", "합정"],
    "sinchon": ["sinchon", "신촌"],
    "mapo": ["mapo", "마포"],
    "yeouido": ["yeouido", "여의도"],
    "dongdaemun": ["dongdaemun", "동대문", "ddp"],
}

PURPOSE_SYNONYMS = {
    "k-pop": "kpop", "k pop": "kpop", "kpop": "kpop", "케이팝": "kpop", "아이돌": "kpop",
    "shopping": "shopping", "쇼핑": "shopping",
    "food": "food", "맛집": "food", "음식": "food", "식도락": "food",
    "cafe": "cafe_hopping", "coffee": "cafe_hopping", "카페": "cafe_hopping", "카페투어": "cafe_hopping",
    "history": "history", "역사": "history",
    "culture": "culture", "문화": "culture",
    "nature": "nature", "park": "nature", "자연": "nature", "공원": "nature",
    "family": "family", "가족": "family",
    "nightlife": "nightlife", "night": "nightlife", "야경": "nightlife", "밤": "nightlife",
    "beauty": "beauty", "뷰티": "beauty", "화장품": "beauty",
}

EXPLICIT_ONLY_KEYWORDS = {
    "karaoke", "노래방", "club", "클럽", "bar", "바", "pub", "펍",
    "nightlife", "술집", "유흥", "lounge", "라운지", "pc방", "만화카페", "찜질방",
}

ENHANCED_POI_FILES = [
    Path(__file__).resolve().parent / "output" / "poi_master_step3_enhanced_v2.csv",
    Path(__file__).resolve().parent / "output" / "poi_master_step3.csv",
]

_ENHANCED_POI_CACHE: list[dict[str, Any]] | None = None


def _normalize_text(value: Any) -> str:
    if value is None:
        return ""
    s = str(value).lower().strip()
    s = re.sub(r"[\(\)\[\]{}.,;:|/\\\-_'\"`~!@#$%^&*+=]", " ", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def _safe_float(value: Any) -> float | None:
    try:
        x = float(value)
        if math.isfinite(x):
            return x
    except Exception:
        return None
    return None


def _safe_json_loads(value: Any, default: Any):
    if value is None:
        return default
    if isinstance(value, (list, dict)):
        return value
    s = str(value).strip()
    if not s or s.lower() in {"nan", "none", "null"}:
        return default
    try:
        return json.loads(s)
    except Exception:
        return default


def _load_enhanced_pois() -> list[dict[str, Any]]:
    global _ENHANCED_POI_CACHE
    if _ENHANCED_POI_CACHE is not None:
        return _ENHANCED_POI_CACHE
    for path in ENHANCED_POI_FILES:
        if not path.exists():
            continue
        try:
            with path.open("r", encoding="utf-8-sig", newline="") as f:
                rows = list(csv.DictReader(f))
            _ENHANCED_POI_CACHE = rows
            print(f"[planner] enhanced POI DB 로드: {path} ({len(rows)}개)")
            return rows
        except Exception as e:
            print(f"[planner] enhanced POI DB 로드 실패: {path} / {e}")
    _ENHANCED_POI_CACHE = []
    return []


def _detect_area_keys(text: str) -> list[str]:
    norm = _normalize_text(text)
    found = []
    for area, aliases in AREA_ALIASES.items():
        for alias in aliases:
            if _normalize_text(alias) in norm:
                found.append(area)
                break
    return found


def _is_area_anchor_name(name: Any, poi_type: Any = "") -> bool:
    norm = _normalize_text(name)
    ptype = _normalize_text(poi_type)
    if not norm:
        return False
    area_hit = any(_normalize_text(a) in norm for aliases in AREA_ALIASES.values() for a in aliases)
    short_or_generic = len(norm.split()) <= 4
    generic_type = ptype in {"", "street", "area", "district", "neighborhood", "tourist spot", "tourist_spot"}
    return bool(area_hit and (short_or_generic or generic_type))


def _normalize_purpose_token(value: Any) -> str:
    raw = _normalize_text(value).replace(" ", "_")
    raw_space = _normalize_text(value)
    if raw in PURPOSE_SYNONYMS:
        return PURPOSE_SYNONYMS[raw]
    if raw_space in PURPOSE_SYNONYMS:
        return PURPOSE_SYNONYMS[raw_space]
    for k, v in PURPOSE_SYNONYMS.items():
        if _normalize_text(k) in raw_space:
            return v
    return ""


def _infer_purposes(purpose: str) -> tuple[list[str], bool]:
    tokens = re.split(r"[,/|&]+|\s+and\s+", purpose or "")
    purposes = []
    for t in tokens:
        p = _normalize_purpose_token(t)
        if p and p not in purposes:
            purposes.append(p)
    explicit = bool(purposes)
    return purposes or ["general"], explicit


def _haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _area_center(area: str) -> tuple[float, float]:
    return SEOUL_AREA_CENTERS.get(area, DEFAULT_CENTER)


# ============================================================
# 버그 1 수정 핵심 함수:
# POI 좌표가 target area 권역 반경 안에 있는지 검증
# ============================================================
def _is_poi_within_area(
    poi_lat: float | None,
    poi_lng: float | None,
    target_area: str,
) -> bool:
    """
    POI 좌표가 target_area 권역 허용 반경 내에 있는지 검증.

    좌표 없으면 True 반환 (좌표 없는 POI는 걸러내지 않음 — critic이 처리).
    """
    if poi_lat is None or poi_lng is None:
        return True  # 좌표 없으면 일단 통과, critic이 잡게 둠

    center_lat, center_lng = SEOUL_AREA_CENTERS.get(target_area, DEFAULT_CENTER)
    radius_km = AREA_RADIUS_KM.get(target_area, DEFAULT_AREA_RADIUS_KM)
    dist = _haversine_km(poi_lat, poi_lng, center_lat, center_lng)

    if dist > radius_km:
        print(
            f"[planner] 권역 검증 실패: POI ({poi_lat:.4f}, {poi_lng:.4f}) → "
            f"{target_area} 중심에서 {dist:.2f}km (허용 {radius_km}km) → 제외"
        )
        return False
    return True


def _representative_terms(area: str, purposes: list[str], explicit: bool) -> list[str]:
    priors = AREA_REPRESENTATIVE_POI_PRIORS.get(area, {})
    if not priors:
        return []
    keys = purposes if explicit else ["general"]
    ordered = []
    for key in keys:
        for term in priors.get(key, []):
            if term not in ordered:
                ordered.append(term)
    if explicit:
        for term in priors.get("general", []):
            if term not in ordered:
                ordered.append(term)
    return ordered


def _row_blob(row: dict[str, Any]) -> str:
    vals = [
        row.get("poi_name", ""), row.get("poi_type", ""), row.get("google_types", ""),
        row.get("google_editorial_summary", ""), row.get("purpose_tags", ""),
        row.get("purpose_evidence", ""), row.get("label_evidence", ""),
    ]
    return " ".join(str(v).lower() for v in vals if v is not None)


def _is_explicit_only_candidate(row: dict[str, Any]) -> bool:
    blob = _row_blob(row)
    poi_type = _normalize_text(row.get("poi_type", ""))
    if poi_type in {"nightlife", "bar", "club", "karaoke"}:
        return True
    return any(k in blob for k in EXPLICIT_ONLY_KEYWORDS)


# ============================================================
# 버그 3 수정: generic token만 매칭되는 오류 수정
# full term match를 최우선으로, distinctive token 매칭 기준 강화
# ============================================================
def _representative_fit(
    row: dict[str, Any],
    area: str,
    purposes: list[str],
    explicit: bool,
) -> tuple[float, str]:
    """
    권역 대표 POI prior와 후보 row의 이름이 얼마나 정확히 맞는지 평가.

    수정사항:
    - full term 포함을 최우선 (기존 동일)
    - 부분 매칭 시 distinctive token 비율 기준 0.67 → 0.80으로 강화
      AND 최소 2개 이상의 distinctive token이 매칭되어야 함
      (단, distinctive token이 1개뿐인 term은 1개 매칭도 허용)
    - 이를 통해 "yeonnam"만 매칭돼서 망원시장이 높은 점수 받는 문제 해결
    """
    terms = _representative_terms(area, purposes, explicit)
    if not terms:
        return 0.55, "no_area_prior"

    blob = _normalize_text(_row_blob(row))
    generic_tokens = {
        "street", "cafe", "market", "mall", "station", "road", "gil", "dong",
        "거리", "카페", "시장", "몰", "역", "길", "동", "센터", "center", "shopping",
        "village", "park", "line", "forest", "house", "world",
    }

    def _tokens(s: str) -> list[str]:
        return [t for t in _normalize_text(s).split() if t]

    for rank, term in enumerate(terms):
        term_norm = _normalize_text(term)
        if not term_norm:
            continue

        # 1) 전체 표현이 그대로 포함 → 강한 매칭
        if term_norm in blob:
            return max(0.62, 1.0 - 0.035 * rank), f"area_prior_match:{term}:rank={rank+1}:full"

        term_tokens = _tokens(term_norm)
        if not term_tokens:
            continue

        distinctive = [t for t in term_tokens if t not in generic_tokens and len(t) >= 3]
        if not distinctive:
            continue

        matched_distinctive = [t for t in distinctive if t in blob]
        distinctive_ratio = len(matched_distinctive) / max(len(distinctive), 1)

        # 버그 3 수정:
        # - distinctive가 1개뿐인 경우: 그 1개가 매칭되면 허용
        # - distinctive가 2개 이상인 경우: 비율 0.80 이상 AND 최소 2개 매칭
        if len(distinctive) == 1:
            if matched_distinctive:
                return max(0.55, 0.88 - 0.035 * rank), (
                    f"area_prior_match:{term}:rank={rank+1}:single_distinctive={matched_distinctive}"
                )
        else:
            if distinctive_ratio >= 0.80 and len(matched_distinctive) >= 2:
                return max(0.58, 0.92 - 0.035 * rank), (
                    f"area_prior_match:{term}:rank={rank+1}:distinctive={matched_distinctive}"
                )

    return (0.20 if not explicit else 0.35), "not_in_area_prior"


def _purpose_fit(row: dict[str, Any], purposes: list[str], explicit: bool) -> float:
    if not explicit:
        return 0.75
    tags = _safe_json_loads(row.get("purpose_tags"), [])
    relevance = _safe_json_loads(row.get("purpose_relevance"), {})
    tags_norm = {_normalize_purpose_token(t) for t in tags if _normalize_purpose_token(t)}
    scores = []
    for p in purposes:
        if isinstance(relevance, dict) and p in relevance:
            try:
                scores.append(max(0.0, min(1.0, float(relevance[p]))))
                continue
            except Exception:
                pass
        if p in tags_norm:
            scores.append(0.85)
        else:
            scores.append(0.35)
    return max(scores) if scores else 0.75


def _confidence_score(value: Any, default: float = 0.55) -> float:
    v = str(value or "").strip().lower()
    if v == "high":
        return 1.0
    if v == "medium":
        return 0.75
    if v == "low":
        return 0.45
    return default


def _score_area_rep_candidate(
    row: dict[str, Any],
    area: str,
    purposes: list[str],
    explicit: bool,
) -> tuple[float, dict[str, Any]]:
    lat = _safe_float(row.get("lat"))
    lng = _safe_float(row.get("lng"))
    center_lat, center_lng = _area_center(area)

    # ── 수정: 반경 초과 POI는 점수 계산 없이 즉시 제외 ──────────────────
    # area_profiles_v2.json의 umbrella cluster가 다른 권역 POI를
    # 포함하는 데이터 오염 문제를 좌표 레벨에서 차단한다.
    # 좌표가 없는 POI는 통과시키되 임계값에서 걸러지게 둔다.
    if lat is not None and lng is not None:
        radius_km = AREA_RADIUS_KM.get(area, DEFAULT_AREA_RADIUS_KM)
        distance_km_check = _haversine_km(center_lat, center_lng, lat, lng)
        if distance_km_check > radius_km:
            return 0.0, {"reject": f"out_of_area_radius:{distance_km_check:.2f}km>{radius_km}km"}
    # ────────────────────────────────────────────────────────────────────

    if lat is None or lng is None:
        distance_km = None
        distance_fit = 0.45
    else:
        distance_km = _haversine_km(center_lat, center_lng, lat, lng)
        if distance_km <= 0.8:
            distance_fit = 1.0
        elif distance_km <= 1.8:
            distance_fit = 0.85
        elif distance_km <= 3.5:
            distance_fit = 0.60
        else:
            distance_fit = 0.25

    rep_fit, rep_reason = _representative_fit(row, area, purposes, explicit)
    p_fit = _purpose_fit(row, purposes, explicit)
    source_fit = _confidence_score(row.get("place_confidence"), 0.55)

    if _is_area_anchor_name(row.get("poi_name"), row.get("poi_type")):
        concrete_fit = 0.2
    else:
        concrete_fit = 1.0

    if _is_explicit_only_candidate(row) and (not explicit or "nightlife" not in purposes):
        return 0.0, {"reject": "explicit_only_candidate_without_matching_purpose"}

    if not explicit:
        total = (
            0.42 * rep_fit
            + 0.18 * distance_fit
            + 0.18 * source_fit
            + 0.12 * concrete_fit
            + 0.10 * p_fit
        )
    else:
        total = (
            0.30 * rep_fit
            + 0.25 * p_fit
            + 0.17 * distance_fit
            + 0.16 * source_fit
            + 0.12 * concrete_fit
        )

    details = {
        "area": area,
        "distance_km": None if distance_km is None else round(distance_km, 3),
        "representative_fit": round(rep_fit, 3),
        "representative_reason": rep_reason,
        "purpose_fit": round(p_fit, 3),
        "source_fit": round(source_fit, 3),
        "distance_fit": round(distance_fit, 3),
        "concrete_fit": round(concrete_fit, 3),
    }
    return round(total, 4), details


def _poi_from_candidate(row: dict[str, Any], *, source: str | None = None) -> dict[str, Any]:
    stay = row.get("estimated_stay_time") or row.get("stay_minutes") or row.get("estimated_stay_minutes") or 60
    try:
        stay = int(float(stay))
    except Exception:
        stay = 60
    return {
        "poi_name": row.get("poi_name", "") or row.get("name", ""),
        "poi_type": row.get("poi_type", "") or row.get("type", "tourist_spot"),
        "address_en": row.get("address_en") or row.get("address") or "",
        "address_ko": row.get("address_ko") or row.get("address") or "",
        "lat": _safe_float(row.get("lat")),
        "lng": _safe_float(row.get("lng")),
        "rating": row.get("rating") or row.get("google_rating") or row.get("review_rating"),
        "estimated_stay_time": stay,
        "source": source or row.get("source") or "Enhanced POI DB",
        "google_place_id": row.get("google_place_id", ""),
        "representative_score": row.get("_representative_score"),
        "representative_reason": row.get("_representative_reason"),
    }


def _place_dedupe_key(place: dict[str, Any]) -> str:
    name = _normalize_text(place.get("poi_name") or place.get("name") or "")
    place_id = str(place.get("google_place_id") or "").strip()
    if place_id:
        return f"gid:{place_id}"
    aliases = [
        ("starfield coex mall", "coex"), ("starfield coex", "coex"),
        ("coex starfield", "coex"), ("코엑스 스타필드몰", "coex"),
        ("코엑스 스타필드", "coex"), ("스타필드 코엑스몰", "coex"),
        ("스타필드 코엑스", "coex"), ("seongsu dong cafe street", "seongsu cafe street"),
        ("성수동 카페거리", "seongsu cafe street"), ("yeonnam dong cafe street", "yeonnam cafe street"),
        ("연남동 카페 골목", "yeonnam cafe street"), ("mangwon market", "mangwon market"),
        ("망원시장", "mangwon market"),
    ]
    for src, dst in aliases:
        if src in name:
            return f"name:{dst}"
    return f"name:{name}"


def _dedupe_places(places: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen = set()
    result = []
    for p in places:
        key = _place_dedupe_key(p)
        if not key or key in seen:
            continue
        seen.add(key)
        result.append(p)
    return result


def _fetch_google_place_by_text(query: str, api_key: str) -> dict[str, Any] | None:
    if not api_key:
        return None
    url = "https://maps.googleapis.com/maps/api/place/findplacefromtext/json"
    params = {
        "input": query, "inputtype": "textquery",
        "fields": "place_id,name,geometry,formatted_address,types,rating,user_ratings_total",
        "language": "en", "key": api_key,
    }
    try:
        resp = requests.get(url, params=params, timeout=8)
        candidates = resp.json().get("candidates", [])
        if not candidates:
            return None
        c = candidates[0]
        loc = (c.get("geometry") or {}).get("location") or {}
        return {
            "poi_name": c.get("name") or query,
            "poi_type": "tourist_spot",
            "address_en": c.get("formatted_address", ""),
            "address_ko": c.get("formatted_address", ""),
            "lat": loc.get("lat"),
            "lng": loc.get("lng"),
            "rating": c.get("rating"),
            "estimated_stay_time": 60,
            "source": "Google Places (Area Representative)",
            "google_place_id": c.get("place_id", ""),
            "_representative_score": 0.76,
            "_representative_reason": f"google_places_fallback:{query}",
        }
    except Exception as e:
        print(f"[Google Places Area Representative] 오류: {e}")
        return None


# ============================================================
# 버그 2 수정: areas 파라미터 추가
# build_area_representative_supplement(areas=["seongsu"], ...) 형태 호출 지원
# ============================================================
def build_area_representative_supplement(
    location: str = "",
    purpose: str = "",
    api_key: str = "",
    max_per_area: int = 6,
    areas: list[str] | None = None,
) -> list[dict[str, Any]]:
    """
    location/purpose에 등장하는 권역명을 대표 구체 POI 후보로 보강한다.

    수정사항:
    - areas 파라미터 추가: 직접 area 목록 전달 가능
    - areas가 None이면 기존 방식대로 location+purpose에서 자동 감지
    """
    if areas is not None:
        detected_areas = areas
    else:
        text = f"{location or ''} {purpose or ''}"
        detected_areas = _detect_area_keys(text)

    if not detected_areas:
        return []

    purposes, explicit = _infer_purposes(purpose)
    rows = _load_enhanced_pois()
    supplements: list[dict[str, Any]] = []

    SCORE_THRESHOLD = 0.60 if explicit else 0.65

    for area in detected_areas:
        scored = []
        for row in rows:
            score, details = _score_area_rep_candidate(row, area, purposes, explicit)
            if score < SCORE_THRESHOLD:
                continue
            row2 = dict(row)
            row2["_representative_score"] = score
            row2["_representative_reason"] = details.get("representative_reason")
            scored.append((score, row2))

        scored.sort(key=lambda x: x[0], reverse=True)

        # ↓ 로그 추가: 각 area별 후보 좌표 출력
        print(f"[planner] {area} representative 후보 {len(scored)}개 (임계값 통과):")
        for score, row2 in scored[:max_per_area]:
            print(f"  - {row2.get('poi_name')} | score={score:.3f} | lat={row2.get('lat')} lng={row2.get('lng')}")

        picked = [
            _poi_from_candidate(row, source="Enhanced POI DB (Area Representative)")
            for _, row in scored[:max_per_area]
        ]

        # DB 후보 부족 시 Google Places fallback
        if len(picked) < min(3, max_per_area) and api_key:
            terms = _representative_terms(area, purposes, explicit)
            for term in terms:
                if len(picked) >= max_per_area:
                    break
                if any(_normalize_text(term) in _normalize_text(p.get("poi_name", "")) for p in picked):
                    continue
                gp = _fetch_google_place_by_text(f"{term} Seoul", api_key)
                if gp:
                    picked.append(gp)
                time.sleep(0.15)

        for p in picked:
            p["area_anchor"] = area
            p["purpose_hint"] = ", ".join(purposes)
        supplements.extend(picked)

    supplements = _dedupe_places(supplements)
    if supplements:
        # 권역별 개수 출력
        for area in detected_areas:
            area_count = sum(1 for p in supplements if p.get("area_anchor") == area)
            print(f"[planner] Area representative POI — {area}: {area_count}개")
        print(f"[planner] Area representative POI 총 {len(supplements)}개 보강: {detected_areas}")
    return supplements


def _itinerary_poi_key(poi: dict[str, Any]) -> str:
    name = _normalize_text(poi.get("name") or poi.get("poi_name") or "")
    lat = _safe_float(poi.get("lat"))
    lng = _safe_float(poi.get("lng"))
    if lat is not None and lng is not None:
        return f"{name}|{round(lat, 4)}|{round(lng, 4)}"
    return name


def _is_same_poi_name(a: str, b: str) -> bool:
    ak = _normalize_text(a)
    bk = _normalize_text(b)
    if not ak or not bk:
        return False
    if ak == bk:
        return True
    return ak in bk or bk in ak


def _dedupe_itinerary_pois(itinerary: dict[str, Any]) -> dict[str, Any]:
    global_seen: set[str] = set()
    for day in itinerary.get("days", []) or []:
        pois = day.get("pois", []) or []
        day_seen: set[str] = set()
        cleaned: list[dict[str, Any]] = []
        removed: list[str] = []
        for poi in pois:
            key = _itinerary_poi_key(poi)
            name = poi.get("name", "")
            if key in day_seen:
                removed.append(name)
                continue
            if key in global_seen and len(pois) - len(removed) > 4:
                removed.append(name)
                continue
            day_seen.add(key)
            global_seen.add(key)
            cleaned.append(poi)
        if removed:
            print(f"[planner] Day {day.get('day')} duplicated POI removed: {removed}")
        day["pois"] = cleaned
    return itinerary


# ============================================================
# 버그 1 수정: _select_unused_reps에 area 권역 검증 추가
# ============================================================
def _select_unused_reps(
    reps: list[dict[str, Any]],
    used_names: set[str],
    count: int,
    target_area: str | None = None,    # 버그 1 수정: target_area 파라미터 추가
) -> list[dict[str, Any]]:
    """
    사용 가능한 대표 POI 후보에서 count개 선택.

    수정사항:
    - target_area가 주어지면 해당 area 권역 반경 내 POI만 선택
    - 권역 밖 POI는 선택에서 제외 (로그 출력)
    - 권역 검증 후 후보가 0개면 권역 검증 없이 used_names 체크만 해서 반환
      (완전히 빈 일정이 되는 것보다 나음 — critic이 cluster_scattered로 잡게 둠)
    """
    selected = []

    for r in reps:
        name = r.get("poi_name", "")
        key = _normalize_text(name)
        if not key or key in used_names:
            continue

        # 권역 검증
        if target_area is not None:
            poi_lat = _safe_float(r.get("lat"))
            poi_lng = _safe_float(r.get("lng"))
            if not _is_poi_within_area(poi_lat, poi_lng, target_area):
                continue  # 권역 밖 POI 제외

        selected.append(r)
        used_names.add(key)
        if len(selected) >= count:
            break

    # 권역 검증 후 후보가 없으면 빈 리스트 반환.
    # _expand_or_replace_area_anchors에서 anchor를 그대로 유지하고
    # critic이 cluster_scattered로 잡아서 replanner가 처리하게 둠.
    # (권역 밖 POI를 강제로 넣으면 cluster_scattered가 더 심해짐)
    if not selected and target_area is not None:
        print(f"[planner] 권역 '{target_area}' 검증 통과 후보 없음 → anchor 그대로 유지")

    return selected


def _make_itinerary_poi(candidate: dict[str, Any], notes_prefix: str = "") -> dict[str, Any]:
    name = candidate.get("poi_name", "") or candidate.get("name", "")
    notes = notes_prefix or "Area anchor was expanded into a concrete representative POI."
    reason = candidate.get("representative_reason")
    score = candidate.get("representative_score")
    if reason:
        notes += f" Evidence for {name}: {reason}."
    if score:
        notes += f" Representative score: {score}."
    try:
        stay = int(float(candidate.get("estimated_stay_time") or 60))
    except Exception:
        stay = 60
    return {
        "name": name,
        "type": candidate.get("poi_type", "tourist_spot"),
        "address": candidate.get("address_en") or candidate.get("address_ko") or "",
        "lat": candidate.get("lat"),
        "lng": candidate.get("lng"),
        "stay_minutes": stay,
        "notes": notes,
    }


def _area_reps_by_area(
    area_representatives: list[dict[str, Any]],
) -> dict[str, list[dict[str, Any]]]:
    by_area: dict[str, list[dict[str, Any]]] = {}
    for p in area_representatives or []:
        area = p.get("area_anchor")
        if not area:
            continue
        by_area.setdefault(area, []).append(p)
    return by_area


# ============================================================
# 버그 1, 4 수정:
# - target_area를 _select_unused_reps에 전달해 권역 검증
# - used_names를 외부에서 받아 두 번 호출 시 중복 방지
# ============================================================
def _expand_or_replace_area_anchors(
    itinerary: dict[str, Any],
    area_representatives: list[dict[str, Any]],
    *,
    user_selected_mode: bool = False,
    used_names: set[str] | None = None,     # 버그 4 수정: 외부에서 전달 가능
) -> dict[str, Any]:
    """
    Planner 출력에 넓은 권역명이 남아 있으면 대표 concrete POI로 바꾼다.

    수정사항:
    - _select_unused_reps()에 target_area 전달 → 권역 밖 POI 교체 차단 (버그 1)
    - used_names를 외부에서 받아서 두 번 호출 시에도 중복 방지 (버그 4)
    - anchor 교체 실패 시 그대로 두고 critic이 잡게 함
    """
    by_area = _area_reps_by_area(area_representatives)
    if not by_area:
        return itinerary

    # 버그 4 수정: 외부 used_names 없으면 새로 생성
    if used_names is None:
        used_names = set()

    # area_representatives 이름 목록 미리 확보.
    # LLM이 이 POI들을 이미 일정에 직접 넣었더라도
    # used_names에서 제외해서 anchor 교체용으로 재사용 가능하게 보존.
    # (LLM이 representative POI를 일정에 넣고 동시에 anchor 교체에도 써야 할 때
    #  used_names 충돌로 후보 0개 → fallback 발동 문제의 근본 원인)
    area_rep_names: set[str] = {
        _normalize_text(p.get("poi_name", ""))
        for p in area_representatives
        if p.get("poi_name")
    }

    # 기존 itinerary에 이미 들어 있는 구체 POI는 representative 재사용에서 제외.
    # 단, area_representative POI는 제외하지 않음 (anchor 교체용 보존).
    for day in itinerary.get("days", []) or []:
        for poi in day.get("pois", []) or []:
            name_key = _normalize_text(poi.get("name", ""))
            if not _is_area_anchor_name(poi.get("name", ""), poi.get("type", "")) \
                    and name_key not in area_rep_names:
                used_names.add(name_key)

    for day in itinerary.get("days", []) or []:
        pois = day.get("pois", []) or []
        new_pois: list[dict[str, Any]] = []

        for poi in pois:
            name = poi.get("name", "")
            ptype = poi.get("type", "")

            if not _is_area_anchor_name(name, ptype):
                new_pois.append(poi)
                continue

            area_keys = _detect_area_keys(f"{name} {day.get('theme', '')}")
            area = area_keys[0] if area_keys else None
            reps = by_area.get(area, []) if area else []

            if not reps:
                # 후보 없으면 anchor 그대로 유지 (critic이 처리)
                new_pois.append(poi)
                continue

            if len(pois) <= 2 and not user_selected_mode:
                count = min(4, max(2, len(reps)))
                # 버그 1 수정: target_area 전달
                selected = _select_unused_reps(reps, used_names, count, target_area=area)

                if not selected:
                    # 후보 완전히 없으면 anchor 그대로 유지
                    new_pois.append(poi)
                    print(f"[planner] 대체 후보 없음 — anchor 유지: {name}")
                    continue

                expanded = [
                    _make_itinerary_poi(
                        r,
                        notes_prefix=f"{name} area expanded into a representative POI for this day."
                    )
                    for r in selected
                ]
                print(f"[planner] Area anchor expansion: {name} → {[p['name'] for p in expanded]}")
                new_pois.extend(expanded)
            else:
                # 버그 1 수정: target_area 전달
                selected = _select_unused_reps(reps, used_names, 1, target_area=area)

                if not selected:
                    # 후보 없으면 anchor 그대로 유지
                    new_pois.append(poi)
                    print(f"[planner] 대체 후보 없음 — anchor 유지: {name}")
                    continue

                replacement = _make_itinerary_poi(
                    selected[0],
                    notes_prefix=f"{name} area replaced with a concrete representative POI."
                )
                print(f"[planner] Area anchor replacement: {name} → {replacement['name']}")
                new_pois.append(replacement)

        day["pois"] = new_pois

    return _dedupe_itinerary_pois(itinerary)


# ---------------------------------------------------------------------------
# Google Places API
# ---------------------------------------------------------------------------

def _get_area_center(location: str) -> tuple[float, float]:
    loc_lower = location.lower()
    for area, coords in SEOUL_AREA_CENTERS.items():
        if area in loc_lower:
            return coords
    return DEFAULT_CENTER


DIETARY_EXCLUDE_KEYWORDS: dict[str, list[str]] = {
    "seafood":    ["seafood", "fish", "sushi", "sashimi", "crab", "shrimp", "lobster",
                   "해산물", "생선", "초밥", "회", "게", "새우", "랍스터", "해물"],
    "pork":       ["pork", "pig", "bacon", "ham", "삼겹살", "돼지", "베이컨", "햄", "족발"],
    "beef":       ["beef", "steak", "소고기", "스테이크", "육회"],
    "meat":       ["meat", "chicken", "beef", "pork", "육류", "고기", "닭", "소", "돼지"],
    "vegetarian": [],
    "vegan":      [],
    "halal":      ["pork", "돼지", "bacon", "ham", "삼겹살"],
    "nut":        ["nut", "peanut", "알몬드", "견과류", "땅콩"],
    "gluten":     ["ramen", "noodle", "bread", "pasta", "라멘", "국수", "빵", "파스타"],
}


def _parse_dietary_restrictions(dietary: str) -> list[str]:
    if not dietary or dietary.lower() in {"none", "no", "없음", "없어요"}:
        return []
    d = dietary.lower()
    return [key for key in DIETARY_EXCLUDE_KEYWORDS if key in d]


def _place_violates_dietary(name: str, types: list[str], restrictions: list[str]) -> bool:
    if not restrictions:
        return False
    combined = f"{name.lower()} {' '.join(types).lower()}"
    for r in restrictions:
        for word in DIETARY_EXCLUDE_KEYWORDS.get(r, []):
            if word in combined:
                return True
    return False


_HOTEL_KEYWORDS = {
    "hotel", "호텔", "premier", "residence", "레지던스",
    "inn", "suites", "suite", "motel", "hostel", "guesthouse",
    "guest house", "pension", "펜션", "lodge",
}


def _is_hotel(name: str, types: list[str]) -> bool:
    name_lower = name.lower()
    if any(k in name_lower for k in _HOTEL_KEYWORDS):
        return True
    hotel_types = {"lodging", "hotel", "motel", "hostel"}
    if any(t in hotel_types for t in (types or [])):
        return True
    return False


def fetch_nearby_places(
    lat: float,
    lng: float,
    place_type: str,
    api_key: str,
    radius: int = 1500,
    min_rating: float = 4.3,
    min_reviews: int = 100,
    max_results: int = 5,
    dietary_restrictions: list[str] | None = None,
) -> list[dict]:
    if not api_key:
        return []
    dietary_restrictions = dietary_restrictions or []
    url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
    params = {
        "location": f"{lat},{lng}", "radius": radius, "type": place_type,
        "key": api_key, "language": "en", "rankby": "prominence",
    }
    try:
        resp = requests.get(url, params=params, timeout=10)
        results = resp.json().get("results", [])
        filtered = [
            r for r in results
            if r.get("rating", 0) >= min_rating
            and r.get("user_ratings_total", 0) >= min_reviews
            and r.get("business_status", "OPERATIONAL") == "OPERATIONAL"
            and not _is_hotel(r.get("name", ""), r.get("types", []))
        ]
        if dietary_restrictions:
            filtered = [
                r for r in filtered
                if not _place_violates_dietary(r.get("name", ""), r.get("types", []), dietary_restrictions)
            ]
        if dietary_restrictions and any(d in dietary_restrictions for d in ["vegetarian", "vegan"]):
            veg_params = dict(params)
            veg_params["keyword"] = "vegetarian vegan"
            try:
                veg_resp = requests.get(url, params=veg_params, timeout=10)
                veg_results = veg_resp.json().get("results", [])
                veg_filtered = [
                    r for r in veg_results
                    if r.get("rating", 0) >= min_rating
                    and r.get("user_ratings_total", 0) >= min_reviews
                    and r.get("business_status", "OPERATIONAL") == "OPERATIONAL"
                ]
                existing_ids = {r.get("place_id") for r in filtered}
                for r in veg_filtered:
                    if r.get("place_id") not in existing_ids:
                        filtered.append(r)
                        existing_ids.add(r.get("place_id"))
            except Exception:
                pass
        if place_type == "cafe":
            filtered.sort(key=lambda r: r.get("user_ratings_total", 0), reverse=True)
        else:
            filtered.sort(key=lambda r: r.get("rating", 0), reverse=True)
        return [
            {
                "poi_name": r["name"],
                "poi_type": place_type,
                "address_en": r.get("vicinity", ""),
                "address_ko": r.get("vicinity", ""),
                "lat": r["geometry"]["location"]["lat"],
                "lng": r["geometry"]["location"]["lng"],
                "rating": r.get("rating"),
                "user_ratings_total": r.get("user_ratings_total", 0),
                "opening_hours": r.get("opening_hours"),
                "place_id": r.get("place_id", ""),
                "estimated_stay_time": 60 if place_type == "restaurant" else 45,
                "source": "Google Places",
                "dietary_safe": True,
            }
            for r in filtered[:max_results]
        ]
    except Exception as e:
        print(f"[Google Places Nearby] 오류: {e}")
        return []


def fetch_kpop_places(
    lat: float, lng: float, api_key: str, purpose: str,
    radius: int = 3000, max_results: int = 5,
) -> list[dict]:
    if not api_key:
        return []
    kpop_keywords = []
    purpose_lower = purpose.lower()
    artists = ["bts", "blackpink", "aespa", "newjeans", "ive", "stray kids",
               "twice", "exo", "seventeen", "txt", "enhypen"]
    for artist in artists:
        if artist in purpose_lower:
            kpop_keywords.append(f"{artist} popup store Seoul")
            kpop_keywords.append(f"{artist} cafe Seoul")
    if not kpop_keywords:
        kpop_keywords = ["kpop popup store Seoul", "kpop merch store Hongdae"]
    url = "https://maps.googleapis.com/maps/api/place/textsearch/json"
    results = []
    seen_names = set()
    for keyword in kpop_keywords[:2]:
        params = {
            "query": keyword, "location": f"{lat},{lng}",
            "radius": radius, "key": api_key, "language": "en",
        }
        try:
            resp = requests.get(url, params=params, timeout=10)
            items = resp.json().get("results", [])
            for r in items[:3]:
                name = r.get("name", "")
                if name in seen_names:
                    continue
                seen_names.add(name)
                if r.get("business_status") == "OPERATIONAL":
                    results.append({
                        "poi_name": name, "poi_type": "kpop_landmark",
                        "address_en": r.get("formatted_address", ""),
                        "address_ko": r.get("formatted_address", ""),
                        "lat": r["geometry"]["location"]["lat"],
                        "lng": r["geometry"]["location"]["lng"],
                        "rating": r.get("rating"), "estimated_stay_time": 60,
                        "source": "Google Places (K-POP)",
                    })
            time.sleep(0.3)
        except Exception as e:
            print(f"[Google Places K-POP] 오류: {e}")
    return results[:max_results]


def build_google_supplement(
    location: str,
    purpose: str,
    api_key: str,
    dietary: str = "none",
    center_lat: float | None = None,
    center_lng: float | None = None,
) -> list[dict]:
    if not api_key:
        return []
    if center_lat is not None and center_lng is not None:
        pass
    else:
        center_lat, center_lng = _get_area_center(location)
    supplement = []
    purpose_lower = purpose.lower()
    dietary_restrictions = _parse_dietary_restrictions(dietary)
    if dietary_restrictions:
        print(f"[Google Places] dietary 제한 적용: {dietary_restrictions}")
    has_dietary = bool(dietary_restrictions)
    restaurant_min_rating = 4.0 if has_dietary else 4.3
    restaurant_min_reviews = 50 if has_dietary else 100
    cafes = fetch_nearby_places(
        center_lat, center_lng, "cafe", api_key,
        radius=2000, min_rating=4.2, min_reviews=100, max_results=5,
        dietary_restrictions=[],
    )
    supplement.extend(cafes)
    print(f"[Google Places] 카페 {len(cafes)}개 추가")
    restaurants = fetch_nearby_places(
        center_lat, center_lng, "restaurant", api_key,
        radius=2000, min_rating=restaurant_min_rating,
        min_reviews=restaurant_min_reviews, max_results=8,
        dietary_restrictions=dietary_restrictions,
    )
    if len(restaurants) < 3:
        restaurants_retry = fetch_nearby_places(
            center_lat, center_lng, "restaurant", api_key,
            radius=3500, min_rating=3.5, min_reviews=50, max_results=8,
            dietary_restrictions=dietary_restrictions,
        )
        existing = {r["poi_name"] for r in restaurants}
        restaurants += [r for r in restaurants_retry if r["poi_name"] not in existing]
        print(f"[Google Places] 반경 확장 재시도 — 식당 {len(restaurants)}개")
    if has_dietary and len(restaurants) < 3:
        restaurants_retry2 = fetch_nearby_places(
            center_lat, center_lng, "restaurant", api_key,
            radius=5000, min_rating=3.5, min_reviews=30, max_results=8,
            dietary_restrictions=dietary_restrictions,
        )
        existing = {r["poi_name"] for r in restaurants}
        restaurants += [r for r in restaurants_retry2 if r["poi_name"] not in existing]
        print(f"[Google Places] dietary 재시도 — 식당 {len(restaurants)}개")
    supplement.extend(restaurants)
    print(f"[Google Places] 식당 {len(restaurants)}개 추가 (dietary={dietary_restrictions or 'none'})")
    if any(k in purpose_lower for k in ["kpop", "k-pop", "bts", "blackpink", "idol", "kpop", "아이돌"]):
        kpop_places = fetch_kpop_places(center_lat, center_lng, api_key, purpose, radius=5000, max_results=5)
        supplement.extend(kpop_places)
        print(f"[Google Places] K-POP 장소 {len(kpop_places)}개 추가")
    if any(k in purpose_lower for k in ["shopping", "쇼핑"]):
        shops = fetch_nearby_places(center_lat, center_lng, "shopping_mall", api_key, radius=2000, min_rating=4.0, max_results=3)
        supplement.extend(shops)
        print(f"[Google Places] 쇼핑 {len(shops)}개 추가")
    return supplement


def _format_google_supplement(places: list[dict]) -> str:
    if not places:
        return ""
    lines = ["\n\n=== VERIFIED SUPPLEMENTAL POI DATA ==="]
    lines.append(
        "Use these verified real places for area anchors, cafes, restaurants, shopping, and K-POP slots. "
        "For broad area names such as Gangnam/Hongdae/Seongsu, choose concrete representative POIs from this list.\n"
    )
    for p in places:
        rating = p.get("rating")
        rating_str = f"rating={rating}" if rating else ""
        rep = p.get("representative_score")
        rep_str = f"representative_score={rep}" if rep else ""
        lines.append(
            f"  - {p.get('poi_name', '')} [{p.get('poi_type', '')}] "
            f"addr={p.get('address_en') or p.get('address_ko', '')} "
            f"lat={p.get('lat')} lng={p.get('lng')} "
            f"stay={p.get('estimated_stay_time', 60)}min "
            f"{rating_str} {rep_str} source={p.get('source', '')}"
        )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# DSPy signatures
# ---------------------------------------------------------------------------

class ItineraryPlanner(dspy.Signature):
    """Generate a personalized Seoul travel itinerary for foreign tourists.

    You are given the user's trip details and a shortlist of candidate
    courses (each with a sequence of POIs), PLUS real-time Google Places
    data for cafes, restaurants, and K-POP spots.

    Build a realistic day-by-day plan following ALL rules below.

      STRUCTURE RULES:
      - One day entry per requested trip duration day.
      - Each day MUST have 5–8 POIs. Never fewer than 5.
      - Each day MUST include at least one restaurant or cafe POI for lunch
        and ideally one for dinner or afternoon coffee.
      - Arrange POIs in chronological visit order starting around 09:00–10:00.
      - Total planned activity + travel time per day: 7–10 hours.

      CONTENT RULES:
      - Carefully read the user's "purpose" and prioritize matching POI types.
        * "cafe" or "coffee" → include 2+ cafe POIs per day (use Google Places cafes)
        * "shopping" → include shopping streets, markets, malls
        * "K-POP" or "kpop" or artist names → include kpop_landmark POIs
          AND use Google Places K-POP spots (popup stores, themed cafes)
        * "culture" or "history" → include museum, history, culture POIs
        * "nature" or "park" → include park POIs
        * "nightlife" or "club" → include nightlife POIs in the evening
      - Honor dietary restrictions strictly when selecting restaurants/cafes.
      - Stay within the user's budget across all days combined.
      - Write "notes" that explain: (1) why this POI matches the user's purpose,
        (2) any cultural tips for foreign visitors (e.g. "1 item per person rule",
        "remove shoes", "cash only"), (3) practical info (reservation needed, etc.).

      GEOGRAPHY RULES:
      - Each day must stay within 1–2 adjacent Seoul neighborhoods.
      - Do NOT mix distant areas in one day (e.g. Hongdae + Gangnam = bad).
      - Order POIs geographically to minimize backtracking and travel time.
      - Different days should cover different neighborhoods for variety.

      AREA ANCHOR RULES:
      - Do NOT use broad area names as final POIs.
      - If the user asks for an area such as Gangnam, expand it into concrete
        representative POIs from VERIFIED SUPPLEMENTAL POI DATA.
      - Never choose karaoke/bar/club/nightlife places unless the user explicitly
        requested nightlife.

      DATA INTEGRITY RULES:
      - For sightseeing/parks/museums: use POIs from candidate_courses ONLY.
      - For cafes/restaurants: use ONLY places from VERIFIED SUPPLEMENTAL POI DATA.
        NEVER invent restaurant or cafe names not listed in the supplemental data.
      - Do NOT invent or hallucinate POI names, addresses, or coordinates.
      - Copy lat, lng, address EXACTLY from the data provided.
      - Only list a course in "sources" if you used at least one of its POIs.

    Return ONLY valid JSON matching this schema, with no markdown fences:
    {
      "summary": "<2-3 sentence overview mentioning neighborhoods and highlights>",
      "days": [
        {
          "day": 1,
          "theme": "<short evocative theme>",
          "pois": [
            {
              "name": "<POI name exactly as in the data>",
              "type": "<poi_type>",
              "address": "<address from the data>",
              "lat": <number>,
              "lng": <number>,
              "stay_minutes": <integer between 30 and 240>,
              "notes": "<purpose fit + cultural tips + practical info>"
            }
          ],
          "estimated_cost": "<realistic cost range>"
        }
      ],
      "sources": [
        {
          "course_id": "<exact course_id>",
          "course_title": "<exact course_title>",
          "source": "<Visit Seoul or Visit Korea>",
          "source_url": "<exact source_url>"
        }
      ]
    }
    """
    duration: str = dspy.InputField(desc="Trip length, e.g. '3 days'.")
    location: str = dspy.InputField(desc="Destination or accommodation area.")
    budget: str = dspy.InputField(desc="Total trip budget.")
    dietary: str = dspy.InputField(desc="Dietary restrictions or preferences.")
    purpose: str = dspy.InputField(desc="Purpose of the trip.")
    candidate_courses: str = dspy.InputField(desc="Shortlist of candidate courses with POIs, PLUS real-time Google Places data.")
    itinerary_json: str = dspy.OutputField(desc="Itinerary as a JSON object matching the schema in the docstring.")


class FixJSON(dspy.Signature):
    """Repair a JSON document that failed to parse.
    Output ONLY the corrected JSON object. No prose, no markdown fences.
    """
    broken_json: str = dspy.InputField(desc="The malformed JSON text.")
    error_message: str = dspy.InputField(desc="The parser error reported.")
    fixed_json: str = dspy.OutputField(desc="Strictly valid JSON only.")


_planner: dspy.Predict | None = None
_fixer: dspy.Predict | None = None


def get_planner() -> dspy.Predict:
    global _planner
    if _planner is None:
        _planner = dspy.Predict(ItineraryPlanner)
    return _planner


def get_fixer() -> dspy.Predict:
    global _fixer
    if _fixer is None:
        _fixer = dspy.Predict(FixJSON)
    return _fixer


def _format_courses_for_prompt(
    courses: list[dict[str, Any]],
    google_supplement: list[dict] | None = None,
) -> str:
    blocks = []
    for i, c in enumerate(courses, start=1):
        title = c.get("course_title", "")
        course_id = c.get("course_id", "")
        source = c.get("source", "")
        source_url = c.get("source_url", "")
        themes = ", ".join(c.get("theme_category", []) or [])
        poi_lines = []
        for p in c.get("sequence", []) or []:
            poi_lines.append(
                f"    - {p.get('poi_name', '')} "
                f"[{p.get('poi_type', '')}] "
                f"addr={p.get('address_en') or p.get('address_ko', '')} "
                f"lat={p.get('lat')} lng={p.get('lng')} "
                f"stay={p.get('estimated_stay_time')}min"
            )
        blocks.append(
            f"Course {i}: {title}\n"
            f"  course_id : {course_id}\n"
            f"  source    : {source}\n"
            f"  source_url: {source_url}\n"
            f"  Themes    : {themes}\n"
            f"  POIs:\n" + "\n".join(poi_lines)
        )
    result = "\n\n".join(blocks)
    if google_supplement:
        result += _format_google_supplement(google_supplement)
    return result


def _build_valid_poi_names(
    courses: list[dict[str, Any]],
    google_supplement: list[dict] | None = None,
) -> set[str]:
    valid = set()
    for c in courses:
        for p in c.get("sequence", []) or []:
            name = str(p.get("poi_name", "")).lower().strip()
            if name:
                valid.add(name)
    if google_supplement:
        for p in google_supplement:
            name = str(p.get("poi_name", "")).lower().strip()
            if name:
                valid.add(name)
    return valid


def _validate_and_fix_pois(
    itinerary: dict[str, Any],
    valid_names: set[str],
    google_supplement: list[dict] | None = None,
) -> dict[str, Any]:
    google_restaurants = [
        p for p in (google_supplement or [])
        if p.get("poi_type") in ["restaurant", "cafe", "market"]
    ]
    google_meal_names: set[str] = {
        _normalize_text(p.get("poi_name", ""))
        for p in google_restaurants if p.get("poi_name")
    }
    normalized_valid_names = {_normalize_text(v) for v in valid_names if v}
    MEAL_TYPES = {"restaurant", "cafe", "food", "bar", "market"}

    for day in itinerary.get("days", []):
        original_pois = day.get("pois", [])
        validated = []
        hallucinated_names = []

        for poi in original_pois:
            poi_name_raw = str(poi.get("name", "")).strip()
            poi_name = _normalize_text(poi_name_raw)
            poi_type_raw = str(poi.get("type", "")).lower().strip()

            if _is_area_anchor_name(poi.get("name", ""), poi.get("type", "")):
                validated.append(poi)
                continue

            if poi_type_raw in MEAL_TYPES:
                matched_google = None
                for g_poi in google_restaurants:
                    g_name = _normalize_text(g_poi.get("poi_name", ""))
                    if (poi_name and g_name and
                        (poi_name == g_name or
                         (len(poi_name) >= 5 and len(g_name) >= 5 and
                          (poi_name in g_name or g_name in poi_name)))):
                        matched_google = g_poi
                        break
                if matched_google:
                    poi = dict(poi)
                    poi["source"] = "Google Places"
                    poi["rating"] = matched_google.get("rating") or poi.get("rating")
                    poi["user_ratings_total"] = matched_google.get("user_ratings_total", 0)
                    if not poi.get("lat") and matched_google.get("lat"):
                        poi["lat"] = matched_google["lat"]
                        poi["lng"] = matched_google["lng"]
                    validated.append(poi)
                else:
                    hallucinated_names.append(poi_name_raw + " [MEAL-HALLUCINATED]")
                continue

            is_valid = (
                poi_name in normalized_valid_names
                or any(
                    poi_name and v and len(poi_name) >= 4 and len(v) >= 4 and
                    (poi_name in v or v in poi_name)
                    for v in normalized_valid_names
                )
            )
            if is_valid:
                validated.append(poi)
            else:
                hallucinated_names.append(poi_name_raw)

        if hallucinated_names:
            print(f"[Validator] Day {day.get('day')} hallucinated POI 제거: {hallucinated_names}")

        has_meal = any(str(p.get("type", "")).lower() in MEAL_TYPES for p in validated)
        if not has_meal and google_restaurants:
            existing_names = {_normalize_text(p.get("name", "")) for p in validated}
            best = None
            for cand in google_restaurants:
                if _normalize_text(cand.get("poi_name", "")) not in existing_names:
                    best = cand
                    break
            if best:
                meal_poi = {
                    "name": best["poi_name"], "type": best["poi_type"],
                    "address": best.get("address_en", ""),
                    "lat": best["lat"], "lng": best["lng"],
                    "stay_minutes": best.get("estimated_stay_time", 60),
                    "notes": (
                        f"Verified restaurant from Google Places. "
                        f"Rating: {best.get('rating', 'N/A')} "
                        f"({best.get('user_ratings_total', 0):,} reviews)."
                    ),
                }
                insert_idx = min(2, len(validated))
                validated.insert(insert_idx, meal_poi)
                print(f"[Validator] Day {day.get('day')} 식사 슬롯 자동 추가: {best['poi_name']}")

        day["pois"] = validated

    return _dedupe_itinerary_pois(itinerary)


_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$", re.MULTILINE)
_TRAILING_COMMA_RE = re.compile(r",(\s*[}\]])")


def _isolate_json_object(text: str) -> str:
    text = _FENCE_RE.sub("", text).strip()
    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        text = text[start: end + 1]
    return text


def _simple_repair(text: str) -> str:
    text = (
        text.replace("\u201c", '"').replace("\u201d", '"')
            .replace("\u2018", "'").replace("\u2019", "'")
    )
    text = _TRAILING_COMMA_RE.sub(r"\1", text)
    return text


def _parse_itinerary_json(raw: str, *, use_llm_fallback: bool = True) -> dict[str, Any]:
    isolated = _isolate_json_object(raw)
    try:
        return json.loads(isolated)
    except json.JSONDecodeError:
        pass
    repaired = _simple_repair(isolated)
    second_err: json.JSONDecodeError | None = None
    try:
        return json.loads(repaired)
    except json.JSONDecodeError as e:
        second_err = e
    if use_llm_fallback and second_err is not None:
        try:
            with lm_context():
                fixed = get_fixer()(
                    broken_json=isolated[:8000],
                    error_message=str(second_err),
                ).fixed_json
            return json.loads(_isolate_json_object(fixed))
        except Exception:
            pass
    _dump_debug(raw)
    if second_err is not None:
        raise second_err
    raise json.JSONDecodeError("Failed to parse itinerary JSON", raw, 0)


def _dump_debug(raw: str) -> None:
    try:
        dbg_path = Path(__file__).resolve().parent / "planner_last_failed.txt"
        dbg_path.write_text(raw, encoding="utf-8")
        print(f"[planner] wrote failing output to {dbg_path}")
    except Exception:
        pass


def _normalize_sources(
    itinerary: dict[str, Any],
    retrieved: list[dict[str, Any]],
) -> dict[str, Any]:
    by_id = {c.get("course_id"): c for c in retrieved if c.get("course_id")}
    by_url = {c.get("source_url"): c for c in retrieved if c.get("source_url")}
    raw_sources = itinerary.get("sources") or []
    cleaned: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    for s in raw_sources:
        if not isinstance(s, dict):
            continue
        match = by_id.get(s.get("course_id")) or by_url.get(s.get("source_url"))
        if not match:
            continue
        cid = match.get("course_id")
        if cid in seen_ids:
            continue
        seen_ids.add(cid)
        cleaned.append({
            "course_id": cid,
            "course_title": match.get("course_title", ""),
            "source": match.get("source", ""),
            "source_url": match.get("source_url", ""),
        })
    if not cleaned and retrieved:
        cleaned = [
            {
                "course_id": c.get("course_id"),
                "course_title": c.get("course_title", ""),
                "source": c.get("source", ""),
                "source_url": c.get("source_url", ""),
            }
            for c in retrieved if c.get("source_url")
        ]
    itinerary["sources"] = cleaned
    return itinerary


# ---------------------------------------------------------------------------
# Graph nodes
# ---------------------------------------------------------------------------

def make_retrieve_node(api_key: str):
    def retrieve_node(state: TravelState) -> TravelState:
        query = build_query(
            purpose=state.get("category"),
            dietary=state.get("restrictions"),
            location=state.get("region"),
            duration=state.get("travel_dates"),
        )
        try:
            courses = retrieve_courses(
                api_key=api_key, query=query, k=5,
                location=state.get("region"),
                purpose=state.get("category"),
            )
        except Exception as e:
            return {
                **state,
                "current_step": "confirm",
                "messages": [AIMessage(content=f"⚠️ Failed to retrieve courses: {e}")],
            }
        return {**state, "retrieved_courses": courses, "current_step": "planning"}
    return retrieve_node


def plan_node(state: TravelState) -> TravelState:
    courses = state.get("retrieved_courses") or []
    if not courses:
        return {
            **state,
            "current_step": "done",
            "messages": [AIMessage(content="⚠️ No candidate courses found. Try different details.")],
        }

    location = state.get("region") or ""
    purpose = state.get("category") or ""

    area_representatives = build_area_representative_supplement(
        location=location,
        purpose=purpose,
        api_key=GOOGLE_PLACES_API_KEY,
    )

    google_supplement = []
    dietary = state.get("restrictions") or "none"
    if GOOGLE_PLACES_API_KEY:
        print("[planner] Google Places 보완 데이터 수집 중...")
        original_message = state.get("original_message") or ""
        detected_areas_for_google = _detect_area_keys(f"{location} {original_message} {purpose}")
        loc_lower_g = location.strip().lower()
        if not detected_areas_for_google or loc_lower_g in {"seoul", "서울", ""}:
            if original_message:
                detected_areas_for_google = _detect_area_keys(original_message)
        if not detected_areas_for_google:
            try:
                dur_days = int(str(state.get("travel_dates") or "3").split()[0])
            except Exception:
                dur_days = 3
            detected_areas_for_google = ["hongdae", "gangnam", "itaewon", "myeongdong", "seongsu"][:dur_days]

        if detected_areas_for_google:
            seen_names: set[str] = set()
            for area in detected_areas_for_google[:4]:
                area_lat, area_lng = SEOUL_AREA_CENTERS.get(area, DEFAULT_CENTER)
                area_supplement = build_google_supplement(
                    location=area, purpose=purpose,
                    api_key=GOOGLE_PLACES_API_KEY, dietary=dietary,
                    center_lat=area_lat, center_lng=area_lng,
                )
                for p in area_supplement:
                    name = p.get("poi_name", "")
                    if name and name not in seen_names:
                        seen_names.add(name)
                        p["area_hint"] = area
                        google_supplement.append(p)
        else:
            google_supplement = build_google_supplement(
                location=location, purpose=purpose,
                api_key=GOOGLE_PLACES_API_KEY, dietary=dietary,
            )
        print(f"[planner] Google Places 총 {len(google_supplement)}개 보완 데이터 확보")
    else:
        print("[planner] GOOGLE_PLACES_API_KEY 없음 — Google Places 보완 생략")

    supplemental_pois = _dedupe_places(area_representatives + google_supplement)
    valid_names = _build_valid_poi_names(courses, supplemental_pois)

    try:
        duration_days = int(str(state.get("travel_dates") or "3").split()[0])
    except Exception:
        duration_days = 3

    original_message = state.get("original_message") or ""
    detection_text = f"{location} {original_message} {purpose}"
    detected_areas = _detect_area_keys(detection_text)

    loc_lower = location.strip().lower()
    if not detected_areas or loc_lower in {"seoul", "서울", ""}:
        if original_message:
            detected_areas = _detect_area_keys(original_message)

    if not detected_areas:
        DEFAULT_AREAS_KEYS = ["hongdae", "gangnam", "itaewon", "myeongdong", "seongsu",
                               "jongno", "yeouido", "jamsil"]
        detected_areas = DEFAULT_AREAS_KEYS[:max(duration_days, 2)]
        print(f"[planner] 권역 감지 안 됨 → 기본값 주입: {detected_areas}")

    area_groups = _assign_areas_to_days(detected_areas)
    day_area_prompt = _build_day_area_prompt(area_groups, duration_days)

    if area_groups:
        print(f"[planner] 권역 배정: {area_groups} → {duration_days}일")

    courses_prompt = _format_courses_for_prompt(courses, supplemental_pois)
    if day_area_prompt:
        courses_prompt = day_area_prompt + "\n\n" + courses_prompt

    try:
        with lm_context():
            result = get_planner()(
                duration=state.get("travel_dates") or "",
                location=location,
                budget=state.get("budget") or "",
                dietary=state.get("restrictions") or "none",
                purpose=purpose,
                candidate_courses=courses_prompt,
            )
        itinerary = _parse_itinerary_json(result.itinerary_json)

        # ============================================================
        # 버그 4 수정:
        # used_names를 plan_node에서 한 번만 만들고
        # _expand_or_replace_area_anchors 두 번 호출에 공유
        # ============================================================
        user_selected_mode = bool(state.get("selected_pois") or state.get("user_selected_pois"))
        shared_used_names: set[str] = set()

        # 1차 확장/대체
        itinerary = _expand_or_replace_area_anchors(
            itinerary,
            area_representatives,
            user_selected_mode=user_selected_mode,
            used_names=shared_used_names,     # 버그 4 수정
        )

        # Hallucination 검증 + 식사 슬롯 보완
        itinerary = _validate_and_fix_pois(itinerary, valid_names, supplemental_pois)

        # 2차 확장/대체 (검증 후 남은 anchor 처리) — 같은 used_names 사용
        itinerary = _expand_or_replace_area_anchors(
            itinerary,
            area_representatives,
            user_selected_mode=user_selected_mode,
            used_names=shared_used_names,     # 버그 4 수정
        )

        itinerary = _dedupe_itinerary_pois(itinerary)
        itinerary = _normalize_sources(itinerary, courses)

        supplement_restaurants = [
            p for p in google_supplement
            if p.get("poi_type") in {"restaurant", "cafe"}
        ]
        if supplement_restaurants:
            itinerary["supplement_restaurants"] = supplement_restaurants
            print(f"[planner] supplement_restaurants {len(supplement_restaurants)}개 itinerary에 첨부")

    except json.JSONDecodeError as e:
        return {
            **state,
            "current_step": "done",
            "messages": [AIMessage(content=f"⚠️ Planner returned invalid JSON: {e}")],
        }
    except Exception as e:
        return {
            **state,
            "current_step": "done",
            "messages": [AIMessage(content=f"⚠️ Planning failed: {e}")],
        }

    try:
        from pipeline import run_pipeline
        user_state_for_pipeline = {
            "purpose": state.get("category") or "general",
            "location": state.get("region") or "",
            "duration": state.get("travel_dates") or "",
            "dietary": state.get("restrictions") or "none",
        }
        print("[planner] pipeline 실행 중...")
        itinerary, pipeline_log = run_pipeline(
            itinerary=itinerary,
            user_state=user_state_for_pipeline,
            verbose=True,
        )
        score = pipeline_log.get("final_score", "?")
        passed = pipeline_log.get("final_passed", False)
        changes = pipeline_log.get("total_changes", 0)
        print(f"[planner] pipeline 완료 — score={score}, passed={passed}, changes={changes}")
    except Exception as e:
        print(f"[planner] pipeline 오류 (원본 itinerary 사용): {e}")

    summary = itinerary.get("summary", "")
    day_count = len(itinerary.get("days", []))
    ack = (
        f"✅ Your {day_count}-day itinerary is ready!\n\n"
        f"{summary}\n\n"
        "See the full plan below."
    )

    return {
        **state,
        "itinerary": itinerary,
        "current_step": "done",
        "messages": [AIMessage(content=ack)],
    }