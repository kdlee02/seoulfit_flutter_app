# 여행 중 도우미 (On-Trip Help) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chat 탭에 "여행 중" 모드를 추가해 여권분실·응급실·주변추천 세 기능을 제공한다.

**Architecture:** 여권분실은 앱에 번들한 정적 JSON으로 네트워크 없이 동작한다. 응급실과 주변추천은 FastAPI 백엔드의 신규 라우터 `live_help.py`를 거친다 — API 키를 클라이언트에 노출하지 않기 위해서다. 챗봇 UI는 퀵액션 3버튼이며 LLM을 호출하지 않는다.

**Tech Stack:** FastAPI · httpx · Flutter · provider · geolocator · latlong2 · url_launcher

**Spec:** [docs/superpowers/specs/2026-08-21-on-trip-help-design.md](../specs/2026-08-21-on-trip-help-design.md)

## Global Constraints

- 백엔드 파이썬은 **`backend/venv/bin/python`** 을 쓴다. 테스트도 이 인터프리터로 실행한다
- 백엔드 테스트는 pytest가 아니라 **`assert` + `if __name__ == "__main__"`** 형식이다 (`backend/test_*.py` 기존 파일들과 동일)
- 신규 파이썬 모듈은 `backend/` 최상단에 평평하게 둔다. `api.py`가 `sys.path`에 자기 디렉터리를 넣으므로 **절대 임포트**(`from live_help import router`)를 쓴다
- Flutter 색·간격 값은 **`lib/theme/app_theme.dart`의 토큰**만 쓴다. 새 값을 하드코딩하기 전에 `seoulfit-flutter-ui` 스킬을 확인한다
- Places 반경 상한은 **1000m**. 못 채우면 있는 만큼만 반환한다
- `hvec <= 0` 은 **"만원"**. 음수를 숫자로 렌더링하지 않는다
- `user_ratings_total` / `rating` 은 **결측 가능**. `.get(..., 0)` / null 체크 필수
- E-Gen `EGEN_API_KEY` 는 data.go.kr **Decoding** 키다

---

### Task 1: 백엔드 — 주변 추천 `/nearby`

**Files:**
- Create: `backend/live_help.py`
- Create: `backend/test_live_help.py`
- Modify: `backend/api.py` (라우터 마운트)

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces:
  - `haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float`
  - `filter_places(results: list[dict], lat: float, lng: float, min_reviews: int = 50) -> dict[str, dict]`
  - `router: APIRouter` — `POST /nearby`
  - 응답: `{"radius_used": int, "places": [{name, address, lat, lng, distance_m, rating, reviews, open_now, place_id}]}`

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`backend/test_live_help.py` 를 새로 만든다.

```python
"""Self-check for live_help (주변 추천 · 응급실).

네트워크를 타지 않는 순수 함수만 검증한다 — 거리 계산, Places 필터, E-Gen 조인.
실호출 검증은 설계 단계에서 이미 끝냈고, 여기서는 조용히 틀리면 위험한 로직만 잡는다.

Run:  backend/venv/bin/python backend/test_live_help.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from live_help import filter_places, haversine_m  # noqa: E402


def test_haversine():
    # 위도 1도는 약 111km. 경도 0도 차이일 때 가장 깔끔하게 확인된다.
    d = haversine_m(37.0, 127.0, 38.0, 127.0)
    assert 110_000 < d < 112_000, d
    assert haversine_m(37.5, 127.0, 37.5, 127.0) == 0


def test_filter_places_drops_low_review_counts():
    results = [
        # 좌표·평점·리뷰수는 신금호 이디야 실측값이다. 155m 는 하버사인 실계산 결과.
        {"place_id": "a", "name": "Busy Cafe", "user_ratings_total": 80, "rating": 4.1,
         "vicinity": "Seongdong-gu", "geometry": {"location": {"lat": 37.553945, "lng": 127.019638}}},
        {"place_id": "b", "name": "Quiet Cafe", "user_ratings_total": 3, "rating": 5.0,
         "vicinity": "Seongdong-gu", "geometry": {"location": {"lat": 37.5537, "lng": 127.0214}}},
    ]
    out = filter_places(results, 37.553675, 127.021367)
    assert set(out) == {"a"}, out
    assert out["a"]["distance_m"] == 155, out["a"]["distance_m"]
    assert out["a"]["reviews"] == 80


def test_filter_places_treats_missing_review_key_as_zero():
    # 구글은 리뷰가 0인 업소에서 user_ratings_total 과 rating 을 아예 뺀다.
    # KeyError 로 터지지 않고, 리뷰 0개로 읽혀 필터에서 떨어져야 한다.
    results = [
        {"place_id": "new", "name": "Brand New Cafe",
         "geometry": {"location": {"lat": 37.5537, "lng": 127.0214}}},
    ]
    assert filter_places(results, 37.553675, 127.021367) == {}
    # min_reviews 를 0 으로 낮추면 통과하되 rating 은 None 으로 남는다.
    kept = filter_places(results, 37.553675, 127.021367, min_reviews=0)
    assert kept["new"]["rating"] is None
    assert kept["new"]["reviews"] == 0
    assert kept["new"]["open_now"] is None


def test_filter_places_skips_rows_without_coordinates():
    results = [{"place_id": "x", "name": "No Geo", "user_ratings_total": 999}]
    assert filter_places(results, 37.5, 127.0) == {}


if __name__ == "__main__":
    test_haversine()
    test_filter_places_drops_low_review_counts()
    test_filter_places_treats_missing_review_key_as_zero()
    test_filter_places_skips_rows_without_coordinates()
    print("live_help self-check ok")
```

- [ ] **Step 2: 실패를 확인한다**

Run: `backend/venv/bin/python backend/test_live_help.py`
Expected: FAIL — `ModuleNotFoundError: No module named 'live_help'`

- [ ] **Step 3: `live_help.py` 를 구현한다**

`backend/live_help.py` 를 새로 만든다.

```python
"""live_help.py — 여행 중 도우미 라우터 (주변 추천 · 응급실).

api.py 에 include_router 로 마운트한다.
여권분실은 앱에 번들한 assets/data/embassies.json 을 쓰므로 여기 없다 —
여권을 잃은 사람은 데이터로밍이 끊겨 있을 수 있다.
"""
from __future__ import annotations

import math
import os

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(tags=["live-help"])

_PLACES_URL = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"

# 반경 상한 1000m. 상한이 없으면 주거지역에서 5개를 채우려고 2km 밖까지 끌어와
# 도보 20분 거리를 '내 위치 기반 추천'으로 내놓는다. 못 채우면 적게 준다.
_RADII = (500, 1000)
_MIN_REVIEWS = 50


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """두 좌표 사이 대권거리(미터)."""
    r = 6371000.0
    rad = math.radians
    a = (
        math.sin(rad(lat2 - lat1) / 2) ** 2
        + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(rad(lng2 - lng1) / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def filter_places(
    results: list[dict], lat: float, lng: float, min_reviews: int = _MIN_REVIEWS
) -> dict[str, dict]:
    """Places 결과를 리뷰 수로 거르고 거리를 붙여 place_id 로 키잉해 돌려준다.

    구글은 리뷰가 하나도 없는 업소에서 user_ratings_total 과 rating 을 아예 빼고
    내려준다. 키 없음 = 리뷰 0개 이므로 0 으로 읽는 것이 크래시 회피가 아니라
    의미상 정확하고, 그러면 필터가 알아서 걸러낸다.
    """
    out: dict[str, dict] = {}
    for p in results:
        if p.get("user_ratings_total", 0) < min_reviews:
            continue
        loc = (p.get("geometry") or {}).get("location") or {}
        if "lat" not in loc or "lng" not in loc:
            continue
        pid = p.get("place_id") or p.get("name", "")
        out[pid] = {
            "name": p.get("name", ""),
            "address": p.get("vicinity", ""),
            "lat": loc["lat"],
            "lng": loc["lng"],
            "distance_m": round(haversine_m(lat, lng, loc["lat"], loc["lng"])),
            "rating": p.get("rating"),
            "reviews": p.get("user_ratings_total", 0),
            "open_now": (p.get("opening_hours") or {}).get("open_now"),
            "place_id": p.get("place_id", ""),
        }
    return out


class NearbyRequest(BaseModel):
    lat: float
    lng: float
    type: str = "cafe"
    want: int = 5


@router.post("/nearby")
def nearby(req: NearbyRequest):
    """현재 위치 도보권의 카페/음식점을 거리순으로 돌려준다."""
    key = os.getenv("GOOGLE_PLACES_API_KEY", "")
    if not key:
        raise HTTPException(status_code=500, detail="GOOGLE_PLACES_API_KEY is not set")

    found: dict[str, dict] = {}
    radius_used = _RADII[0]
    for radius in _RADII:
        radius_used = radius
        # rankby=distance 는 radius 와 함께 못 쓴다. 반경 확장 전략을 쓰므로
        # radius 를 쓰고 거리 정렬은 하버사인으로 직접 한다.
        try:
            data = httpx.get(
                _PLACES_URL,
                params={
                    "location": f"{req.lat},{req.lng}",
                    "radius": radius,
                    "type": req.type,
                    "key": key,
                    "language": "en",
                },
                timeout=15,
            ).json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=502, detail=f"Places request failed: {e}")

        status = data.get("status")
        if status not in ("OK", "ZERO_RESULTS"):
            raise HTTPException(
                status_code=502,
                detail=f"Places error {status}: {data.get('error_message', '')}",
            )
        found.update(filter_places(data.get("results", []), req.lat, req.lng))
        if len(found) >= req.want:
            break

    places = sorted(found.values(), key=lambda x: x["distance_m"])[: req.want]
    return {"radius_used": radius_used, "places": places}
```

- [ ] **Step 4: 테스트 통과를 확인한다**

Run: `backend/venv/bin/python backend/test_live_help.py`
Expected: PASS — `live_help self-check ok`

- [ ] **Step 5: 라우터를 마운트한다**

`backend/api.py` 에서 lens 라우터 임포트 바로 아래에 추가한다.

기존 (`backend/api.py:62` 부근):
```python
from graph import build_graph, clear_thread
from lens import router as lens_router
from guardrail_gate import is_blocked
```

변경 후:
```python
from graph import build_graph, clear_thread
from lens import router as lens_router
from live_help import router as live_help_router
from guardrail_gate import is_blocked
```

기존 (`backend/api.py:104` 부근):
```python
# Lens (camera → landmark) endpoints
app.include_router(lens_router)
```

변경 후:
```python
# Lens (camera → landmark) endpoints
app.include_router(lens_router)

# 여행 중 도우미 (주변 추천 · 응급실) endpoints
app.include_router(live_help_router)
```

- [ ] **Step 6: 실서버 스모크**

터미널 A:
```bash
cd backend && venv/bin/python -m uvicorn api:app --port 8000
```

터미널 B:
```bash
curl -s -X POST http://localhost:8000/nearby \
  -H 'Content-Type: application/json' \
  -d '{"lat":37.5563,"lng":126.9236,"type":"cafe","want":5}' | head -40
```

Expected: `radius_used` 가 500, `places` 5건, 각 항목의 `distance_m` 이 오름차순.

- [ ] **Step 7: 커밋**

```bash
git add backend/live_help.py backend/test_live_help.py backend/api.py
git commit -m "feat(backend): add /nearby place recommendations with radius expansion"
```

---

### Task 2: 백엔드 — 응급실 `/emergency-rooms`

**Files:**
- Modify: `backend/live_help.py` (E-Gen 파트 추가)
- Modify: `backend/test_live_help.py` (조인 테스트 추가)

**Interfaces:**
- Consumes: Task 1의 `router`
- Produces:
  - `parse_beds(items: list) -> dict[str, dict]` — hpid → `{er_phone, hvec, updated_at}`
  - `join_er(near_items: list, beds: dict[str, dict], want: int) -> list[dict]`
  - `POST /emergency-rooms` → `{"updated_at": str, "hospitals": [{name, address, lat, lng, distance_km, er_phone, beds, beds_state, updated_at}]}`
  - `beds_state` 는 `"available"` 또는 `"full"`

- [ ] **Step 1: 실패하는 테스트를 추가한다**

`backend/test_live_help.py` 의 임포트 줄을 바꾸고 테스트를 덧붙인다.

임포트를 이렇게 바꾼다:
```python
import xml.etree.ElementTree as ET

from live_help import filter_places, haversine_m, join_er, parse_beds  # noqa: E402
```

파일의 `if __name__ == "__main__":` 블록 **위에** 다음을 추가한다:

```python
_BEDS_XML = """<response><body><items>
  <item><hpid>A1100007</hpid><dutyName>세브란스</dutyName>
        <dutyTel3>02-2227-7777</dutyTel3><hvec>4</hvec><hvidate>20260821182414</hvidate></item>
  <item><hpid>A1100028</hpid><dutyName>서울아산</dutyName>
        <dutyTel3>02-3010-3333</dutyTel3><hvec>-6</hvec><hvidate>20260821182414</hvidate></item>
</items></body></response>"""

_NEAR_XML = """<response><body><items>
  <item><hpid>A1100028</hpid><dutyName>서울아산</dutyName><dutyAddr>서울 송파구</dutyAddr>
        <latitude>37.5270</latitude><longitude>127.1080</longitude>
        <distance>9.20</distance><dutyTel1>02-3010-3114</dutyTel1></item>
  <item><hpid>A1100007</hpid><dutyName>세브란스</dutyName><dutyAddr>서울 서대문구 연세로 50-1</dutyAddr>
        <latitude>37.5621</latitude><longitude>126.9408</longitude>
        <distance>1.65</distance><dutyTel1>02-2228-0114</dutyTel1></item>
  <item><hpid>A9999999</hpid><dutyName>응급실 없는 일반병원</dutyName><dutyAddr>서울 마포구</dutyAddr>
        <latitude>37.5525</latitude><longitude>126.9337</longitude>
        <distance>0.98</distance><dutyTel1>02-337-7582</dutyTel1></item>
</items></body></response>"""


def test_parse_beds_reads_er_phone_and_capacity():
    beds = parse_beds(ET.fromstring(_BEDS_XML).findall(".//item"))
    assert set(beds) == {"A1100007", "A1100028"}
    # 응급실 직통번호(dutyTel3)는 실시간 병상 응답에만 있다. 위치조회의
    # dutyTel1 은 병원 대표번호라 새벽에 받지 않는다.
    assert beds["A1100007"]["er_phone"] == "02-2227-7777"
    assert beds["A1100007"]["hvec"] == 4
    assert beds["A1100028"]["hvec"] == -6


def test_join_er_drops_hospitals_without_live_beds():
    near = ET.fromstring(_NEAR_XML).findall(".//item")
    beds = parse_beds(ET.fromstring(_BEDS_XML).findall(".//item"))
    rows = join_er(near, beds, want=5)
    # 실시간 목록에 없는 A9999999 는 응급실 미운영이라 조인에서 떨어진다.
    assert [r["name"] for r in rows] == ["세브란스", "서울아산"], rows
    assert rows[0]["distance_km"] == 1.65
    assert rows[0]["er_phone"] == "02-2227-7777"
    assert rows[0]["address"] == "서울 서대문구 연세로 50-1"


def test_join_er_marks_negative_capacity_as_full():
    # hvec 는 정원 초과를 음수로 표현한다. '-6 beds' 로 렌더링되면 안 된다.
    near = ET.fromstring(_NEAR_XML).findall(".//item")
    beds = parse_beds(ET.fromstring(_BEDS_XML).findall(".//item"))
    rows = {r["name"]: r for r in join_er(near, beds, want=5)}
    assert rows["세브란스"]["beds_state"] == "available"
    assert rows["서울아산"]["beds_state"] == "full"


def test_join_er_respects_want():
    near = ET.fromstring(_NEAR_XML).findall(".//item")
    beds = parse_beds(ET.fromstring(_BEDS_XML).findall(".//item"))
    assert len(join_er(near, beds, want=1)) == 1
```

`if __name__ == "__main__":` 블록에 호출을 추가한다:
```python
    test_parse_beds_reads_er_phone_and_capacity()
    test_join_er_drops_hospitals_without_live_beds()
    test_join_er_marks_negative_capacity_as_full()
    test_join_er_respects_want()
```

- [ ] **Step 2: 실패를 확인한다**

Run: `backend/venv/bin/python backend/test_live_help.py`
Expected: FAIL — `ImportError: cannot import name 'join_er' from 'live_help'`

- [ ] **Step 3: E-Gen 파트를 구현한다**

`backend/live_help.py` 상단 임포트에 추가:
```python
import time
import xml.etree.ElementTree as ET
```

파일 끝에 다음을 추가한다:

```python
# ---------------------------------------------------------------------------
# 응급실 — E-Gen (국립중앙의료원 전국 응급의료기관 정보 조회 서비스)
#
# 9개 오퍼레이션 중 2개만 쓴다:
#   getEgytLcinfoInqire                 좌표·거리를 주는 유일한 엔드포인트
#   getEmrrmRltmUsefulSckbdInfoInqire   dutyTel3(응급실 직통)·hvec(가용병상)의 유일한 출처
# hpid 로 조인하면 응급실을 운영하지 않는 일반 병원은 자동으로 떨어진다.
# ---------------------------------------------------------------------------

_EGEN_BASE = "https://apis.data.go.kr/B552657/ErmctInfoInqireService"
_BEDS_TTL = 60  # 서울 전체가 한 응답이라 60초 캐시하면 일일 1000콜 제한에 여유가 생긴다

_beds_cache: tuple[float, dict[str, dict]] | None = None


def _egen(op: str, **params) -> list:
    key = os.getenv("EGEN_API_KEY", "")
    if not key:
        raise HTTPException(status_code=500, detail="EGEN_API_KEY is not set")
    try:
        r = httpx.get(
            f"{_EGEN_BASE}/{op}",
            params={"serviceKey": key, "pageNo": 1, "numOfRows": 1000, **params},
            timeout=25,
        )
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"E-Gen {op} request failed: {e}")
    try:
        root = ET.fromstring(r.text)
    except ET.ParseError:
        raise HTTPException(status_code=502, detail=f"E-Gen {op} returned non-XML")
    code = root.findtext(".//resultCode")
    if code not in (None, "00"):
        raise HTTPException(
            status_code=502,
            detail=f"E-Gen {op} returned {code}: {root.findtext('.//resultMsg')}",
        )
    return root.findall(".//item")


def parse_beds(items: list) -> dict[str, dict]:
    """실시간 가용병상 item 들을 hpid 로 키잉한다."""
    beds: dict[str, dict] = {}
    for it in items:
        hpid = (it.findtext("hpid") or "").strip()
        if not hpid:
            continue
        raw = (it.findtext("hvec") or "0").strip()
        try:
            hvec = int(raw)
        except ValueError:
            hvec = 0
        beds[hpid] = {
            "er_phone": (it.findtext("dutyTel3") or "").strip(),
            "hvec": hvec,
            "updated_at": (it.findtext("hvidate") or "").strip(),
        }
    return beds


def _seoul_beds() -> dict[str, dict]:
    global _beds_cache
    now = time.time()
    if _beds_cache and now - _beds_cache[0] < _BEDS_TTL:
        return _beds_cache[1]
    beds = parse_beds(_egen("getEmrrmRltmUsefulSckbdInfoInqire", STAGE1="서울특별시"))
    _beds_cache = (now, beds)
    return beds


def join_er(near_items: list, beds: dict[str, dict], want: int) -> list[dict]:
    """위치조회 결과에 실시간 병상을 붙이고 거리순으로 자른다.

    실시간 목록에 없는 기관은 응급실 미운영 일반 병원이므로 여기서 떨어진다 —
    별도 필터링 로직이 필요 없다.
    """
    rows: list[dict] = []
    for it in near_items:
        hpid = (it.findtext("hpid") or "").strip()
        b = beds.get(hpid)
        if not b:
            continue
        rows.append({
            "name": (it.findtext("dutyName") or "").strip(),
            "address": (it.findtext("dutyAddr") or "").strip(),
            "lat": float(it.findtext("latitude") or 0),
            "lng": float(it.findtext("longitude") or 0),
            "distance_km": float(it.findtext("distance") or 0),
            "er_phone": b["er_phone"],
            "beds": b["hvec"],
            # hvec 는 정원 초과를 음수로 쓴다. 0 이하는 전부 '만원'.
            "beds_state": "available" if b["hvec"] > 0 else "full",
            "updated_at": b["updated_at"],
        })
    rows.sort(key=lambda x: x["distance_km"])
    return rows[:want]


class ErRequest(BaseModel):
    lat: float
    lng: float
    want: int = 5


@router.post("/emergency-rooms")
def emergency_rooms(req: ErRequest):
    """현재 위치에서 가까운, 실제로 운영 중인 응급실을 병상 상황과 함께 돌려준다."""
    near = _egen("getEgytLcinfoInqire", WGS84_LON=req.lng, WGS84_LAT=req.lat)
    rows = join_er(near, _seoul_beds(), req.want)
    return {"updated_at": rows[0]["updated_at"] if rows else "", "hospitals": rows}
```

- [ ] **Step 4: 테스트 통과를 확인한다**

Run: `backend/venv/bin/python backend/test_live_help.py`
Expected: PASS — `live_help self-check ok`

- [ ] **Step 5: 실서버 스모크**

```bash
curl -s -X POST http://localhost:8000/emergency-rooms \
  -H 'Content-Type: application/json' \
  -d '{"lat":37.5563,"lng":126.9236,"want":5}' | head -40
```

Expected: `hospitals` 5건, `distance_km` 오름차순, 모든 항목에 `er_phone` 존재, `beds_state` 가 `available`/`full` 중 하나.

두 번 연속 호출해 두 번째가 눈에 띄게 빠른지 확인한다 (병상 캐시 적중).

- [ ] **Step 6: 커밋**

```bash
git add backend/live_help.py backend/test_live_help.py
git commit -m "feat(backend): add /emergency-rooms with E-Gen location+bed join"
```

---

### Task 3: Flutter 인프라 — 의존성 · 에셋 · iOS 권한 · 위험색 토큰

**Files:**
- Modify: `pubspec.yaml`
- Modify: `ios/Runner/Info.plist`
- Modify: `lib/theme/app_theme.dart:15`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `assets/data/embassies.json` 이 `rootBundle` 로 로드 가능해진다
  - `geolocator` 패키지 사용 가능
  - `const kDanger` — 응급 UI용 위험색

`assets/data/embassies.json` (118건) 은 이미 리포에 있다. 새로 만들지 않는다.

Android 위치 권한은 [AndroidManifest.xml:4-5](../../../android/app/src/main/AndroidManifest.xml#L4-L5) 에 이미 선언되어 있다. **손대지 않는다.**

- [ ] **Step 1: `pubspec.yaml` 에 의존성과 에셋을 추가한다**

기존:
```yaml
  flutter_tts: ^4.2.0
  shared_preferences: ^2.3.0
```
변경 후:
```yaml
  flutter_tts: ^4.2.0
  shared_preferences: ^2.3.0
  geolocator: ^13.0.1
```

기존:
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
```
변경 후:
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/data/
```

- [ ] **Step 2: iOS 위치 권한 문구를 추가한다**

`ios/Runner/Info.plist` 의 `<dict>` 바로 다음 줄(`CADisableMinimumFrameDurationOnPhone` 위)에 삽입한다.

기존:
```xml
<dict>
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
```
변경 후:
```xml
<dict>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>SeoulFit uses your location to find nearby emergency rooms, cafes and restaurants while you travel.</string>
	<key>CADisableMinimumFrameDurationOnPhone</key>
	<true/>
```

이 키가 없어서 온보딩의 `Permission.location.request()`
([onboarding_screen.dart:118](../../../lib/screens/onboarding_screen.dart#L118)) 가 iOS에서
동작하지 않던 버그도 함께 고쳐진다.

- [ ] **Step 3: 위험색 토큰을 추가한다**

`lib/theme/app_theme.dart:15` 의 `kSuccess` 아래에 추가한다.

기존:
```dart
const kSuccess = Color(0xFF10B981);
```
변경 후:
```dart
const kSuccess = Color(0xFF10B981);

/// 응급 UI 전용 위험색. 만원인 응급실, 119 배너처럼 "지금 문제가 있다"를
/// 나타내는 곳에만 쓴다. 일반 경고는 kWarning 을 계속 쓴다.
const kDanger = Color(0xFFE53E3E);
const kDangerWash = Color(0xFFFDECEC);
```

- [ ] **Step 4: 의존성을 받고 정적 분석을 돌린다**

```bash
flutter pub get
flutter analyze
```

Expected: `flutter pub get` 성공, `flutter analyze` 에 새 오류 없음.

- [ ] **Step 5: 에셋이 실제로 번들되는지 확인한다**

```bash
grep -n "assets/data" .flutter-plugins-dependencies 2>/dev/null; \
flutter build bundle 2>&1 | tail -3 && \
find build -name embassies.json | head
```

Expected: `embassies.json` 이 `build/` 아래에서 발견된다.

- [ ] **Step 6: 커밋**

```bash
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist lib/theme/app_theme.dart assets/data/embassies.json backend/tools
git commit -m "chore(flutter): add geolocator, bundle embassy data, fix iOS location permission"
```

---

### Task 4: Flutter 모델과 서비스

**Files:**
- Create: `lib/models/live_help.dart`
- Create: `lib/services/live_help_service.dart`

**Interfaces:**
- Consumes: Task 1의 `POST /nearby`, Task 2의 `POST /emergency-rooms`, Task 3의 에셋·geolocator
- Produces:
  - `class Embassy` — `countryEn, countryKo, iso2, missionKo, addressKo, postalCode, phone, phoneDial, email, website`, `bool matches(String query)`
  - `class EmergencyRoom` — `name, address, lat, lng, distanceKm, erPhone, beds, bedsState, updatedAt`, `bool get isFull`
  - `class NearbyPlace` — `name, address, lat, lng, distanceM, rating, reviews, openNow, placeId`
  - `class LiveHelpService`:
    - `static Future<List<Embassy>> loadEmbassies()`
    - `static Future<LatLng?> currentLatLng()`
    - `static Future<List<NearbyPlace>> fetchNearby(LatLng at, String type)`
    - `static Future<List<EmergencyRoom>> fetchEmergencyRooms(LatLng at)`
  - `LatLng` 는 `package:latlong2/latlong.dart` 것을 쓴다 (이미 의존성에 있음). 새 좌표 타입을 만들지 않는다

- [ ] **Step 1: 모델 테스트를 쓴다**

`test/live_help_model_test.dart` 를 새로 만든다.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:seoulfit_flutter/models/live_help.dart';

void main() {
  test('Embassy.matches finds by English, Korean and ISO2', () {
    const e = Embassy(
      countryEn: 'Philippines', countryKo: '필리핀', iso2: 'PH',
      missionKo: '필리핀', addressKo: '서울특별시 용산구 회나무로 80',
      postalCode: '04346', phone: '788-2100/1', phoneDial: '02-7882100',
      email: 'seoulpe@philembassy-seoul.com', website: '',
    );
    expect(e.matches('phil'), isTrue);
    expect(e.matches('필리'), isTrue);
    expect(e.matches('ph'), isTrue);
    expect(e.matches('용산'), isTrue);
    expect(e.matches('japan'), isFalse);
  });

  test('EmergencyRoom.isFull is true when beds_state is full', () {
    final full = EmergencyRoom.fromJson(const {
      'name': '서울아산', 'address': '서울 송파구', 'lat': 37.527, 'lng': 127.108,
      'distance_km': 9.2, 'er_phone': '02-3010-3333',
      'beds': -6, 'beds_state': 'full', 'updated_at': '20260821182414',
    });
    expect(full.isFull, isTrue);
    expect(full.beds, -6);

    final open = EmergencyRoom.fromJson(const {
      'name': '세브란스', 'address': '서울 서대문구', 'lat': 37.5621, 'lng': 126.9408,
      'distance_km': 1.65, 'er_phone': '02-2227-7777',
      'beds': 4, 'beds_state': 'available', 'updated_at': '20260821182414',
    });
    expect(open.isFull, isFalse);
  });

  test('NearbyPlace tolerates missing rating and open_now', () {
    final p = NearbyPlace.fromJson(const {
      'name': 'Brand New Cafe', 'address': 'Seongdong-gu',
      'lat': 37.5537, 'lng': 127.0214, 'distance_m': 155,
      'reviews': 0, 'place_id': 'x',
    });
    expect(p.rating, isNull);
    expect(p.openNow, isNull);
    expect(p.distanceM, 155);
  });
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `flutter test test/live_help_model_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:seoulfit_flutter/models/live_help.dart'`

- [ ] **Step 3: 모델을 구현한다**

`lib/models/live_help.dart` 를 새로 만든다.

```dart
/// 여행 중 도우미 세 기능의 데이터 모델.
///
/// [Embassy] 는 앱에 번들된 assets/data/embassies.json 에서,
/// 나머지 둘은 백엔드 /nearby · /emergency-rooms 응답에서 온다.
library;

String _str(Object? v) => v is String ? v : '';
double _dbl(Object? v) => v is num ? v.toDouble() : 0;
int _int(Object? v) => v is num ? v.toInt() : 0;

/// 주한 공관 한 곳. 서울 소재 118건이 앱에 번들되어 있어 오프라인에서도 읽힌다.
class Embassy {
  final String countryEn;
  final String countryKo;
  final String iso2;
  final String missionKo;
  final String addressKo;
  final String postalCode;

  /// 외교부 원문 그대로. `788-2100/1` 처럼 복수 번호일 수 있어 표시 전용이다.
  final String phone;

  /// `tel:` 링크용으로 지역번호를 채워 정규화한 단일 번호. 비어 있을 수 있다.
  final String phoneDial;

  final String email;

  /// 118건 중 15건만 값이 있다. 비어 있으면 링크 버튼을 숨긴다.
  final String website;

  const Embassy({
    required this.countryEn,
    required this.countryKo,
    required this.iso2,
    required this.missionKo,
    required this.addressKo,
    required this.postalCode,
    required this.phone,
    required this.phoneDial,
    required this.email,
    required this.website,
  });

  factory Embassy.fromJson(Map<String, dynamic> j) => Embassy(
        countryEn: _str(j['country_en']),
        countryKo: _str(j['country_ko']),
        iso2: _str(j['iso2']),
        missionKo: _str(j['mission_ko']),
        addressKo: _str(j['address_ko']),
        postalCode: _str(j['postal_code']),
        phone: _str(j['phone']),
        phoneDial: _str(j['phone_dial']),
        email: _str(j['email']),
        website: _str(j['website']),
      );

  /// 영문명·한글명·ISO2·주소 어느 쪽으로 쳐도 찾히게 한다. 여행자는 자기 나라를
  /// 영어로 치지만 한국인 동행이 한글로 칠 수도 있다.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return countryEn.toLowerCase().contains(q) ||
        countryKo.contains(q) ||
        iso2.toLowerCase() == q ||
        missionKo.contains(q) ||
        addressKo.contains(q);
  }
}

/// 운영 중인 응급실 한 곳. 위치조회와 실시간 병상을 hpid 로 조인한 결과다.
class EmergencyRoom {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double distanceKm;

  /// 응급실 직통번호. 병원 대표번호가 아니라 새벽에도 받는 번호다.
  final String erPhone;

  /// 가용 병상. 정원 초과를 음수로 표현하므로 [isFull] 이 아닐 때만 렌더링한다.
  final int beds;
  final String bedsState;
  final String updatedAt;

  const EmergencyRoom({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.erPhone,
    required this.beds,
    required this.bedsState,
    required this.updatedAt,
  });

  factory EmergencyRoom.fromJson(Map<String, dynamic> j) => EmergencyRoom(
        name: _str(j['name']),
        address: _str(j['address']),
        lat: _dbl(j['lat']),
        lng: _dbl(j['lng']),
        distanceKm: _dbl(j['distance_km']),
        erPhone: _str(j['er_phone']),
        beds: _int(j['beds']),
        bedsState: _str(j['beds_state']),
        updatedAt: _str(j['updated_at']),
      );

  bool get isFull => bedsState == 'full';
}

/// 주변 추천 장소 한 곳.
class NearbyPlace {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final int distanceM;

  /// 리뷰가 없는 업소는 구글이 평점을 아예 주지 않는다. null 이면 뱃지를 숨긴다.
  final double? rating;
  final int reviews;

  /// 결측 가능. null 이면 영업 상태 뱃지를 숨긴다.
  final bool? openNow;

  final String placeId;

  const NearbyPlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceM,
    required this.rating,
    required this.reviews,
    required this.openNow,
    required this.placeId,
  });

  factory NearbyPlace.fromJson(Map<String, dynamic> j) => NearbyPlace(
        name: _str(j['name']),
        address: _str(j['address']),
        lat: _dbl(j['lat']),
        lng: _dbl(j['lng']),
        distanceM: _int(j['distance_m']),
        rating: j['rating'] is num ? (j['rating'] as num).toDouble() : null,
        reviews: _int(j['reviews']),
        openNow: j['open_now'] is bool ? j['open_now'] as bool : null,
        placeId: _str(j['place_id']),
      );
}
```

- [ ] **Step 4: 모델 테스트 통과를 확인한다**

Run: `flutter test test/live_help_model_test.dart`
Expected: PASS — 3 tests passed.

- [ ] **Step 5: 서비스를 구현한다**

`lib/services/live_help_service.dart` 를 새로 만든다.

```dart
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/api_base.dart';
import '../models/live_help.dart';

/// 서울시청. GPS 를 못 얻고 지역 선택도 하지 않았을 때의 마지막 기준점.
const kSeoulCenter = LatLng(37.5665, 126.9780);

/// 위치 거부/실패 시 고를 수 있는 지역들. 백엔드 geo.py 의 SEOUL_AREA_CENTERS
/// 중 여행자가 실제로 머무는 곳만 추렸다.
const kSeoulAreas = <String, LatLng>{
  'Hongdae': LatLng(37.5563, 126.9227),
  'Myeongdong': LatLng(37.5636, 126.9857),
  'Gangnam': LatLng(37.4979, 127.0276),
  'Itaewon': LatLng(37.5347, 126.9946),
  'Jongno': LatLng(37.5729, 126.9794),
  'Seongsu': LatLng(37.5447, 127.0558),
  'Yeouido': LatLng(37.5217, 126.9244),
  'Jamsil': LatLng(37.5133, 127.1028),
};

/// 여행 중 도우미의 데이터 접근. 대사관은 번들 에셋, 나머지 둘은 백엔드다.
class LiveHelpService {
  static List<Embassy>? _embassies;

  static String get _base => apiBase;

  /// 번들된 주한공관 118건. 첫 호출에만 파싱하고 이후 메모리 캐시를 쓴다.
  /// 네트워크를 타지 않으므로 데이터로밍이 끊겨도 동작한다.
  static Future<List<Embassy>> loadEmbassies() async {
    final cached = _embassies;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/data/embassies.json');
    final list = jsonDecode(raw) as List;
    final parsed = [
      for (final e in list)
        if (e is Map) Embassy.fromJson(Map<String, dynamic>.from(e)),
    ];
    _embassies = parsed;
    return parsed;
  }

  /// 현재 좌표. 권한 거부·서비스 비활성·타임아웃이면 null 을 돌려주고,
  /// 호출부가 지역 수동 선택으로 넘어간다. 예외를 던지지 않는다 —
  /// 응급 화면에서 막다른 길을 만들지 않기 위해서다.
  static Future<LatLng?> currentLatLng() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$_base/$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception('Backend error ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// 도보권 카페/음식점. [type] 은 Google Places 타입 (`cafe`, `restaurant`).
  static Future<List<NearbyPlace>> fetchNearby(LatLng at, String type) async {
    final json = await _post('nearby', {
      'lat': at.latitude,
      'lng': at.longitude,
      'type': type,
      'want': 5,
    });
    final list = json['places'] as List? ?? const [];
    return [
      for (final p in list)
        if (p is Map) NearbyPlace.fromJson(Map<String, dynamic>.from(p)),
    ];
  }

  /// 가까운 운영 중 응급실. 거리순으로 이미 정렬되어 온다.
  static Future<List<EmergencyRoom>> fetchEmergencyRooms(LatLng at) async {
    final json = await _post('emergency-rooms', {
      'lat': at.latitude,
      'lng': at.longitude,
      'want': 5,
    });
    final list = json['hospitals'] as List? ?? const [];
    return [
      for (final h in list)
        if (h is Map) EmergencyRoom.fromJson(Map<String, dynamic>.from(h)),
    ];
  }
}
```

- [ ] **Step 6: 정적 분석과 전체 테스트**

```bash
flutter analyze
flutter test
```

Expected: 새 오류 없음, 모든 테스트 통과.

- [ ] **Step 7: 커밋**

```bash
git add lib/models/live_help.dart lib/services/live_help_service.dart test/live_help_model_test.dart
git commit -m "feat(flutter): add live-help models and service"
```

---

### Task 5: 여행 중 도우미 화면 — 허브와 여권분실

**Files:**
- Create: `lib/screens/live_help_screen.dart`

**Interfaces:**
- Consumes: Task 4의 `LiveHelpService`, `Embassy`
- Produces: `class LiveHelpScreen extends StatefulWidget` — `const LiveHelpScreen({super.key})`

이 태스크에서는 3버튼 허브와 **여권분실 뷰만** 만든다. 응급실·주변추천 뷰는 Task 6이다.

- [ ] **Step 1: 화면 뼈대와 여권분실 뷰를 구현한다**

`lib/screens/live_help_screen.dart` 를 새로 만든다.

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/live_help.dart';
import '../services/live_help_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/app_status_bar.dart';
import '../widgets/mascot_widget.dart';

enum _View { hub, passport, emergency, nearby }

/// 여행 중 도우미. 여행 전 챗봇(/chat)과 달리 LLM 을 호출하지 않고
/// 퀵액션 3버튼으로만 동작한다 — 응급 상황에서 지연도 환각도 만들지 않기 위해서다.
class LiveHelpScreen extends StatefulWidget {
  const LiveHelpScreen({super.key});

  @override
  State<LiveHelpScreen> createState() => _LiveHelpScreenState();
}

class _LiveHelpScreenState extends State<LiveHelpScreen> {
  _View _view = _View.hub;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            const AppStatusBar(),
            _Header(
              showBack: _view != _View.hub,
              onBack: () => setState(() => _view = _View.hub),
            ),
            const Divider(height: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  Widget _body() {
    switch (_view) {
      case _View.hub:
        return _Hub(onPick: (v) => setState(() => _view = v));
      case _View.passport:
        return const _PassportView();
      case _View.emergency:
      case _View.nearby:
        // Task 6 에서 채운다.
        return const SizedBox.shrink();
    }
  }
}

class _Header extends StatelessWidget {
  final bool showBack;
  final VoidCallback onBack;
  const _Header({required this.showBack, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kCard,
      padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg, vertical: Insets.md),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              color: kInk,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            )
          else
            const MascotWidget(size: 38, variant: MascotVariant.chip),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SeoulFit Buddy 🐣',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
                Text('On-trip help',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: kSubtext)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hub extends StatelessWidget {
  final ValueChanged<_View> onPick;
  const _Hub({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        Text('What can I help you with?',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
        const SizedBox(height: Insets.xs),
        Text("Tell me what happened and I'll pull it up right away.",
            style:
                GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext)),
        const SizedBox(height: Insets.xl),
        _ActionCard(
          icon: Icons.badge_outlined,
          title: 'Lost passport',
          subtitle: 'Find your embassy in Seoul',
          onTap: () => onPick(_View.passport),
        ),
        const SizedBox(height: Insets.md),
        _ActionCard(
          icon: Icons.local_hospital_outlined,
          title: 'Emergency room',
          subtitle: 'Nearest ER with live bed availability',
          danger: true,
          onTap: () => onPick(_View.emergency),
        ),
        const SizedBox(height: Insets.md),
        _ActionCard(
          icon: Icons.place_outlined,
          title: 'Near me',
          subtitle: 'Cafes and restaurants within walking distance',
          onTap: () => onPick(_View.nearby),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool danger;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = danger ? kDanger : kMint;
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(Insets.lg),
          decoration: BoxDecoration(
            border: Border.all(color: kCardBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: danger ? kDangerWash : kMintLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kInk)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: kSubtext)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kSubtext),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _launch(Uri uri) async {
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}

/// 여권분실. 데이터가 앱에 번들되어 있어 네트워크 실패 경로가 없다.
class _PassportView extends StatefulWidget {
  const _PassportView();

  @override
  State<_PassportView> createState() => _PassportViewState();
}

class _PassportViewState extends State<_PassportView> {
  final _controller = TextEditingController();
  List<Embassy> _all = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    LiveHelpService.loadEmbassies().then((v) {
      if (mounted) setState(() => _all = v);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hits = _all.where((e) => e.matches(_query)).toList();
    return Column(
      children: [
        const _EmergencyNumbersBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Insets.lg, Insets.md, Insets.lg, Insets.sm),
          child: TextField(
            controller: _controller,
            onChanged: (v) => setState(() => _query = v),
            style: GoogleFonts.plusJakartaSans(fontSize: 14, color: kInk),
            decoration: InputDecoration(
              hintText: 'Search your country — Philippines, 필리핀, PH',
              hintStyle:
                  GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext),
              prefixIcon: const Icon(Icons.search_rounded, color: kSubtext),
              filled: true,
              fillColor: kCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kCardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kCardBorder),
              ),
            ),
          ),
        ),
        Expanded(
          child: hits.isEmpty
              ? Center(
                  child: Text('No embassy found for "$_query"',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: kSubtext)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      Insets.lg, 0, Insets.lg, Insets.xl),
                  itemCount: hits.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Insets.md),
                  itemBuilder: (_, i) => _EmbassyCard(hits[i]),
                ),
        ),
      ],
    );
  }
}

/// 여권 분실 시 실제로 통화가 되는 두 번호. 대사관 대표전화는 새벽에 받지
/// 않지만 이 둘은 24시간이다. 데이터에 긴급전화 필드가 아예 없어서 이 배너가
/// 그 구멍을 메운다.
class _EmergencyNumbersBanner extends StatelessWidget {
  const _EmergencyNumbersBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, 0),
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: kYellowLight,
        border: Border.all(color: kWarningBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report to the police first, then your embassy.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: kInk)),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Expanded(
                child: _PhonePill(
                  label: '1330 · 24h interpreter',
                  number: '1330',
                ),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: _PhonePill(label: '112 · Police', number: '112'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhonePill extends StatelessWidget {
  final String label;
  final String number;
  const _PhonePill({required this.label, required this.number});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _launch(Uri(scheme: 'tel', path: number)),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.call_rounded, size: 14, color: kInk),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: kInk)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmbassyCard extends StatelessWidget {
  final Embassy e;
  const _EmbassyCard(this.e);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.countryEn,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
          Text(e.countryKo,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: kSubtext)),
          const SizedBox(height: Insets.md),
          // 한글 주소를 그대로 노출한다 — 택시 기사에게 화면을 보여주는 용도다.
          Text(e.addressKo,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: kInk, height: 1.4)),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              if (e.phoneDial.isNotEmpty)
                _MiniButton(
                  icon: Icons.call_rounded,
                  label: e.phone,
                  onTap: () => _launch(
                      Uri(scheme: 'tel', path: e.phoneDial.replaceAll('-', ''))),
                ),
              _MiniButton(
                icon: Icons.map_outlined,
                label: 'Map',
                onTap: () => _launch(Uri.parse(
                    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(e.addressKo)}')),
              ),
              if (e.website.isNotEmpty)
                _MiniButton(
                  icon: Icons.language_rounded,
                  label: 'Website',
                  onTap: () => _launch(Uri.parse(e.website)),
                ),
              if (e.email.isNotEmpty)
                _MiniButton(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  onTap: () => _launch(Uri(scheme: 'mailto', path: e.email)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Insets.md, vertical: Insets.sm),
        decoration: BoxDecoration(
          color: kMintLight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: kMint),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: kInk)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 정적 분석**

Run: `flutter analyze lib/screens/live_help_screen.dart`
Expected: 오류 없음. `MascotVariant.chip` 과 `Insets` 상수명이 실제와 맞는지 확인한다 — 다르면 `lib/widgets/mascot_widget.dart` 와 `lib/theme/app_theme.dart` 의 실제 이름으로 맞춘다.

- [ ] **Step 3: 커밋**

```bash
git add lib/screens/live_help_screen.dart
git commit -m "feat(flutter): add on-trip help hub and lost-passport view"
```

---

### Task 6: 응급실 뷰와 주변 추천 뷰

**Files:**
- Modify: `lib/screens/live_help_screen.dart`

**Interfaces:**
- Consumes: Task 4의 `LiveHelpService.currentLatLng/fetchEmergencyRooms/fetchNearby`, `kSeoulAreas`, `EmergencyRoom`, `NearbyPlace`
- Produces: `_View.emergency` 와 `_View.nearby` 가 실제 위젯을 반환한다

- [ ] **Step 1: 위치 게이트 위젯을 추가한다**

`live_help_screen.dart` 상단 임포트에 추가한다:
```dart
import 'package:latlong2/latlong.dart';
```

파일 끝에 추가한다:

```dart
/// GPS 를 시도하고, 실패하면 지역 수동 선택을 띄운다.
/// 응급 화면이 막다른 길이 되지 않도록 항상 좌표를 확보하는 것이 목적이다.
class _LocationGate extends StatefulWidget {
  final Widget Function(LatLng at) builder;
  const _LocationGate({required this.builder});

  @override
  State<_LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<_LocationGate> {
  LatLng? _at;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    LiveHelpService.currentLatLng().then((v) {
      if (!mounted) return;
      setState(() {
        _at = v;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kMint));
    }
    final at = _at;
    if (at != null) return widget.builder(at);
    return _AreaPicker(onPick: (v) => setState(() => _at = v));
  }
}

class _AreaPicker extends StatelessWidget {
  final ValueChanged<LatLng> onPick;
  const _AreaPicker({required this.onPick});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Insets.lg),
      children: [
        Text("Couldn't get your location",
            style: GoogleFonts.plusJakartaSans(
                fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
        const SizedBox(height: Insets.xs),
        Text('Pick the area you are in and I will search from there.',
            style:
                GoogleFonts.plusJakartaSans(fontSize: 13, color: kSubtext)),
        const SizedBox(height: Insets.lg),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final entry in kSeoulAreas.entries)
              InkWell(
                onTap: () => onPick(entry.value),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Insets.lg, vertical: Insets.md),
                  decoration: BoxDecoration(
                    color: kCard,
                    border: Border.all(color: kCardBorder),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(entry.key,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kInk)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: 응급실 뷰를 추가한다**

`live_help_screen.dart` 파일 끝에 추가한다:

```dart
/// E-Gen 이 통째로 죽었을 때 보여줄 최소 목록. 서울 권역 대형병원 5곳을
/// 지리적으로 흩어 골랐다 (성북·종로·서대문·서초·송파). 전화번호는 전부
/// 응급실 직통번호(dutyTel3)이고 좌표·주소는 getEgytBassInfoInqire 실응답에서
/// 가져왔다. 응급 화면은 어떤 경우에도 막다른 길이 되면 안 된다.
const _kErFallback = <EmergencyRoom>[
  EmergencyRoom(
      name: '연세대학교의과대학세브란스병원',
      address: '서울특별시 서대문구 연세로 50-1 (신촌동)',
      lat: 37.562117, lng: 126.940828, distanceKm: 0,
      erPhone: '02-2227-7777', beds: 0, bedsState: 'unknown', updatedAt: ''),
  EmergencyRoom(
      name: '서울대학교병원',
      address: '서울특별시 종로구 대학로 101 (연건동)',
      lat: 37.579666, lng: 126.998963, distanceKm: 0,
      erPhone: '02-2072-2475', beds: 0, bedsState: 'unknown', updatedAt: ''),
  EmergencyRoom(
      name: '고려대학교의과대학부속병원 (안암병원)',
      address: '서울특별시 성북구 고려대로 73 (안암동5가)',
      lat: 37.587156, lng: 127.026471, distanceKm: 0,
      erPhone: '02-920-5374', beds: 0, bedsState: 'unknown', updatedAt: ''),
  EmergencyRoom(
      name: '가톨릭대학교 서울성모병원',
      address: '서울특별시 서초구 반포대로 222 (반포동)',
      lat: 37.501801, lng: 127.004727, distanceKm: 0,
      erPhone: '02-2258-2370', beds: 0, bedsState: 'unknown', updatedAt: ''),
  EmergencyRoom(
      name: '서울아산병원',
      address: '서울특별시 송파구 올림픽로43길 88 (풍납동)',
      lat: 37.526564, lng: 127.108238, distanceKm: 0,
      erPhone: '02-3010-3333', beds: 0, bedsState: 'unknown', updatedAt: ''),
];

/// 응급실. API 가 죽어도 119 안내와 대형병원 5곳은 항상 보인다.
class _EmergencyView extends StatefulWidget {
  final LatLng at;
  const _EmergencyView(this.at);

  @override
  State<_EmergencyView> createState() => _EmergencyViewState();
}

class _EmergencyViewState extends State<_EmergencyView> {
  List<EmergencyRoom>? _rooms;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    LiveHelpService.fetchEmergencyRooms(widget.at).then((v) {
      if (mounted) setState(() => _rooms = v);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms;
    return Column(
      children: [
        const _Call119Banner(),
        Expanded(
          child: _failed
              ? ListView(
                  padding: const EdgeInsets.all(Insets.lg),
                  children: [
                    Text(
                      "Live hospital data is unavailable. These major ERs are open 24 hours — call ahead before you go.",
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: kSubtext, height: 1.5),
                    ),
                    const SizedBox(height: Insets.lg),
                    for (final r in _kErFallback) ...[
                      _RoomCard(r),
                      const SizedBox(height: Insets.md),
                    ],
                  ],
                )
              : rooms == null
                  ? const Center(
                      child: CircularProgressIndicator(color: kMint))
                  : ListView.separated(
                      padding: const EdgeInsets.all(Insets.lg),
                      itemCount: rooms.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: Insets.md),
                      itemBuilder: (_, i) => _RoomCard(rooms[i]),
                    ),
        ),
      ],
    );
  }
}

class _Call119Banner extends StatelessWidget {
  const _Call119Banner();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _launch(Uri(scheme: 'tel', path: '119')),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, 0),
        padding: const EdgeInsets.all(Insets.lg),
        decoration: BoxDecoration(
          color: kDangerWash,
          border: Border.all(color: kDanger),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.emergency_rounded, color: kDanger),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Call 119',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kDanger)),
                  Text('Ambulance and interpreter, 24 hours',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: kInk)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final EmergencyRoom r;
  const _RoomCard(this.r);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
              ),
              const SizedBox(width: Insets.sm),
              // hvec 는 정원 초과를 음수로 쓴다. 만원일 때 숫자를 보여주지 않는다.
              // 폴백 목록은 bedsState 가 unknown 이라 뱃지를 아예 숨긴다.
              if (r.bedsState != 'unknown')
                _Pill(
                  text: r.isFull ? 'Full' : '${r.beds} beds',
                  fg: r.isFull ? kDanger : kSuccess,
                  bg: r.isFull ? kDangerWash : kMintLight,
                ),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Text(
              r.distanceKm > 0
                  ? '${r.distanceKm.toStringAsFixed(1)} km · ${r.address}'
                  : r.address,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: kSubtext, height: 1.4)),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              if (r.erPhone.isNotEmpty)
                _MiniButton(
                  icon: Icons.call_rounded,
                  label: r.erPhone,
                  onTap: () => _launch(Uri(
                      scheme: 'tel', path: r.erPhone.replaceAll('-', ''))),
                ),
              _MiniButton(
                icon: Icons.directions_rounded,
                label: 'Directions',
                onTap: () => _launch(Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=${r.lat},${r.lng}')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const _Pill({required this.text, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.xs),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}
```

- [ ] **Step 3: 주변 추천 뷰를 추가한다**

`live_help_screen.dart` 파일 끝에 추가한다:

```dart
/// 주변 추천. 카페/음식점 토글 + 거리순 5개.
class _NearbyView extends StatefulWidget {
  final LatLng at;
  const _NearbyView(this.at);

  @override
  State<_NearbyView> createState() => _NearbyViewState();
}

class _NearbyViewState extends State<_NearbyView> {
  String _type = 'cafe';
  List<NearbyPlace>? _places;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _places = null;
      _failed = false;
    });
    LiveHelpService.fetchNearby(widget.at, _type).then((v) {
      if (mounted) setState(() => _places = v);
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final places = _places;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: Row(
            children: [
              for (final t in const ['cafe', 'restaurant'])
                Padding(
                  padding: const EdgeInsets.only(right: Insets.sm),
                  child: InkWell(
                    onTap: () {
                      if (_type == t) return;
                      _type = t;
                      _load();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Insets.lg, vertical: Insets.sm),
                      decoration: BoxDecoration(
                        color: _type == t ? kMintLight : kCard,
                        border: Border.all(
                            color: _type == t ? kMint : kCardBorder),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(t == 'cafe' ? 'Cafes' : 'Restaurants',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _type == t ? kMint : kSubtext)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _failed
              ? Center(
                  child: Text("Couldn't load nearby places right now.",
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: kSubtext)),
                )
              : places == null
                  ? const Center(
                      child: CircularProgressIndicator(color: kMint))
                  : places.isEmpty
                      ? Center(
                          child: Text('Nothing within walking distance here.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13, color: kSubtext)),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              Insets.lg, 0, Insets.lg, Insets.xl),
                          itemCount: places.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: Insets.md),
                          itemBuilder: (_, i) => _PlaceCard(places[i]),
                        ),
        ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final NearbyPlace p;
  const _PlaceCard(this.p);

  @override
  Widget build(BuildContext context) {
    final openNow = p.openNow;
    final rating = p.rating;
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: kInk)),
              ),
              // 리뷰가 없는 업소는 구글이 평점을 주지 않는다 — 그럴 땐 뱃지를 숨긴다.
              if (rating != null)
                _Pill(
                    text: '$rating★ (${p.reviews})',
                    fg: kInk,
                    bg: kYellowLight),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Text('${p.distanceM} m · ${p.address}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: kSubtext, height: 1.4)),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: [
              if (openNow != null)
                _Pill(
                  text: openNow ? 'Open now' : 'Closed',
                  fg: openNow ? kSuccess : kSubtext,
                  bg: openNow ? kMintLight : kCanvas,
                ),
              _MiniButton(
                icon: Icons.directions_walk_rounded,
                label: 'Directions',
                onTap: () => _launch(Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: `_body()` 를 연결한다**

기존:
```dart
      case _View.emergency:
      case _View.nearby:
        // Task 6 에서 채운다.
        return const SizedBox.shrink();
```
변경 후:
```dart
      case _View.emergency:
        return _LocationGate(builder: (at) => _EmergencyView(at));
      case _View.nearby:
        return _LocationGate(builder: (at) => _NearbyView(at));
```

- [ ] **Step 5: 정적 분석과 테스트**

```bash
flutter analyze
flutter test
```
Expected: 오류 없음, 테스트 통과.

- [ ] **Step 6: 커밋**

```bash
git add lib/screens/live_help_screen.dart
git commit -m "feat(flutter): add emergency-room and nearby views with location fallback"
```

---

### Task 7: 모드 토글과 라우트 배선

**Files:**
- Create: `lib/widgets/chat_mode_toggle.dart`
- Modify: `lib/main.dart`
- Modify: `lib/screens/conversational_intake_screen.dart`
- Modify: `lib/screens/live_help_screen.dart`

**Interfaces:**
- Consumes: Task 5의 `LiveHelpScreen`
- Produces: `class ChatModeToggle extends StatelessWidget` — `const ChatModeToggle({super.key, required this.liveMode})`

- [ ] **Step 1: 토글 위젯을 만든다**

`lib/widgets/chat_mode_toggle.dart` 를 새로 만든다.

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Chat 탭의 두 모드를 오가는 세그먼트 토글.
///
/// 하단 탭 5개가 이미 만석이라 6번째를 넣는 대신 Chat 탭을 둘로 나눴다.
/// 두 화면 모두 AppBottomNav(currentIndex: 0) 을 쓰므로 pushReplacementNamed
/// 로 바꿔치기해도 탭 상태가 흔들리지 않는다.
///
/// 저장된 여행의 date 가 문자열이라 "여행 중"을 자동 판정할 수 없다.
/// 기본값은 Plan 이고 전환은 수동이다.
class ChatModeToggle extends StatelessWidget {
  /// 현재 화면이 On-trip 인지. true 면 오른쪽 세그먼트가 선택 상태다.
  final bool liveMode;

  const ChatModeToggle({super.key, required this.liveMode});

  void _go(BuildContext context, String route) {
    if (ModalRoute.of(context)?.settings.name == route) return;
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kCanvas,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kCardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(context, 'Plan', !liveMode, '/chat'),
          _seg(context, 'On-trip', liveMode, '/live-help'),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, bool on, String route) {
    return InkWell(
      onTap: () => _go(context, route),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Insets.md, vertical: 5),
        decoration: BoxDecoration(
          color: on ? kMint : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : kSubtext)),
      ),
    );
  }
}
```

- [ ] **Step 2: 라우트를 등록한다**

`lib/main.dart` 임포트 블록의 `import 'screens/conversational_intake_screen.dart';` 아래에 추가:
```dart
import 'screens/live_help_screen.dart';
```

`routes:` 맵의 `'/chat'` 아래에 추가:
```dart
          '/chat': (ctx) => const ConversationalIntakeScreen(),
          '/live-help': (ctx) => const LiveHelpScreen(),
```

- [ ] **Step 3: 여행 전 챗봇 헤더에 토글을 넣는다**

`lib/screens/conversational_intake_screen.dart` 임포트에 추가:
```dart
import '../widgets/chat_mode_toggle.dart';
```

헤더의 `'AI Chat'` 칩(파일 내 `Container` + `Text('AI Chat', ...)` 블록)을 통째로 토글로 바꾼다.

기존:
```dart
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: kMintLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'AI Chat',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: kMint),
                    ),
                  ),
```
변경 후:
```dart
                  const ChatModeToggle(liveMode: false),
```

- [ ] **Step 4: 여행 중 화면 헤더에도 토글을 넣는다**

`lib/screens/live_help_screen.dart` 임포트에 추가:
```dart
import '../widgets/chat_mode_toggle.dart';
```

`_Header` 의 `Expanded(...)` 바로 뒤(`Row` 의 마지막 자식으로) 추가:
```dart
          const ChatModeToggle(liveMode: true),
```

- [ ] **Step 5: 정적 분석과 테스트**

```bash
flutter analyze
flutter test
```
Expected: 오류 없음. `GoogleFonts` 임포트가 더 이상 쓰이지 않아 `unused_import` 가 뜨면 그때만 제거한다.

- [ ] **Step 6: 실기기/시뮬레이터 스모크**

백엔드를 띄운 상태에서:
```bash
flutter run
```

확인 항목:
1. Chat 탭 헤더의 `Plan | On-trip` 토글이 양방향으로 동작한다
2. On-trip 에서 3버튼이 보이고, Lost passport → 국가 검색이 즉시 동작한다 (**기내모드로도 동작해야 한다**)
3. Emergency room → 위치 권한 다이얼로그 → 목록에 응급실 직통번호와 병상/Full 뱃지가 보인다
4. 위치 권한을 거부하면 지역 선택 칩이 뜨고, 고르면 목록이 나온다
5. Near me → Cafes/Restaurants 토글이 동작하고 거리순으로 정렬된다

- [ ] **Step 7: 커밋**

```bash
git add lib/widgets/chat_mode_toggle.dart lib/main.dart \
        lib/screens/conversational_intake_screen.dart lib/screens/live_help_screen.dart
git commit -m "feat(flutter): wire Plan/On-trip mode toggle into chat tab"
```

---

## 자기 검토 결과

**스펙 커버리지**

| 스펙 절 | 태스크 |
|---|---|
| 1. 화면과 네비게이션 | Task 5, 7 |
| 2. 여권분실 (데이터·배너·UI) | Task 3(에셋), 4(모델·로더), 5(뷰·1330/112 배너) |
| 3. 응급실 (조인·캐시·음수·폴백) | Task 2(백엔드), 6(뷰·119 배너) |
| 4. 주변 추천 (반경확장·필터·거리순) | Task 1(백엔드), 6(뷰) |
| 5. 위치 획득 (권한·폴백) | Task 3(iOS 권한), 4(`currentLatLng`), 6(`_LocationGate`) |
| 6. 백엔드 계약 | Task 1, 2 |
| 7. 프런트 구조 | Task 4~7 |
| 8. 에러 처리 | Task 6(실패 문구·폴백), 4(`currentLatLng` 무예외) |
| 9. 테스트 | Task 1, 2(백엔드 셀프체크), 4(모델 테스트) |

**의도적으로 넣지 않은 것**

- 스펙 3절의 "조건부 확장 (Phase 2)" — `getEgytBassInfoInqire` 상세 화면. 스펙에서 Phase 2로 명시했으므로 이번 계획 범위 밖이다
- 없음. 첫 검토에서 "E-Gen 전면 장애 시 권역응급의료센터 5곳 하드코딩"(스펙 8절)이 빠져 있었고, Task 6 Step 2 의 `_kErFallback` 으로 채웠다. 다섯 곳의 응급실 직통번호·주소·좌표는 `getEgytBassInfoInqire` 실응답에서 가져온 값이지 추정치가 아니다

**타입 정합성 확인**
- 백엔드 `beds_state` ↔ Dart `EmergencyRoom.bedsState` / `isFull` — 일치
- 백엔드 `distance_m`(int) ↔ `NearbyPlace.distanceM`(int) — 일치
- 백엔드 `distance_km`(float) ↔ `EmergencyRoom.distanceKm`(double) — 일치
- `filter_places` 시그니처가 Task 1 테스트와 구현에서 동일
- `join_er(near_items, beds, want)` 가 Task 2 테스트와 구현에서 동일
- `LatLng` 는 `latlong2` 것을 일관되게 쓴다 (신규 타입 없음)
- `bedsState` 는 백엔드가 `available`/`full` 만 보내고, 폴백 전용으로 `unknown` 이 추가된다. `_RoomCard` 가 세 값을 모두 처리한다
