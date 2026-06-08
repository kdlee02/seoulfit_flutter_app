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
    area_matches_requested,
    extract_requested_areas,
    infer_poi_area,
)


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

_BASE_DIR = Path(__file__).resolve().parent
COURSE_DATA_PATH = _BASE_DIR / "course_data.json"
VECTORSTORE_DIR = _BASE_DIR / "vectorstore"
POI_VECTORSTORE_DIR = _BASE_DIR / "vectorstore_poi"

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
# Index B — POI-level document construction and vector store
# ---------------------------------------------------------------------------

# Area inference (alias matching + haversine fallback) lives in geo.py.
# Imported at the top of this file.


def _time_slot(sequence_order: int, total: int) -> str:
    """Classify a POI's position in a course as morning / afternoon / evening."""
    if total <= 1:
        return "morning"
    ratio = (sequence_order - 1) / (total - 1)
    if ratio < 0.34:
        return "morning"
    if ratio < 0.67:
        return "afternoon"
    return "evening"


def _poi_to_document(
    poi: dict[str, Any],
    course: dict[str, Any],
    sequence: list[dict[str, Any]],
) -> Document:
    """Build one Index B Document for a single POI.

    page_content encodes location, theme, type, and sequence context so
    all four dimensions are searchable via embedding similarity.
    metadata stores structured fields for filtering and downstream use.
    """
    total = len(sequence)
    order = int(poi.get("sequence_order") or 1)
    slot = _time_slot(order, total)
    area = infer_poi_area(poi)

    sorted_seq = sorted(sequence, key=lambda p: int(p.get("sequence_order") or 0))
    idx = next((i for i, p in enumerate(sorted_seq)
                if int(p.get("sequence_order") or 0) == order), 0)
    prev_name = sorted_seq[idx - 1].get("poi_name") if idx > 0 else None
    next_name = sorted_seq[idx + 1].get("poi_name") if idx < total - 1 else None

    themes = ", ".join(course.get("theme_category") or [])
    address = poi.get("address_en") or poi.get("address_ko") or ""

    page_content = (
        f"POI: {poi.get('poi_name', '')}\n"
        f"Type: {poi.get('poi_type', '')}\n"
        f"Area: {area or 'Seoul'}\n"
        f"Address: {address}\n"
        f"Course: {course.get('course_title', '')}\n"
        f"Source: {course.get('source', '')}\n"
        f"Themes: {themes}\n"
        f"Position: {order} of {total} ({slot} slot)\n"
        f"Comes after: {prev_name or 'start of day'}\n"
        f"Comes before: {next_name or 'end of day'}\n"
        f"Estimated stay: {poi.get('estimated_stay_time', 60)} min\n"
    )

    metadata: dict[str, Any] = {
        "poi_name":       poi.get("poi_name", ""),
        "poi_type":       poi.get("poi_type", ""),
        "area":           area,
        "themes":         course.get("theme_category") or [],
        "time_slot":      slot,
        "course_id":      course.get("course_id", ""),
        "course_title":   course.get("course_title", ""),
        "sequence_order": order,
        "poi":            poi,
        "course":         course,
    }

    return Document(page_content=page_content, metadata=metadata)


def _build_poi_documents(courses: list[dict[str, Any]]) -> list[Document]:
    """Expand all courses into one Document per POI."""
    docs: list[Document] = []
    for course in courses:
        sequence = course.get("sequence") or []
        for poi in sequence:
            docs.append(_poi_to_document(poi, course, sequence))
    return docs


_poi_vectorstore: FAISS | None = None
_poi_vectorstore_api_key: str | None = None


def build_or_load_poi_vectorstore(
    api_key: str,
    persist_dir: Path = POI_VECTORSTORE_DIR,
    rebuild: bool = False,
) -> FAISS:
    """Return a FAISS index where each document is one POI from course_data.json.

    Loads from disk if vectorstore_poi/index.faiss exists and rebuild=False.
    Otherwise embeds all POIs and saves to disk.
    """
    global _poi_vectorstore, _poi_vectorstore_api_key

    if _poi_vectorstore is not None and _poi_vectorstore_api_key == api_key and not rebuild:
        return _poi_vectorstore

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
        docs = _build_poi_documents(courses)
        metadatas = [d.metadata for d in docs]

        text_embeddings = _embed_documents_chunked(docs, embeddings)
        store = FAISS.from_embeddings(
            text_embeddings=text_embeddings,
            embedding=embeddings,
            metadatas=metadatas,
        )
        persist_dir.mkdir(parents=True, exist_ok=True)
        store.save_local(str(persist_dir))

    _poi_vectorstore = store
    _poi_vectorstore_api_key = api_key
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
    empty anchor_courses / supplement_pois slots. Downstream retrieval fills
    those in.

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
            "supplement_pois": [],
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
            "supplement_pois": [],
        })
    return segments


def _audit_gaps(
    anchor_courses: list[dict[str, Any]],
    segment: dict[str, Any],
) -> dict[str, bool]:
    """Check whether anchor courses cover the segment's purpose.

    Returns {purpose_gap}. True means Index B should run a targeted query.
    Area coverage and meal slots are enforced downstream by the validator and
    critic-repair, so those checks are not duplicated here.
    """
    purpose_hint = (segment.get("purpose_hint") or "").lower()
    # Drop short tokens — single chars and conjunctions hurt more than they help.
    purpose_keywords = [w for w in re.findall(r"[a-z가-힣]+", purpose_hint) if len(w) > 2]

    if not purpose_keywords:
        return {"purpose_gap": False}

    if not anchor_courses:
        return {"purpose_gap": True}

    for course in anchor_courses:
        themes_lower = [t.lower() for t in (course.get("theme_category") or [])]
        for poi in (course.get("sequence") or []):
            poi_name = (poi.get("poi_name") or "").lower()
            poi_type = (poi.get("poi_type") or "").lower()
            if any(
                kw in poi_name
                or kw in poi_type
                or any(kw in t for t in themes_lower)
                for kw in purpose_keywords
            ):
                return {"purpose_gap": False}

    return {"purpose_gap": True}


def _segment_poi_search(
    store_b: FAISS,
    query: str,
    requested_area: str | None,
    k: int,
) -> list[Document]:
    """POI similarity search with adjacency-aware area filtering.

    If a segment area is given, the filter accepts the area AND its walkably
    adjacent neighbors (e.g. hongdae also accepts hapjeong/mangwon/yeonnam/mapo).
    Without adjacency expansion, a Hongdae query would only see ~13 strict-Hongdae
    POIs in the corpus.

    Falls back to unfiltered top-k * 4 + post-filter if the filtered search
    returns fewer than k results, or if the LangChain version refuses callables.
    """
    if not requested_area:
        return store_b.similarity_search(query, k=k)

    def _matches(meta: dict[str, Any]) -> bool:
        return area_matches_requested(meta.get("area"), requested_area)

    try:
        docs = store_b.similarity_search(query, k=k, filter=_matches)
    except (TypeError, ValueError):
        docs = []

    if len(docs) >= k:
        return docs

    raw = store_b.similarity_search(query, k=k * 4)
    seen_names = {(d.metadata.get("poi_name") or "") for d in docs}
    for d in raw:
        name = d.metadata.get("poi_name") or ""
        if name in seen_names:
            continue
        if _matches(d.metadata):
            docs.append(d)
            seen_names.add(name)
            if len(docs) >= k:
                break
    return docs[:k]


def retrieve_for_segments(
    api_key: str,
    segments: list[dict[str, Any]],
    purpose: str | None = None,
    courses_per_segment: int = 3,
    pois_per_gap: int = 5,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Per-segment dual-index retrieval.

    For each segment:
      1. Index A → top-k whole courses for the (area, purpose) pair.
      2. _audit_gaps decides whether any coverage dimension is missing.
      3. Index B → gap-fill POIs, one targeted query per gap, deduplicated.

    Returns (segments_with_data, all_anchor_courses_flat). The flat list is
    deduplicated by course_id and is what TravelState.retrieved_courses should
    be set to for backward compat with critic_repair / _normalize_sources.
    """
    store_a = build_or_load_vectorstore(api_key)
    store_b = build_or_load_poi_vectorstore(api_key)

    seen_course_ids: set[str] = set()
    all_courses: list[dict[str, Any]] = []

    for seg in segments:
        area = seg.get("area")
        purpose_hint = seg.get("purpose_hint") or ""
        area_lbl = area_label(area) if area else ""

        # --- Index A: anchor courses ---
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

        # --- Gap audit ---
        gaps = _audit_gaps(anchors, seg)
        print(
            f"[RAG] segment days={seg.get('day_numbers')} area={area or '-'} "
            f"anchors={len(anchors)} purpose_gap={gaps['purpose_gap']}"
        )

        if not gaps["purpose_gap"]:
            seg["supplement_pois"] = []
            continue

        # --- Index B: purpose gap-fill query ---
        gap_queries: list[str] = [f"{area_lbl} {purpose_hint}".strip()]

        seen_poi_names: set[str] = set()
        suppl: list[dict[str, Any]] = []
        for q in gap_queries:
            docs_b = _segment_poi_search(store_b, q, area, pois_per_gap)
            for d in docs_b:
                poi = d.metadata.get("poi") or {}
                name = (poi.get("poi_name") or "").strip()
                if not name or name in seen_poi_names:
                    continue
                seen_poi_names.add(name)
                course = d.metadata.get("course") or {}
                cid = course.get("course_id")
                # Annotate the POI with parent course attribution so the prompt
                # can surface it and the LLM can generate a valid sources entry.
                suppl.append({
                    **poi,
                    "course_id":    cid or "",
                    "course_title": course.get("course_title", ""),
                    "source":       course.get("source", ""),
                    "source_url":   course.get("source_url", ""),
                })
                if cid and cid not in seen_course_ids:
                    seen_course_ids.add(cid)
                    all_courses.append(course)
        seg["supplement_pois"] = suppl

    return segments, all_courses
