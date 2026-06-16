"""RAG layer over course_data.json.

Builds (or loads) a FAISS index of Seoul travel courses, embedded with
Google's text-embedding-004. Each course becomes one Document; the full
course dict is stashed in metadata so retrieval hands the planner
ready-to-use POI sequences.

개선사항:
1. 여러 지역 입력 시 (예: "Hongdae and Seongsu") 지역별 분리 검색
2. 목적별 특화 쿼리 생성
3. 중복 제거 후 합치기
"""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path
from typing import Any

from langchain_community.vectorstores import FAISS
from langchain_core.documents import Document
from langchain_google_genai import GoogleGenerativeAIEmbeddings

from geo import (
    AREA_ALIASES,
    area_label,
    extract_requested_areas,
)


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

_BASE_DIR = Path(__file__).resolve().parent
COURSE_DATA_PATH = _BASE_DIR / "course_data.json"
VECTORSTORE_DIR = _BASE_DIR / "vectorstore"

EMBEDDING_MODEL = "models/gemini-embedding-001"

EMBED_CHUNK_SIZE = 50
EMBED_CHUNK_SLEEP_SECONDS = 60
EMBED_MAX_RETRIES = 5


# ---------------------------------------------------------------------------
# Document construction
# ---------------------------------------------------------------------------

def _course_to_text(course: dict[str, Any]) -> str:
    """Flatten a course into a single searchable string."""
    title = course.get("course_title", "")
    themes = ", ".join(course.get("theme_category", []) or [])
    source = course.get("source", "")

    poi_lines = []
    for poi in course.get("sequence", []) or []:
        name = poi.get("poi_name", "")
        ptype = poi.get("poi_type", "")
        addr = poi.get("address_en") or poi.get("address_ko", "")
        poi_lines.append(f"- ({ptype}) {name} — {addr}")
    pois = "\n".join(poi_lines)

    return (
        f"Title: {title}\n"
        f"Source: {source}\n"
        f"Themes: {themes}\n"
        f"POIs:\n{pois}"
    )


def _course_to_document(course: dict[str, Any]) -> Document:
    sequence = course.get("sequence", []) or []
    try:
        total_min = sum(int(p.get("estimated_stay_time", 0) or 0) for p in sequence)
    except (TypeError, ValueError):
        total_min = 0

    metadata = {
        "course_id": course.get("course_id"),
        "source": course.get("source"),
        "source_url": course.get("source_url"),
        "course_title": course.get("course_title"),
        "themes": course.get("theme_category", []) or [],
        "poi_count": len(sequence),
        "total_estimated_minutes": total_min,
        "course": course,
    }
    return Document(page_content=_course_to_text(course), metadata=metadata)


def _load_courses(path: Path = COURSE_DATA_PATH) -> list[dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Vector store build / load
# ---------------------------------------------------------------------------

_vectorstore: FAISS | None = None
_vectorstore_api_key: str | None = None


def _get_embeddings(api_key: str) -> GoogleGenerativeAIEmbeddings:
    key = (api_key or "").strip()
    if not key:
        raise ValueError(
            "Empty Gemini API key. Enter a valid key in the sidebar or set "
            "GOOGLE_API_KEY before launching streamlit."
        )
    return GoogleGenerativeAIEmbeddings(model=EMBEDDING_MODEL, google_api_key=key)


_RETRY_DELAY_RE = re.compile(r"retry[_ ]delay[^0-9]*(\d+)", re.IGNORECASE)


def _parse_retry_seconds(err: Exception, default: int = EMBED_CHUNK_SLEEP_SECONDS) -> int:
    """Extract the server-suggested retry_delay from a 429 error string."""
    m = _RETRY_DELAY_RE.search(str(err))
    if m:
        try:
            return int(m.group(1)) + 1
        except ValueError:
            pass
    return default


def _embed_with_retry(
    embeddings: GoogleGenerativeAIEmbeddings,
    texts: list[str],
) -> list[list[float]]:
    """embed_documents with exponential-ish backoff on 429s."""
    for attempt in range(EMBED_MAX_RETRIES):
        try:
            return embeddings.embed_documents(texts)
        except Exception as e:
            msg = str(e)
            is_quota = "429" in msg or "quota" in msg.lower() or "rate" in msg.lower()
            if not is_quota or attempt == EMBED_MAX_RETRIES - 1:
                raise
            wait = _parse_retry_seconds(e)
            print(
                f"   ⚠️  rate-limited (attempt {attempt + 1}/{EMBED_MAX_RETRIES}), "
                f"sleeping {wait}s and retrying..."
            )
            time.sleep(wait)
    raise RuntimeError("unreachable")


def _embed_documents_chunked(
    docs: list[Document],
    embeddings: GoogleGenerativeAIEmbeddings,
    chunk_size: int = EMBED_CHUNK_SIZE,
    chunk_sleep: int = EMBED_CHUNK_SLEEP_SECONDS,
) -> list[tuple[str, list[float]]]:
    """Embed docs in rate-limit-friendly chunks. Returns (text, vector) pairs."""
    texts = [d.page_content for d in docs]
    pairs: list[tuple[str, list[float]]] = []
    total = len(texts)
    for start in range(0, total, chunk_size):
        end = min(start + chunk_size, total)
        chunk = texts[start:end]
        print(f"   embedding {start + 1}–{end} of {total}...")
        vectors = _embed_with_retry(embeddings, chunk)
        pairs.extend(zip(chunk, vectors))
        if end < total:
            print(f"   sleeping {chunk_sleep}s to respect rate limit...")
            time.sleep(chunk_sleep)
    return pairs


def build_or_load_vectorstore(
    api_key: str,
    persist_dir: Path = VECTORSTORE_DIR,
    rebuild: bool = False,
) -> FAISS:
    """Return a FAISS index over course_data.json."""
    global _vectorstore, _vectorstore_api_key

    if _vectorstore is not None and _vectorstore_api_key == api_key and not rebuild:
        return _vectorstore

    embeddings = _get_embeddings(api_key)
    index_file = persist_dir / "index.faiss"

    if index_file.exists() and not rebuild:
        store = FAISS.load_local(
            str(persist_dir),
            embeddings,
            allow_dangerous_deserialization=True,
        )
    else:
        courses = _load_courses()
        docs = [_course_to_document(c) for c in courses]
        metadatas = [d.metadata for d in docs]

        text_embeddings = _embed_documents_chunked(docs, embeddings)
        store = FAISS.from_embeddings(
            text_embeddings=text_embeddings,
            embedding=embeddings,
            metadatas=metadatas,
        )
        persist_dir.mkdir(parents=True, exist_ok=True)
        store.save_local(str(persist_dir))

    _vectorstore = store
    _vectorstore_api_key = api_key
    return store


# ---------------------------------------------------------------------------
# Retrieval
# ---------------------------------------------------------------------------

def _extract_areas(location: str) -> list[str]:
    # 괄호 제거
    location = re.sub(r'[()]', '', location)
    # "Seoul" 단독 단어 제거
    location = re.sub(r'\bSeoul\b', '', location, flags=re.IGNORECASE)
    # and, &, comma, slash로 분리
    areas = re.split(r"\s+and\s+|\s*&\s*|\s*,\s*|\s*/\s*", location, flags=re.IGNORECASE)
    # 빈 문자열 제거
    return [a.strip() for a in areas if a.strip()]


def build_query(
    purpose: str | None,
    dietary: str | None,
    location: str | None,
    duration: str | None = None,
) -> str:
    """Compose a natural-language query from the user's confirmed fields."""
    parts = []
    if purpose:
        parts.append(f"Travel purpose: {purpose}.")
    if location:
        parts.append(f"Area or neighborhood of interest: {location}.")
    if dietary and dietary.lower() not in {"none", "no", "n/a", "없음"}:
        parts.append(f"Dietary preference: {dietary}.")
    if duration:
        parts.append(f"Trip length: {duration}.")
    if not parts:
        return "Seoul travel itinerary"
    return " ".join(parts)


def retrieve_courses(
    api_key: str,
    query: str,
    k: int = 5,
    location: str | None = None,
    purpose: str | None = None,
) -> list[dict[str, Any]]:
    """
    Return the top-k course dicts (full payloads) for a query.
    location이 여러 지역이면 각각 검색해서 합침.
    """
    store = build_or_load_vectorstore(api_key)

    # 지역 추출
    areas = _extract_areas(location) if location else []

    if len(areas) >= 2:
        # 여러 지역이면 각각 검색 후 합치기
        seen_ids: set[str] = set()
        all_courses: list[dict[str, Any]] = []
        per_area_k = max(2, k // len(areas))

        for area in areas:
            # 지역별 특화 쿼리 생성
            if purpose:
                area_query = f"{area} {purpose} Seoul travel itinerary"
            else:
                area_query = f"{area} Seoul travel itinerary"

            docs = store.similarity_search(area_query, k=per_area_k)
            for d in docs:
                course = d.metadata.get("course", {})
                cid = course.get("course_id")
                if cid and cid not in seen_ids:
                    seen_ids.add(cid)
                    all_courses.append(course)

        # 부족하면 전체 쿼리로 보완
        if len(all_courses) < k:
            docs = store.similarity_search(query, k=k)
            for d in docs:
                course = d.metadata.get("course", {})
                cid = course.get("course_id")
                if cid and cid not in seen_ids:
                    seen_ids.add(cid)
                    all_courses.append(course)
                    if len(all_courses) >= k:
                        break

        print(f"[RAG] 지역별 검색: {areas} → {len(all_courses)}개 코스 확보")
        return all_courses[:k]

    else:
        # 단일 지역이면 기존 방식
        docs = store.similarity_search(query, k=k)
        courses = [d.metadata.get("course", {}) for d in docs if d.metadata.get("course")]
        print(f"[RAG] 단일 검색 → {len(courses)}개 코스 확보")
        return courses


# ---------------------------------------------------------------------------
# Day-segment planning (dual-index retrieval)
# ---------------------------------------------------------------------------
#
# The dual-index plan splits a multi-area / multi-purpose trip into discrete
# day segments. Each segment is retrieved independently — Index A for whole
# editorial courses, Index B for gap-filling individual POIs — so a request
# like "2 days Hongdae + 1 day historical" no longer blends into a single
# muddled query.


def _parse_num_days(duration: str | None) -> int:
    """Parse the integer number of days from '4 days', '1 week', etc."""
    if not duration:
        return 1
    text = duration.lower().strip()
    week_match = re.search(r"(\d+)\s*week", text)
    if week_match:
        return int(week_match.group(1)) * 7
    day_match = re.search(r"(\d+)\s*day", text)
    if day_match:
        return int(day_match.group(1))
    num_match = re.search(r"\d+", text)
    if num_match:
        return int(num_match.group())
    return 1


def _split_purpose_by_area(
    purpose: str,
    areas: list[str],
) -> dict[str, str]:
    """Best-effort match of purpose clauses to areas.

    Splits on 'and' / ',' / 'then' / ';' and tries to attach each clause to an
    area by checking if the area's aliases appear in the clause. If no clause
    mentions a given area, that area falls back to the full purpose string.
    """
    if not purpose:
        return {a: "" for a in areas}

    clauses = re.split(
        r"\s+and\s+|\s+then\s+|\s*[,;]\s*",
        purpose,
        flags=re.IGNORECASE,
    )
    clauses = [c.strip() for c in clauses if c.strip()]

    hints: dict[str, str] = {}
    for area in areas:
        aliases = AREA_ALIASES.get(area, [])
        matched = next(
            (c for c in clauses
             if any(a.lower() in c.lower() for a in aliases)),
            None,
        )
        hints[area] = matched if matched else purpose
    return hints


def parse_day_segments(
    location: str | None,
    purpose: str | None,
    duration: str | None,
) -> list[dict[str, Any]]:
    """Split a trip request into per-area / per-purpose day segments.

    Returns a list of segment dicts with day_numbers + area + purpose_hint and
    an empty anchor_courses slot. Downstream retrieval fills it in.

    If no areas are detected in the user's text, returns a single segment
    covering every day with area=None and purpose_hint=purpose.
    """
    num_days = _parse_num_days(duration)
    areas = extract_requested_areas(location, purpose)

    if not areas:
        return [{
            "day_numbers":     list(range(1, num_days + 1)),
            "area":            None,
            "purpose_hint":    purpose or "",
            "anchor_courses":  [],
        }]

    purpose_hints = _split_purpose_by_area(purpose or "", areas)

    # Distribute days evenly; last area absorbs any remainder so all days are covered.
    days_per_area = max(1, num_days // len(areas))
    segments: list[dict[str, Any]] = []
    cursor = 1
    for i, area in enumerate(areas):
        if i == len(areas) - 1:
            day_range = list(range(cursor, num_days + 1))
        else:
            end = min(cursor + days_per_area, num_days + 1)
            day_range = list(range(cursor, end))
            cursor = end
        if not day_range:
            continue
        segments.append({
            "day_numbers":     day_range,
            "area":            area,
            "purpose_hint":    purpose_hints.get(area, purpose or ""),
            "anchor_courses":  [],
        })
    return segments


def retrieve_for_segments(
    api_key: str,
    segments: list[dict[str, Any]],
    purpose: str | None = None,
    courses_per_segment: int = 3,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Per-segment Index A retrieval.

    For each segment, pull the top-k whole anchor courses for the (area, purpose)
    pair from Index A. Gaps the courses don't cover (cafes, restaurants, K-POP,
    shopping) are filled later by Google Places in plan_node and by the validator
    / critic-repair.

    Returns (segments_with_data, all_anchor_courses_flat). The flat list is
    deduplicated by course_id and is what TravelState.retrieved_courses should
    be set to for backward compat with critic_repair / _normalize_sources.
    """
    store_a = build_or_load_vectorstore(api_key)

    seen_course_ids: set[str] = set()
    all_courses: list[dict[str, Any]] = []

    for seg in segments:
        area = seg.get("area")
        purpose_hint = seg.get("purpose_hint") or ""
        area_lbl = area_label(area) if area else ""

        query_a = f"{area_lbl} {purpose_hint} Seoul travel itinerary".strip()
        docs_a = store_a.similarity_search(query_a, k=courses_per_segment)

        anchors: list[dict[str, Any]] = []
        for d in docs_a:
            course = d.metadata.get("course") or {}
            cid = course.get("course_id")
            if not cid:
                continue
            anchors.append(course)
            if cid not in seen_course_ids:
                seen_course_ids.add(cid)
                all_courses.append(course)
        seg["anchor_courses"] = anchors

        print(
            f"[RAG] segment days={seg.get('day_numbers')} area={area or '-'} "
            f"anchors={len(anchors)}"
        )

    return segments, all_courses
