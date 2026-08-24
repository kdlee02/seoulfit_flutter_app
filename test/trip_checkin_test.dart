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
