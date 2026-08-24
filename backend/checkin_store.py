"""Trip check-in persistence — one row per trip.

Postgres in production (Render injects DATABASE_URL); a local SQLite file
otherwise, so dev and the self-check run offline. The SQL is deliberately
ANSI-plain (TEXT columns holding JSON, ON CONFLICT upsert) so one statement
works on both engines — only the parameter placeholder differs.

ponytail: one table, no ORM, no migration tool. Add one when a second table
needs to relate to this one.
"""
import json
import logging
import os
import sqlite3
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

# Set once _connect() has logged which backend it picked, so a busy process
# doesn't repeat the line on every save/load call.
_backend_logged = False

_DEFAULT_SQLITE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "checkins.db"
)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS trip_checkins (
    trip_id    TEXT PRIMARY KEY,
    device_id  TEXT NOT NULL,
    itinerary  TEXT NOT NULL,
    days       TEXT NOT NULL,
    updated_at TEXT NOT NULL
)
"""

_UPSERT = """
INSERT INTO trip_checkins (trip_id, device_id, itinerary, days, updated_at)
VALUES ({p}, {p}, {p}, {p}, {p})
ON CONFLICT (trip_id) DO UPDATE SET
    device_id  = EXCLUDED.device_id,
    itinerary  = EXCLUDED.itinerary,
    days       = EXCLUDED.days,
    updated_at = EXCLUDED.updated_at
"""

_SELECT = """
SELECT trip_id, device_id, itinerary, days, updated_at
FROM trip_checkins WHERE trip_id = {p}
"""


def _connect(db_path: str | None):
    """Return (connection, placeholder). Postgres when DATABASE_URL is set and
    no explicit db_path was given; SQLite otherwise."""
    global _backend_logged
    url = os.getenv("DATABASE_URL")
    if url and db_path is None:
        if not _backend_logged:
            logger.info("checkin_store: using Postgres via DATABASE_URL")
            _backend_logged = True
        import psycopg  # imported lazily so dev without the driver still runs
        return psycopg.connect(url), "%s"
    path = db_path or _DEFAULT_SQLITE
    if not _backend_logged:
        logger.info("checkin_store: using SQLite at %s", path)
        _backend_logged = True
    return sqlite3.connect(path), "?"


def save_checkin(
    trip_id: str,
    device_id: str,
    itinerary: dict,
    days: dict,
    db_path: str | None = None,
) -> bool:
    """Upsert one trip's record. Returns False on any failure instead of
    raising — the client keeps its own local copy, so a storage outage must
    never surface as an app error."""
    try:
        conn, ph = _connect(db_path)
        try:
            with conn:
                cur = conn.cursor()
                cur.execute(_SCHEMA)
                cur.execute(
                    _UPSERT.format(p=ph),
                    (
                        trip_id,
                        device_id,
                        json.dumps(itinerary, ensure_ascii=False),
                        json.dumps(days, ensure_ascii=False),
                        datetime.now(timezone.utc).isoformat(),
                    ),
                )
        finally:
            conn.close()
        return True
    except Exception:
        logger.exception(
            "checkin_store: save_checkin failed for trip_id=%s", trip_id
        )
        return False


def load_checkin(trip_id: str, db_path: str | None = None) -> dict | None:
    """Read one trip's record back, or None if absent. Used by the self-check
    and by offline aggregate analysis."""
    try:
        conn, ph = _connect(db_path)
        try:
            cur = conn.cursor()
            cur.execute(_SCHEMA)
            cur.execute(_SELECT.format(p=ph), (trip_id,))
            row = cur.fetchone()
        finally:
            conn.close()
    except Exception:
        logger.exception(
            "checkin_store: load_checkin failed for trip_id=%s", trip_id
        )
        return None
    if row is None:
        return None
    return {
        "trip_id": row[0],
        "device_id": row[1],
        "itinerary": json.loads(row[2]),
        "days": json.loads(row[3]),
        "updated_at": row[4],
    }
