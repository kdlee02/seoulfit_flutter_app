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
