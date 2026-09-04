# Trip Check-in & Recap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a traveller tick off which planned stops they actually visited each day, see a recap built from those ticks, and persist a copy server-side so the pipeline's existing feasibility score can be compared against real completion rates in aggregate.

**Architecture:** Local-first. The client snapshots the confirmed stop list into `shared_preferences`, records per-day check-ins there, and renders the recap purely from local data. Each save also fires a best-effort `POST /trip/checkin`; a failure is swallowed and never blocks the UI. The backend upserts one row per trip into a single table — Postgres when `DATABASE_URL` is set (Render), SQLite otherwise (dev/tests), with identical SQL.

**Tech Stack:** Flutter (`provider`, `shared_preferences`, `http` — all already in `pubspec.yaml`, no new packages), FastAPI, `psycopg[binary]` (new), `sqlite3` (stdlib).

**Spec:** [docs/superpowers/specs/2026-08-24-trip-checkin-recap-design.md](../specs/2026-08-24-trip-checkin-recap-design.md)

## Global Constraints

- **No new Flutter packages.** `shared_preferences`, `provider`, `http`, `google_fonts` are already declared. The device id generator mirrors `ApiService._newThreadId()` rather than adding `uuid`.
- **No login, no OAuth, no accounts.** Identity is a random per-install string in `shared_preferences`.
- **No location tracking.** Do not add `getPositionStream`, background location modes, or any new `geolocator` call.
- **`trip_id` is the existing `ApiService.threadId`** (`trip-<ts>-<rand>`). Do not invent a second trip identifier.
- **The score to read is `feasibility_score`, not `overall_score`.** Path: `itinerary.raw['critic_report']['after']['feasibility_score']`.
- **Day numbers are normalised as `day == 0 ? 1 : day`**, matching [route_variation_screen.dart:186](../../../lib/screens/route_variation_screen.dart#L186). Apply this everywhere a `Poi.day` is read.
- **Unrecorded days are excluded from both numerator and denominator** of the completion rate. Never count them as 0%.
- **Stamp thresholds:** `>= 0.80` full · `0.50–0.79` faded · `< 0.50` none. Presentation only — always persist the exact counts.
- **Theme tokens only:** `kMint`, `kMintLight`, `kCanvas`, `kInk`, `kSubtext`, `kCard`, `kCardBorder`, `kSuccess` from `lib/theme/app_theme.dart`. No new hardcoded colours. Consult the `seoulfit-flutter-ui` skill before adding any spacing/motion value.
- **Backend tests are plain `assert` scripts run with `python <file>.py`** — matching `backend/test_reorder_supplements.py`. Do not introduce pytest.
- **Verification commands:** `flutter analyze`, `flutter test`, and `backend/venv/bin/python backend/test_checkin_store.py`.

---

### Task 1: Backend check-in store and endpoint

**Files:**
- Create: `backend/checkin_store.py`
- Create: `backend/test_checkin_store.py`
- Modify: `backend/requirements.txt` (append `psycopg[binary]`)
- Modify: `backend/api.py` (add request model near line 147, endpoint after `/transit-legs`)

**Interfaces:**
- Produces: `save_checkin(trip_id: str, device_id: str, itinerary: dict, days: dict, db_path: str | None = None) -> bool`
- Produces: `load_checkin(trip_id: str, db_path: str | None = None) -> dict | None` — returns `{"trip_id", "device_id", "itinerary", "days", "updated_at"}` with `itinerary`/`days` decoded back to dicts.
- Produces: `POST /trip/checkin` accepting `{trip_id, device_id, itinerary, days}`, returning `{"stored": bool}`.

- [ ] **Step 1: Write the failing test**

Create `backend/test_checkin_store.py`:

```python
"""Self-check for checkin_store: round-trip, upsert, and failure isolation.

Runs against a temp SQLite file so it needs no DATABASE_URL and no network.
The same SQL runs against Postgres in production — the only difference is the
parameter placeholder, which _connect() supplies.

Run:  backend/venv/bin/python backend/test_checkin_store.py
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from checkin_store import save_checkin, load_checkin  # noqa: E402

ITIN = {"planned": {"1": ["Gyeongbokgung", "Tosokchon"]}, "feasibility_score": 0.92}
DAYS = {"1": {"visited": ["Gyeongbokgung"], "misses": {"Tosokchon": "time"}}}


def test_round_trip(db):
    assert save_checkin("trip-a", "dev-1", ITIN, DAYS, db_path=db) is True
    row = load_checkin("trip-a", db_path=db)
    assert row is not None, "saved row should load back"
    assert row["device_id"] == "dev-1"
    assert row["itinerary"] == ITIN, row["itinerary"]
    assert row["days"] == DAYS, row["days"]
    assert row["updated_at"]


def test_upsert_replaces_not_duplicates(db):
    save_checkin("trip-b", "dev-1", ITIN, {"1": {"visited": [], "misses": {}}}, db_path=db)
    save_checkin("trip-b", "dev-1", ITIN, DAYS, db_path=db)
    row = load_checkin("trip-b", db_path=db)
    assert row["days"] == DAYS, "second save must overwrite the first"


def test_missing_trip_is_none(db):
    assert load_checkin("trip-nope", db_path=db) is None


def test_unicode_survives(db):
    days = {"1": {"visited": ["경복궁"], "misses": {"토속촌": "stamina"}}}
    save_checkin("trip-c", "dev-1", ITIN, days, db_path=db)
    assert load_checkin("trip-c", db_path=db)["days"] == days


def test_bad_path_returns_false_not_raises():
    ok = save_checkin("trip-d", "dev-1", ITIN, DAYS, db_path="/nonexistent-dir/x.db")
    assert ok is False, "storage failure must be reported, not raised"


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        db = os.path.join(tmp, "test.db")
        test_round_trip(db)
        test_upsert_replaces_not_duplicates(db)
        test_missing_trip_is_none(db)
        test_unicode_survives(db)
        test_bad_path_returns_false_not_raises()
    print("checkin_store: all checks passed")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `backend/venv/bin/python backend/test_checkin_store.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'checkin_store'`

- [ ] **Step 3: Write the store**

Create `backend/checkin_store.py`:

```python
"""Trip check-in persistence — one row per trip.

Postgres in production (Render injects DATABASE_URL); a local SQLite file
otherwise, so dev and the self-check run offline. The SQL is deliberately
ANSI-plain (TEXT columns holding JSON, ON CONFLICT upsert) so one statement
works on both engines — only the parameter placeholder differs.

ponytail: one table, no ORM, no migration tool. Add one when a second table
needs to relate to this one.
"""
import json
import os
import sqlite3
from datetime import datetime, timezone

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
    url = os.getenv("DATABASE_URL")
    if url and db_path is None:
        import psycopg  # imported lazily so dev without the driver still runs
        return psycopg.connect(url), "%s"
    return sqlite3.connect(db_path or _DEFAULT_SQLITE), "?"


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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `backend/venv/bin/python backend/test_checkin_store.py`
Expected: `checkin_store: all checks passed`

- [ ] **Step 5: Add the driver to requirements**

Append to `backend/requirements.txt`:

```
# Trip check-in persistence (checkin_store.py). Render injects DATABASE_URL;
# without it the store falls back to a local SQLite file and this is unused.
psycopg[binary]>=3.1
```

- [ ] **Step 6: Add the request model to api.py**

Insert after the `TransitLegsRequest` class (`backend/api.py:147-148`):

```python
class CheckinRequest(BaseModel):
    trip_id: str
    device_id: str
    itinerary: dict     # snapshot: planned stops per day + feasibility_score
    days: dict          # day number (as str) → {visited: [...], misses: {...}}
```

- [ ] **Step 7: Add the endpoint**

Add the import next to the other backend module imports in `backend/api.py`:

```python
from checkin_store import save_checkin
```

Append the endpoint after the `/transit-legs` handler:

```python
@app.post("/trip/checkin")
def trip_checkin(req: CheckinRequest):
    """Store one trip's check-in snapshot. Write-only: the client renders its
    recap from its own local copy, so there is no read path here. Returns
    stored=false rather than an error when persistence is unavailable."""
    # Trust-boundary validation: ids are used as a primary key, and the two
    # JSON blobs come straight off the wire.
    if not req.trip_id or len(req.trip_id) > 128:
        raise HTTPException(status_code=422, detail="invalid trip_id")
    if not req.device_id or len(req.device_id) > 128:
        raise HTTPException(status_code=422, detail="invalid device_id")
    payload_bytes = len(json.dumps(req.itinerary)) + len(json.dumps(req.days))
    if payload_bytes > 256_000:
        raise HTTPException(status_code=413, detail="payload too large")

    return {"stored": save_checkin(req.trip_id, req.device_id, req.itinerary, req.days)}
```

If `json` is not already imported at the top of `api.py`, add `import json` beside `import os`.

- [ ] **Step 8: Smoke-test the endpoint**

```bash
backend/venv/bin/python -m uvicorn api:app --port 8000 --app-dir backend &
sleep 3
curl -s -X POST localhost:8000/trip/checkin \
  -H 'Content-Type: application/json' \
  -d '{"trip_id":"trip-smoke","device_id":"dev-smoke","itinerary":{"planned":{"1":["경복궁"]}},"days":{"1":{"visited":["경복궁"],"misses":{}}}}'
```

Expected: `{"stored":true}`. Then confirm the reject path:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST localhost:8000/trip/checkin \
  -H 'Content-Type: application/json' \
  -d '{"trip_id":"","device_id":"d","itinerary":{},"days":{}}'
```

Expected: `422`. Stop the server afterwards (`kill %1`).

- [ ] **Step 9: Ignore the dev database file**

Append to `.gitignore`:

```
backend/checkins.db
```

- [ ] **Step 10: Commit**

```bash
git add backend/checkin_store.py backend/test_checkin_store.py backend/requirements.txt backend/api.py .gitignore
git commit -m "feat(backend): trip check-in store and POST /trip/checkin"
```

---

### Task 2: Check-in model and score getters

**Files:**
- Create: `lib/models/trip_checkin.dart`
- Create: `test/trip_checkin_test.dart`
- Modify: `lib/models/travel_state.dart` (add getters to `Itinerary`, after the `raw` field block ending line 85)
- Modify: `lib/screens/final_itinerary_map_screen.dart:78-88` (replace `_score`)

**Interfaces:**
- Consumes: `Poi` (`name`, `day`) and `Itinerary` (`raw`) from `lib/models/travel_state.dart`.
- Produces: `enum MissReason { time, stamina, notInterested, other }`, `enum StampTier { full, faded, none }`, `class DayCheckin`, `class TripCheckin`.
- Produces: `TripCheckin.fromStops(String tripId, List<Poi> stops, double? feasibilityScore)`.
- Produces: `TripCheckin` members `plannedDays`, `checkedDays`, `dayRate(int)`, `stampFor(int)`, `completionRate`, `hasEnoughData`, `withDay(int, DayCheckin)`, `toJson()`, `TripCheckin.fromJson(Map)`.
- Produces: `Itinerary.feasibilityScore` and `Itinerary.overallScore` (both `double?`).

- [ ] **Step 1: Write the failing test**

Create `test/trip_checkin_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:seoulfit_flutter/models/trip_checkin.dart';
import 'package:seoulfit_flutter/models/travel_state.dart';

TripCheckin _twoDayTrip() => const TripCheckin(
      tripId: 't1',
      planned: {
        1: ['A', 'B', 'C', 'D', 'E'],
        2: ['F', 'G', 'H', 'I', 'J'],
      },
    );

void main() {
  test('unrecorded days are excluded, not counted as zero', () {
    final trip = _twoDayTrip().withDay(
      1,
      const DayCheckin(visited: {'A', 'B', 'C', 'D', 'E'}),
    );
    // Day 2 was never checked in → it must not drag the rate down.
    expect(trip.completionRate, 1.0);
    expect(trip.checkedDays, [1]);
  });

  test('completion aggregates across checked days only', () {
    final trip = _twoDayTrip()
        .withDay(1, const DayCheckin(visited: {'A', 'B', 'C', 'D'}))
        .withDay(2, const DayCheckin(visited: {'F'}));
    expect(trip.completionRate, closeTo(5 / 10, 1e-9));
  });

  test('visited names outside the plan cannot inflate the rate', () {
    final trip = _twoDayTrip()
        .withDay(1, const DayCheckin(visited: {'A', 'B', 'ZZ', 'YY'}));
    expect(trip.completionRate, closeTo(2 / 5, 1e-9));
  });

  test('completionRate is null when nothing is checked in', () {
    expect(_twoDayTrip().completionRate, isNull);
  });

  test('stamp tiers sit on the documented thresholds', () {
    final full = _twoDayTrip()
        .withDay(1, const DayCheckin(visited: {'A', 'B', 'C', 'D'})); // 0.80
    final faded = _twoDayTrip()
        .withDay(1, const DayCheckin(visited: {'A', 'B', 'C'})); // 0.60
    final none = _twoDayTrip()
        .withDay(1, const DayCheckin(visited: {'A', 'B'})); // 0.40
    expect(full.stampFor(1), StampTier.full);
    expect(faded.stampFor(1), StampTier.faded);
    expect(none.stampFor(1), StampTier.none);
    expect(_twoDayTrip().stampFor(1), StampTier.none, reason: 'unchecked day');
    expect(_twoDayTrip().dayRate(1), isNull, reason: 'unchecked day has no rate');
  });

  test('hasEnoughData gates on half the days being checked', () {
    expect(_twoDayTrip().hasEnoughData, isFalse);
    expect(
      _twoDayTrip().withDay(1, const DayCheckin(visited: {'A'})).hasEnoughData,
      isTrue,
    );
  });

  test('fromStops groups by day and normalises day 0 to 1', () {
    final stops = [
      Poi.fromJson({'name': 'A'}, day: 0),
      Poi.fromJson({'name': 'B'}, day: 0),
      Poi.fromJson({'name': 'C'}, day: 2),
    ];
    final trip = TripCheckin.fromStops('t9', stops, 0.91);
    expect(trip.planned[1], ['A', 'B']);
    expect(trip.planned[2], ['C']);
    expect(trip.feasibilityScore, 0.91);
  });

  test('json round-trip preserves days, misses and score', () {
    final trip = _twoDayTrip().withDay(
      1,
      const DayCheckin(
        visited: {'A'},
        misses: {'B': MissReason.stamina, 'C': MissReason.notInterested},
      ),
    );
    final back = TripCheckin.fromJson(trip.toJson());
    expect(back.tripId, trip.tripId);
    expect(back.planned, trip.planned);
    expect(back.checkins[1]!.visited, {'A'});
    expect(back.checkins[1]!.misses['B'], MissReason.stamina);
    expect(back.checkins[1]!.misses['C'], MissReason.notInterested);
    expect(back.completionRate, trip.completionRate);
  });

  test('feasibilityScore reads critic_report.after, not overall_score', () {
    final it = Itinerary.fromJson({
      'summary': '',
      'days': [],
      'sources': [],
      'critic_report': {
        'after': {'overall_score': 0.88, 'feasibility_score': 0.94},
      },
    });
    expect(it.feasibilityScore, 0.94);
    // Regression: the old reader looked at critic_report['overall_score'],
    // a key make_critic_repair_node never writes, so this was always null.
    expect(it.overallScore, 0.88);
  });

  test('score getters return null when the report is absent', () {
    final it = Itinerary.fromJson({'summary': '', 'days': [], 'sources': []});
    expect(it.feasibilityScore, isNull);
    expect(it.overallScore, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/trip_checkin_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'seoulfit_flutter/models/trip_checkin.dart'`

(If the package name in `pubspec.yaml` is not `seoulfit_flutter`, use the declared `name:` value in every import above and throughout this plan.)

- [ ] **Step 3: Write the model**

Create `lib/models/trip_checkin.dart`:

```dart
import 'travel_state.dart';

/// Why a planned stop went unvisited. Stored per POI and deliberately kept out
/// of the completion rate: the feasibility score measures whether a plan is
/// physically doable, not whether the traveller felt like going.
enum MissReason { time, stamina, notInterested, other }

MissReason _reasonFromJson(String s) => MissReason.values.firstWhere(
      (r) => r.name == s,
      orElse: () => MissReason.other,
    );

/// Stamp shown for one day. Presentation only — the exact visited/planned
/// counts are always persisted alongside it.
enum StampTier { full, faded, none }

/// What the traveller reported for one day. A day with no [DayCheckin] at all
/// is "unrecorded" and is excluded from every aggregate.
class DayCheckin {
  final Set<String> visited;
  final Map<String, MissReason> misses;

  const DayCheckin({this.visited = const {}, this.misses = const {}});

  Map<String, dynamic> toJson() => {
        'visited': visited.toList(),
        'misses': misses.map((k, v) => MapEntry(k, v.name)),
      };

  factory DayCheckin.fromJson(Map<String, dynamic> json) => DayCheckin(
        visited: ((json['visited'] as List?) ?? const []).cast<String>().toSet(),
        misses: ((json['misses'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, _reasonFromJson(v as String)),
        ),
      );
}

/// One trip's check-in record. [planned] is snapshotted from the confirmed
/// selection at creation time — `TravelProvider.selectedStops` lives in memory
/// only and would be gone by the second evening.
class TripCheckin {
  final String tripId;

  /// Day number → planned POI names, in visit order.
  final Map<int, List<String>> planned;

  /// Day number → what the traveller reported. A missing key means unrecorded.
  final Map<int, DayCheckin> checkins;

  /// `critic_report.after.feasibility_score` at confirmation time, 0..1.
  final double? feasibilityScore;

  const TripCheckin({
    required this.tripId,
    required this.planned,
    this.checkins = const {},
    this.feasibilityScore,
  });

  /// Snapshot the confirmed selection. Day 0 normalises to 1, matching the
  /// route screen's grouping.
  factory TripCheckin.fromStops(
    String tripId,
    List<Poi> stops,
    double? feasibilityScore,
  ) {
    final planned = <int, List<String>>{};
    for (final s in stops) {
      (planned[s.day == 0 ? 1 : s.day] ??= <String>[]).add(s.name);
    }
    return TripCheckin(
      tripId: tripId,
      planned: planned,
      feasibilityScore: feasibilityScore,
    );
  }

  List<int> get plannedDays => planned.keys.toList()..sort();
  List<int> get checkedDays => checkins.keys.toList()..sort();

  /// Visited / planned for one day, or null if that day was never checked in.
  double? dayRate(int day) {
    final entry = checkins[day];
    final stops = planned[day];
    if (entry == null || stops == null || stops.isEmpty) return null;
    return entry.visited.where(stops.contains).length / stops.length;
  }

  StampTier stampFor(int day) {
    final rate = dayRate(day);
    if (rate == null) return StampTier.none;
    if (rate >= 0.80) return StampTier.full;
    if (rate >= 0.50) return StampTier.faded;
    return StampTier.none;
  }

  /// Completion over checked-in days only — unrecorded days leave both sides
  /// of the fraction untouched, so a forgotten evening never reads as failure.
  /// Null when nothing has been checked in yet.
  double? get completionRate {
    var visited = 0;
    var total = 0;
    for (final day in checkedDays) {
      final stops = planned[day];
      if (stops == null || stops.isEmpty) continue;
      visited += checkins[day]!.visited.where(stops.contains).length;
      total += stops.length;
    }
    return total == 0 ? null : visited / total;
  }

  /// Guards any comparison against the feasibility score: one checked day out
  /// of five says nothing about the trip.
  bool get hasEnoughData =>
      planned.isNotEmpty && checkedDays.length / planned.length >= 0.5;

  TripCheckin withDay(int day, DayCheckin entry) => TripCheckin(
        tripId: tripId,
        planned: planned,
        checkins: {...checkins, day: entry},
        feasibilityScore: feasibilityScore,
      );

  Map<String, dynamic> toJson() => {
        'trip_id': tripId,
        'planned': planned.map((k, v) => MapEntry(k.toString(), v)),
        'checkins': checkins.map((k, v) => MapEntry(k.toString(), v.toJson())),
        'feasibility_score': feasibilityScore,
      };

  factory TripCheckin.fromJson(Map<String, dynamic> json) => TripCheckin(
        tripId: json['trip_id'] as String? ?? '',
        planned: ((json['planned'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(
            int.parse(k as String),
            (v as List).cast<String>(),
          ),
        ),
        checkins: ((json['checkins'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(
            int.parse(k as String),
            DayCheckin.fromJson(Map<String, dynamic>.from(v as Map)),
          ),
        ),
        feasibilityScore: (json['feasibility_score'] as num?)?.toDouble(),
      );
}
```

- [ ] **Step 4: Add the score getters to Itinerary**

In `lib/models/travel_state.dart`, inside `class Itinerary`, after the `Itinerary.fromJson` factory:

```dart
  /// The deterministic feasibility term from the critic report — meal windows,
  /// travel time between stops, and opening hours. 0..1, or null if the plan
  /// was never scored.
  ///
  /// Deliberately not [overallScore]: that one blends in requested-area
  /// coverage and foreigner-readiness, neither of which says anything about
  /// whether a traveller can complete the plan.
  double? get feasibilityScore => _afterScore('feasibility_score');

  /// The blended critic score, 0..1.
  double? get overallScore {
    final direct = raw['overall_score'] ?? raw['score'];
    if (direct is num) return direct.toDouble();
    return _afterScore('overall_score');
  }

  /// `make_critic_repair_node` nests the scores under
  /// `critic_report.after`; the flat `critic_report[key]` lookup is kept only
  /// as a fallback for older payloads.
  double? _afterScore(String key) {
    final report = raw['critic_report'];
    if (report is! Map) return null;
    final after = report['after'];
    if (after is Map && after[key] is num) return (after[key] as num).toDouble();
    if (report[key] is num) return (report[key] as num).toDouble();
    return null;
  }
```

- [ ] **Step 5: Fix the dead score reader**

In `lib/screens/final_itinerary_map_screen.dart`, replace the whole `_score` method (lines 78-88) with:

```dart
  double? _score(Itinerary it) => it.overallScore;
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/trip_checkin_test.dart && flutter analyze`
Expected: all tests pass, analyze reports no new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/models/trip_checkin.dart lib/models/travel_state.dart lib/screens/final_itinerary_map_screen.dart test/trip_checkin_test.dart
git commit -m "feat(flutter): trip check-in model; fix dead critic score reader"
```

---

### Task 3: Local persistence and device id

**Files:**
- Create: `lib/services/checkin_store.dart`
- Create: `test/checkin_store_test.dart`

**Interfaces:**
- Consumes: `TripCheckin` from Task 2.
- Produces: `CheckinStore.deviceId() → Future<String>`, `CheckinStore.save(TripCheckin) → Future<void>`, `CheckinStore.load(String tripId) → Future<TripCheckin?>`.

- [ ] **Step 1: Write the failing test**

Create `test/checkin_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:seoulfit_flutter/services/checkin_store.dart';
import 'package:seoulfit_flutter/models/trip_checkin.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('device id is generated once and then reused', () async {
    final first = await CheckinStore.deviceId();
    final second = await CheckinStore.deviceId();
    expect(first, isNotEmpty);
    expect(second, first);
  });

  test('saved trip loads back with its check-ins intact', () async {
    const trip = TripCheckin(
      tripId: 'trip-x',
      planned: {
        1: ['A', 'B']
      },
      feasibilityScore: 0.9,
    );
    await CheckinStore.save(
      trip.withDay(1, const DayCheckin(visited: {'A'}, misses: {'B': MissReason.time})),
    );
    final back = await CheckinStore.load('trip-x');
    expect(back, isNotNull);
    expect(back!.checkins[1]!.visited, {'A'});
    expect(back.checkins[1]!.misses['B'], MissReason.time);
    expect(back.feasibilityScore, 0.9);
  });

  test('unknown trip loads as null', () async {
    expect(await CheckinStore.load('nope'), isNull);
  });

  test('trips are stored independently', () async {
    await CheckinStore.save(const TripCheckin(tripId: 'a', planned: {1: ['A']}));
    await CheckinStore.save(const TripCheckin(tripId: 'b', planned: {1: ['B']}));
    expect((await CheckinStore.load('a'))!.planned[1], ['A']);
    expect((await CheckinStore.load('b'))!.planned[1], ['B']);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/checkin_store_test.dart`
Expected: FAIL — cannot resolve `services/checkin_store.dart`

- [ ] **Step 3: Write the store**

Create `lib/services/checkin_store.dart`:

```dart
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_checkin.dart';

/// Local-first store for trip check-ins, following the same
/// `shared_preferences` + JSON pattern as [TripStorageService].
///
/// The recap renders entirely from here; the backend copy written by
/// [ApiService.postCheckin] is best-effort and never read back.
class CheckinStore {
  static const _deviceKey = 'device_id';
  static const _tripPrefix = 'checkin_';
  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// Stable per-install identifier, generated on first call. No account and no
  /// OAuth: this only needs to group one device's records, not authenticate a
  /// person. Mirrors `ApiService._newThreadId`'s alphabet so ids look alike in
  /// logs. Lost on reinstall — acceptable for a single trip's record.
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rand = Random.secure();
    final id =
        'dev-${List.generate(16, (_) => _alphabet[rand.nextInt(36)]).join()}';
    await prefs.setString(_deviceKey, id);
    return id;
  }

  static Future<void> save(TripCheckin trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_tripPrefix${trip.tripId}',
      jsonEncode(trip.toJson()),
    );
  }

  static Future<TripCheckin?> load(String tripId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_tripPrefix$tripId');
    if (raw == null) return null;
    return TripCheckin.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/checkin_store_test.dart && flutter analyze`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/checkin_store.dart test/checkin_store_test.dart
git commit -m "feat(flutter): local check-in store with per-install device id"
```

---

### Task 4: Check-in screen and entry point

**Files:**
- Create: `lib/screens/trip_checkin_screen.dart`
- Modify: `lib/main.dart` (import + `'/trip-checkin'` route after `'/route-variation'`, line 56)
- Modify: `lib/screens/route_variation_screen.dart` (entry-point card between lines 349 and 350)

**Interfaces:**
- Consumes: `TripCheckin`, `DayCheckin`, `MissReason`, `StampTier` (Task 2); `CheckinStore` (Task 3); `TravelProvider.selectedStops`, `TravelProvider.itinerary`.
- Produces: route `'/trip-checkin'` rendering `TripCheckinScreen`, which reads/writes the record for the trip id it is given.
- Produces: `TravelProvider.tripId` — the `ApiService.threadId` for the active trip, exposed so the screen and the sync call agree on one id.

- [ ] **Step 1: Expose the trip id on the provider**

In `lib/providers/travel_provider.dart`, add next to the other getters (after `Itinerary? get itinerary`):

```dart
  /// The backend thread id for this planning session, reused as the trip id so
  /// check-in records line up with the conversation that produced the plan.
  String get tripId => _api.threadId;
```

- [ ] **Step 2: Write the check-in screen**

Create `lib/screens/trip_checkin_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/trip_checkin.dart';
import '../providers/travel_provider.dart';
import '../services/checkin_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';

const _reasonLabels = {
  MissReason.time: '시간 부족',
  MissReason.stamina: '체력 부족',
  MissReason.notInterested: '마음이 안 감',
  MissReason.other: '기타',
};

/// One day at a time: tick what you visited, and say why for the rest.
/// Opens on the first day that has no record yet.
class TripCheckinScreen extends StatefulWidget {
  const TripCheckinScreen({super.key});

  @override
  State<TripCheckinScreen> createState() => _TripCheckinScreenState();
}

class _TripCheckinScreenState extends State<TripCheckinScreen> {
  TripCheckin? _trip;
  int _day = 1;
  Set<String> _visited = {};
  Map<String, MissReason> _misses = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final provider = context.read<TravelProvider>();
    final tripId = provider.tripId;
    // Load an existing record, or snapshot the confirmed selection into a new
    // one. selectedStops is memory-only, so this snapshot is what later days
    // measure against.
    var trip = await CheckinStore.load(tripId);
    trip ??= TripCheckin.fromStops(
      tripId,
      provider.selectedStops.isNotEmpty
          ? provider.selectedStops
          : provider.allPois,
      provider.itinerary?.feasibilityScore,
    );
    final days = trip.plannedDays;
    final firstUnchecked =
        days.firstWhere((d) => !trip!.checkins.containsKey(d), orElse: () => days.isEmpty ? 1 : days.first);
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _day = firstUnchecked;
      _loading = false;
    });
    _loadDay(firstUnchecked);
  }

  void _loadDay(int day) {
    final entry = _trip?.checkins[day];
    setState(() {
      _day = day;
      _visited = {...?entry?.visited};
      _misses = {...?entry?.misses};
    });
  }

  void _toggle(String name) {
    setState(() {
      if (_visited.remove(name)) return;
      _visited.add(name);
      _misses.remove(name);
    });
  }

  Future<void> _saveDay() async {
    final trip = _trip;
    if (trip == null) return;
    final stops = trip.planned[_day] ?? const <String>[];
    // Anything not ticked is a miss; default to "other" if no reason was given.
    final misses = <String, MissReason>{
      for (final name in stops)
        if (!_visited.contains(name)) name: _misses[name] ?? MissReason.other,
    };
    final updated = trip.withDay(
      _day,
      DayCheckin(visited: {..._visited}, misses: misses),
    );
    await CheckinStore.save(updated);
    if (!mounted) return;
    setState(() => _trip = updated);
    Navigator.pushNamed(context, '/trip-recap');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kCanvas,
        body: Center(child: CircularProgressIndicator(color: kMint)),
      );
    }
    final trip = _trip!;
    final stops = trip.planned[_day] ?? const <String>[];
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppStatusBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text('오늘 다녀오셨나요?',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text('다녀온 곳을 눌러서 체크하세요. 안 누른 곳은 이유를 골라주세요.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: kSubtext)),
            ),
            if (trip.plannedDays.length > 1)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final d in trip.plannedDays)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('Day $d'),
                          selected: d == _day,
                          selectedColor: kMintLight,
                          onSelected: (_) => _loadDay(d),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                itemCount: stops.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final name = stops[i];
                  final visited = _visited.contains(name);
                  return _StopTile(
                    name: name,
                    visited: visited,
                    reason: _misses[name],
                    onToggle: () => _toggle(name),
                    onReason: (r) => setState(() => _misses[name] = r),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: stops.isEmpty ? null : _saveDay,
                  child: Text('Day $_day 기록하기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final String name;
  final bool visited;
  final MissReason? reason;
  final VoidCallback onToggle;
  final ValueChanged<MissReason> onReason;

  const _StopTile({
    required this.name,
    required this.visited,
    required this.reason,
    required this.onToggle,
    required this.onReason,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: visited ? kMint : kCardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(
                  visited
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: visited ? kSuccess : kSubtext,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: kInk)),
                ),
              ],
            ),
          ),
          if (!visited) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in _reasonLabels.entries)
                  ChoiceChip(
                    label: Text(entry.value,
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    selected: reason == entry.key,
                    selectedColor: kMintLight,
                    onSelected: (_) => onReason(entry.key),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Register the route**

In `lib/main.dart`, add the import beside the other screen imports:

```dart
import 'screens/trip_checkin_screen.dart';
```

and the route after `'/route-variation'`:

```dart
          '/trip-checkin': (ctx) => const TripCheckinScreen(),
```

- [ ] **Step 4: Add the entry point**

In `lib/screens/route_variation_screen.dart`, insert between the stats `Container` (ends line 349) and `const SizedBox(height: 24)`:

```dart
                          const SizedBox(height: 12),
                          // Opt-in by use: no record exists until this is
                          // tapped, so the whole feature stays invisible to
                          // anyone who never wants it.
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pushNamed(
                                  context, '/trip-checkin'),
                              icon: const Icon(Icons.how_to_reg_rounded,
                                  size: 18),
                              label: Text('다녀온 곳 체크하기',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
```

- [ ] **Step 5: Verify it builds and the flow works**

Run: `flutter analyze && flutter test`
Expected: no new analyze issues, all tests pass.

Then run the app and walk: chat → confirm → `/user-selection` → `/route-variation` → tap "다녀온 곳 체크하기" → tick some stops → pick reasons for the rest → "Day 1 기록하기". Expect navigation to `/trip-recap` (a missing-route error here is expected until Task 5 lands — confirm the tick state persisted by re-entering the check-in screen instead).

- [ ] **Step 6: Commit**

```bash
git add lib/screens/trip_checkin_screen.dart lib/main.dart lib/screens/route_variation_screen.dart lib/providers/travel_provider.dart
git commit -m "feat(flutter): per-day trip check-in screen"
```

---

### Task 5: Recap screen

**Files:**
- Create: `lib/screens/trip_recap_screen.dart`
- Modify: `lib/main.dart` (import + `'/trip-recap'` route)

**Interfaces:**
- Consumes: `TripCheckin` (`plannedDays`, `checkedDays`, `dayRate`, `stampFor`, `completionRate`), `CheckinStore.load`, `TravelProvider.tripId`.
- Produces: route `'/trip-recap'` rendering `TripRecapScreen`.

- [ ] **Step 1: Write the recap screen**

Create `lib/screens/trip_recap_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/trip_checkin.dart';
import '../providers/travel_provider.dart';
import '../services/checkin_store.dart';
import '../theme/app_theme.dart';
import '../widgets/app_status_bar.dart';

/// Everything recorded so far, rendered from the local store. There is no
/// "finish the trip" step — the recap simply reflects whatever has been
/// checked in, and days with no record are shown as unrecorded rather than
/// counted as failures.
class TripRecapScreen extends StatefulWidget {
  const TripRecapScreen({super.key});

  @override
  State<TripRecapScreen> createState() => _TripRecapScreenState();
}

class _TripRecapScreenState extends State<TripRecapScreen> {
  TripCheckin? _trip;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final trip = await CheckinStore.load(context.read<TravelProvider>().tripId);
    if (!mounted) return;
    setState(() {
      _trip = trip;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kCanvas,
        body: Center(child: CircularProgressIndicator(color: kMint)),
      );
    }
    final trip = _trip;
    if (trip == null || trip.checkedDays.isEmpty) {
      return Scaffold(
        backgroundColor: kCanvas,
        body: SafeArea(
          child: Column(
            children: [
              const AppStatusBar(),
              const Spacer(),
              const Icon(Icons.inbox_rounded, size: 44, color: kSubtext),
              const SizedBox(height: 10),
              Text('아직 기록이 없어요',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w700, color: kInk)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/trip-checkin'),
                child: const Text('체크인 하러 가기'),
              ),
              const Spacer(),
            ],
          ),
        ),
      );
    }

    final rate = trip.completionRate;
    final stamped = trip.plannedDays
        .where((d) => trip.stampFor(d) != StampTier.none)
        .length;
    final unrecorded = trip.plannedDays.length - trip.checkedDays.length;

    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const AppStatusBar(),
            const SizedBox(height: 8),
            Text('여행 기록',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 24, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kMintLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Stat('완료율',
                      rate == null ? '—' : '${(rate * 100).round()}%'),
                  _Stat('스탬프', '$stamped개'),
                  _Stat('기록한 날', '${trip.checkedDays.length}일'),
                ],
              ),
            ),
            if (unrecorded > 0) ...[
              const SizedBox(height: 10),
              Text('기록하지 않은 날 $unrecorded일은 완료율 계산에서 빠졌어요.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: kSubtext)),
            ],
            const SizedBox(height: 20),
            for (final day in trip.plannedDays) ...[
              _DayRow(
                day: day,
                tier: trip.stampFor(day),
                visited: trip.checkins[day]?.visited
                        .where((n) => trip.planned[day]!.contains(n))
                        .length ??
                    0,
                planned: trip.planned[day]?.length ?? 0,
                recorded: trip.checkins.containsKey(day),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  GoogleFonts.plusJakartaSans(fontSize: 12, color: kSubtext)),
        ],
      );
}

class _DayRow extends StatelessWidget {
  final int day;
  final StampTier tier;
  final int visited;
  final int planned;
  final bool recorded;

  const _DayRow({
    required this.day,
    required this.tier,
    required this.visited,
    required this.planned,
    required this.recorded,
  });

  @override
  Widget build(BuildContext context) {
    // The stamp is decoration; the exact fraction next to it is the real record.
    final opacity = switch (tier) {
      StampTier.full => 1.0,
      StampTier.faded => 0.35,
      StampTier.none => 0.0,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: opacity,
            child: const Icon(Icons.verified_rounded, color: kMint, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Day $day',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
          ),
          Text(
            recorded ? '$planned곳 중 $visited곳' : '미기록',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: recorded ? kInk : kSubtext,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Register the route**

In `lib/main.dart`, add:

```dart
import 'screens/trip_recap_screen.dart';
```

and after `'/trip-checkin'`:

```dart
          '/trip-recap': (ctx) => const TripRecapScreen(),
```

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: no new issues.

Then in the app: complete a Day 1 check-in with 4 of 5 stops ticked on a 2-day trip. Expect the recap to show `완료율 80%`, `스탬프 1개`, `기록한 날 1일`, a full stamp on Day 1, and Day 2 as `미기록` with the "기록하지 않은 날 1일은 완료율 계산에서 빠졌어요" note. Confirm the 80% is **not** diluted to 40% by the unrecorded day.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/trip_recap_screen.dart lib/main.dart
git commit -m "feat(flutter): trip recap screen"
```

---

### Task 6: Backend sync

**Files:**
- Modify: `lib/services/api_service.dart` (add `postCheckin` after `fetchTransitLegs`)
- Modify: `lib/services/checkin_store.dart` (fire-and-forget sync from `save`)
- Modify: `test/checkin_store_test.dart` (assert sync failure does not break the save)

**Interfaces:**
- Consumes: `POST /trip/checkin` from Task 1; `CheckinStore.deviceId()`; `TripCheckin.toJson()`.
- Produces: `ApiService.postCheckin({required String deviceId, required TripCheckin trip}) → Future<bool>`.

- [ ] **Step 1: Write the failing test**

Append to `test/checkin_store_test.dart`:

```dart
  test('a failing backend sync still leaves the local save intact', () async {
    // No server is running in the test environment, so the POST inside save()
    // throws — the local write must survive it.
    await CheckinStore.save(
      const TripCheckin(tripId: 'offline', planned: {1: ['A']}),
    );
    final back = await CheckinStore.load('offline');
    expect(back, isNotNull);
    expect(back!.planned[1], ['A']);
  });
```

- [ ] **Step 2: Run it to confirm the current behaviour**

Run: `flutter test test/checkin_store_test.dart`
Expected: PASS (no sync exists yet). This test is the guard for Step 3 — it must still pass after the sync is added.

- [ ] **Step 3: Add the API call**

In `lib/services/api_service.dart`, after `fetchTransitLegs`, add the import of the model at the top:

```dart
import '../models/trip_checkin.dart';
```

and the method:

```dart
  /// Sends one trip's check-in snapshot to the backend. Write-only and
  /// best-effort: the client renders its recap from local storage, so a false
  /// here costs nothing but a missing row in the research table.
  Future<bool> postCheckin({
    required String deviceId,
    required TripCheckin trip,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_base/trip/checkin'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'trip_id': trip.tripId,
              'device_id': deviceId,
              'itinerary': {
                'planned': trip.planned.map((k, v) => MapEntry(k.toString(), v)),
                'feasibility_score': trip.feasibilityScore,
              },
              'days': trip.checkins
                  .map((k, v) => MapEntry(k.toString(), v.toJson())),
            }),
          )
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
```

- [ ] **Step 4: Fire the sync from the store**

In `lib/services/checkin_store.dart`, add the import:

```dart
import 'api_service.dart';
```

and change `save` to:

```dart
  /// Writes locally, then mirrors to the backend. The local write is awaited;
  /// the upload is not — a slow or dead network must never make the check-in
  /// button feel broken.
  static Future<void> save(TripCheckin trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_tripPrefix${trip.tripId}',
      jsonEncode(trip.toJson()),
    );
    unawaited(_sync(trip));
  }

  static Future<void> _sync(TripCheckin trip) async {
    try {
      await ApiService().postCheckin(deviceId: await deviceId(), trip: trip);
    } catch (_) {
      // Best-effort: the local copy is the source of truth for the recap.
    }
  }
```

Add `import 'dart:async';` at the top for `unawaited`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test && flutter analyze`
Expected: all tests pass — in particular the offline test from Step 1, proving the local write survives a dead backend.

- [ ] **Step 6: End-to-end check against a live backend**

Start the backend, complete a Day 1 check-in in the app, then confirm the row landed:

```bash
backend/venv/bin/python -c "
import sys; sys.path.insert(0, 'backend')
from checkin_store import load_checkin
print(load_checkin('PASTE_TRIP_ID_FROM_LOGS'))
"
```

Expected: a dict with the day's `visited` and `misses`, plus `itinerary.feasibility_score` carrying a number (not `None`) — that last part confirms the score really does reach the client at `critic_report.after.feasibility_score`.

- [ ] **Step 7: Commit**

```bash
git add lib/services/api_service.dart lib/services/checkin_store.dart test/checkin_store_test.dart
git commit -m "feat(flutter): mirror check-ins to the backend, best-effort"
```

---

### Task 7 (optional): Feasibility-score comparison row

**Drop this task freely.** Nothing else depends on it, and the spec's "The F(p) comparison — scope limit" section explains why the number is weak evidence: Critic/Repair removes all variance from the predictor, and completion rate is quantised into large steps. Build it only if a live demo needs the comparison on screen; the offline aggregate over `trip_checkins` is where a real finding would come from.

**Files:**
- Modify: `lib/screens/trip_recap_screen.dart` (insert after the `unrecorded > 0` block)

**Interfaces:**
- Consumes: `TripCheckin.feasibilityScore`, `TripCheckin.completionRate`, `TripCheckin.hasEnoughData`.

- [ ] **Step 1: Add the gated comparison**

In `lib/screens/trip_recap_screen.dart`, after the `if (unrecorded > 0) ...[ … ]` block:

```dart
            // Gated on hasEnoughData: one checked day out of five would render
            // a confident-looking comparison from almost no data. Worded as a
            // score, never as a probability or an accuracy — the critic's
            // feasibility term is a deterministic 0..1 rating of the plan, not
            // a prediction of whether this traveller would finish it.
            if (trip.feasibilityScore != null &&
                rate != null &&
                trip.hasEnoughData) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kCard,
                  border: Border.all(color: kCardBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('실행가능성 점수와 비교',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: kInk)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Stat('AI 실행가능성 점수',
                            '${(trip.feasibilityScore! * 100).round()}점'),
                        _Stat('실제 완료율', '${(rate * 100).round()}%'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                        '실행가능성 점수는 식사 시간대·이동 시간·영업시간을 계산한 '
                        '일정 자체의 점수예요. 완주 확률이 아니라서 두 숫자가 '
                        '달라도 예측이 틀린 건 아닙니다.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: kSubtext, height: 1.5)),
                  ],
                ),
              ),
            ],
```

- [ ] **Step 2: Verify the gate**

Run: `flutter analyze && flutter test`

Then in the app, on a 2-day trip with only Day 1 checked in (ratio 0.5), expect the card to appear. Add a third day to the plan and check in only Day 1 (ratio 0.33) — expect the card to be **absent**.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/trip_recap_screen.dart
git commit -m "feat(flutter): gated feasibility-score comparison on the recap"
```

---

## Aggregate analysis (no code — for whoever writes this up)

Once records accumulate, the finding comes from a query, not from the app:

```sql
SELECT trip_id,
       json_extract(itinerary, '$.feasibility_score') AS fp,
       days
FROM trip_checkins;
```

(`json_extract` on SQLite; `itinerary::json->>'feasibility_score'` on Postgres.)

Compute completion per trip with the same rule the client uses — checked-in days
only — and look for *where* the score misses rather than whether two averages land
close. The reason codes are the useful column: a cluster of `stamina` misses on
late-afternoon stops points at a missing fatigue term in `_evaluate_days`, which is
a defensible result. "92 vs 89" is not.
