"""Pre-build the POI-level FAISS index (Index B) over course_data.json.

Run this after build_index.py. Index B stores one document per POI
(552 total across 126 courses) and saves to vectorstore_poi/.

Usage:
    GOOGLE_API_KEY=AIza... python build_index2.py
    python build_index2.py AIza...
    python build_index2.py --rebuild
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rag import (
    COURSE_DATA_PATH,
    POI_VECTORSTORE_DIR,
    build_or_load_poi_vectorstore,
    _load_courses,
    _build_poi_documents,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Pre-build the POI-level FAISS index (Index B).")
    parser.add_argument(
        "api_key",
        nargs="?",
        default=os.environ.get("GOOGLE_API_KEY"),
        help="Gemini API key (or set GOOGLE_API_KEY env var).",
    )
    parser.add_argument(
        "--rebuild",
        action="store_true",
        help="Force re-embedding even if vectorstore_poi/ already exists.",
    )
    args = parser.parse_args()

    if not args.api_key:
        print(
            "❌ No API key provided. Pass it as the first argument or set GOOGLE_API_KEY.",
            file=sys.stderr,
        )
        return 1

    if not COURSE_DATA_PATH.exists():
        print(f"❌ course_data.json not found at {COURSE_DATA_PATH}", file=sys.stderr)
        return 1

    courses = _load_courses()
    docs = _build_poi_documents(courses)

    print(f"📂 Course data  : {COURSE_DATA_PATH}")
    print(f"💾 POI index    : {POI_VECTORSTORE_DIR}")
    print(f"📄 Courses      : {len(courses)}")
    print(f"📍 POI documents: {len(docs)}")
    print(f"🔁 Rebuild      : {args.rebuild}")

    already_exists = (POI_VECTORSTORE_DIR / "index.faiss").exists()
    if already_exists and not args.rebuild:
        print("ℹ️  Index already exists — loading from disk (use --rebuild to re-embed).")
    else:
        batches = (len(docs) + 49) // 50
        print(f"⏳ Embedding {len(docs)} POIs in ~{batches} batches ...")

    t0 = time.time()
    store = build_or_load_poi_vectorstore(args.api_key, rebuild=args.rebuild)
    elapsed = time.time() - t0

    n_docs = store.index.ntotal if hasattr(store, "index") else "?"
    print(f"✅ Done. Indexed {n_docs} POIs in {elapsed:.1f}s.")
    print(f"   POI index saved to {POI_VECTORSTORE_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
