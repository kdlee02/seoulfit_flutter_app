# Trip Check-in & Recap — Design Spec

**Date:** 2026-08-24
**Status:** approved for implementation
**Supersedes:** the "코스 완주 화면" draft discussed in chat (see "Cut scope" for what was dropped and why)

## Goal

Let a traveller record which planned POIs they actually visited, day by day, and
see a recap at the end of the trip. The check-in data is persisted server-side so
the deterministic feasibility score the pipeline already computes (F(p)) can later
be compared against real completion rates in aggregate.

## Code audit — findings that shaped this design

These were verified against the repo on 2026-08-24, not assumed.

1. **F(p) already reaches the client.** `make_critic_repair_node` writes
   `itinerary["critic_report"] = {"before": …, "after": …, …}`
   ([critic_repair.py:1026](../../../backend/critic_repair.py#L1026)), and the whole
   `itinerary` dict is serialised into `StateResponse.itinerary`
   ([api.py:132](../../../backend/api.py#L132)). `Itinerary.fromJson` keeps it verbatim
   in `raw` ([travel_state.dart:78](../../../lib/models/travel_state.dart#L78)).
   **No backend change is needed to read the score** — it lives at
   `itinerary.raw['critic_report']['after']['feasibility_score']`.

2. **Existing bug in the score reader.** `_score()` at
   [final_itinerary_map_screen.dart:83](../../../lib/screens/final_itinerary_map_screen.dart#L83)
   looks for `raw['critic_report']['overall_score']`, but the real path is
   `raw['critic_report']['after']['overall_score']`. That branch is dead — the score
   pill silently renders nothing whenever the top-level `overall_score` key is absent.
   Fixed as part of Task 2.

3. **The score to use is `feasibility_score`, not `overall_score`.**
   `overall_score = 0.35·feasibility + 0.35·area_coverage + 0.15·duplicate +
   0.15·foreigner` ([critic_repair.py:459](../../../backend/critic_repair.py#L459)).
   Only the `feasibility_score` term measures meal windows, travel time and opening
   hours; the other three are unrelated to whether a traveller can complete the plan.

4. **No persistence layer exists.** `state.py` is a 25-line LangGraph `TypedDict`;
   `requirements.txt` has no database driver. A store must be added.

5. **Reusable pieces already in the repo:**
   - `shared_preferences` + `TripStorageService` — the local-storage pattern to follow.
   - `ApiService.threadId` (`trip-<ts>-<rand>`) — a per-trip identifier already
     generated client-side. Reused as `trip_id`; no new id scheme.
   - `UserSelectionScreen` — the checkbox list layout the check-in screen mirrors.
   - `SaveCompleteScreen` exists but is **not registered in `main.dart` routes**;
     it is unrelated to this feature and left alone.

## Decisions

### No login

The feature needs to group one device's records, not authenticate a person. A random
id generated on first launch and kept in `shared_preferences` is sufficient. No
Kakao/Google OAuth, no accounts, no new package — the id generator mirrors
`ApiService._newThreadId()`.

Accepted limits: reinstalling the app loses the id; records do not follow the user
to a new device. Neither matters for a single trip's record.

### Manual evening check-in, no location tracking

`geolocator` can stream coordinates (`getPositionStream`), but auto-stamping on
proximity would require background location permission on both platforms, a
persistent Android foreground-service notification, App Store justification for
`UIBackgroundModes: location`, and continuous GPS drain across a full travel day —
in exchange for pre-ticking a checkbox. Proximity stamping also misfires: passing
*near* a POI without entering it, or GPS drift into an adjacent building, both
produce false stamps.

The user ticks off what they visited. The existing one-shot
`LiveHelpService.currentLatLng()` is untouched.

### Local-first, server copy

The client writes every check-in to `shared_preferences` and renders the recap
entirely from local data. It POSTs a copy to the backend on each save. If the POST
fails the app is unaffected — the recap still works. This means one write-only
endpoint instead of a read/write API, and no server round-trip in the render path.

### Denominator = the confirmed itinerary

Completion is measured against the stops the user confirmed on
`UserSelectionScreen` (`TravelProvider.selectedStops`), not the generated draft.
POIs the user deliberately removed must never count as "missed". The confirmed stop
list is snapshotted into the check-in record at creation time, because
`selectedStops` lives in memory only and would be lost between days.

### Unchecked days are "unrecorded", never 0%

A day with no check-in is excluded from **both** numerator and denominator. Counting
it as a failure would understate completion for people who simply forgot, and would
bias the F(p) comparison toward "the model overestimates".

## Metrics

| Name | Definition |
|---|---|
| `dayRate(d)` | `visited(d).length / planned(d).length` for a checked-in day |
| `completionRate` | `Σ visited(d) / Σ planned(d)` over **checked-in days only** |
| `feasibilityScore` | `critic_report.after.feasibility_score`, snapshotted at confirmation |
| `hasEnoughData` | `checkedDays.length / planned.length >= 0.5` |

**Stamp tiers** (`dayRate`): `>= 0.80` full · `0.50–0.79` faded · `< 0.50` none.
These thresholds are a UX judgment call with no empirical basis and must be described
as such anywhere the work is written up. The exact visited/planned counts are always
stored; the tier is presentation only.

**Miss reasons**, one per unvisited POI: `time` · `stamina` · `notInterested` ·
`other`. Stored per POI, never folded into the completion rate.

## The F(p) comparison — scope limit

Showing "AI predicted 92% vs actual 89%" as a headline is not supported by the data
this feature collects:

- **No variance in the predictor.** Critic/Repair exists to raise low-scoring
  itineraries, so every plan a user receives already scores high. Without low-F(p)
  cases there is no contrast group, and no correlation can be demonstrated regardless
  of sample size.
- **Quantisation.** With 12 planned POIs the completion rate can only take values
  8.3% apart. A per-trip comparison against a continuous score is noise.
- **It can embarrass the product.** A 75%-vs-92% render is the app telling the user
  its own prediction was wrong.

Therefore the comparison is **not part of the default recap**. The data is collected
so it can be analysed in aggregate offline (`SELECT` over `trip_checkins`), which is
where a real finding — e.g. "F(p) has no fatigue term and overestimates afternoons
with 3+ POIs" — would come from.

Task 7 implements an opt-in comparison row for demo purposes, gated on
`hasEnoughData`, worded as "실행가능성 점수" and never as a probability or accuracy.
It is the last task and can be dropped without affecting anything else.

## Cut scope

| Dropped | Reason |
|---|---|
| Opt-in toggle screen | Opt-in by use: the entry point sits on the existing itinerary screen. No record is created until the user taps it. A whole screen and its state for a question the first tap already answers. |
| Evening push notification | Would pull in `flutter_local_notifications` plus iOS/Android permission flows — more work than the toggle it was meant to replace. |
| Real-time GPS auto-stamp | See "Manual evening check-in". |
| Total distance travelled | Without GPS this is planned coordinate distance, not travelled distance. Weak stat, and not worth adding tracking for. |
| Instagram-story share card | The largest build item in the draft and worth nothing to the data goal. |
| `GET /trip/recap` | The client already holds the data; a server read path would be a second source of truth. |
| "여행 마무리하기" as the recap trigger | The recap reads whatever has been checked in so far. A dedicated finalise step adds a state machine for no benefit; the entry point simply offers "요약 보기". |

## Non-goals

- Recovering records after reinstall or on a second device.
- Recording POIs visited that were not in the plan. Known gap; completion rate
  undercounts for travellers who improvise. Revisit only if it shows up in real use.
- Any change to the Generator → Critic → Replanner/Repair pipeline itself.
