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

  test('fromStops snapshots coordinates, skipping stops that have none', () {
    final stops = [
      Poi.fromJson({'name': 'A', 'lat': 37.5796, 'lng': 126.9770}, day: 1),
      Poi.fromJson({'name': 'B'}, day: 1), // no coords — must not be stored
      Poi.fromJson({'name': 'C', 'lat': 37.5665, 'lng': 126.9780}, day: 2),
    ];
    final trip = TripCheckin.fromStops('t9', stops, null);
    expect(trip.coords['A'], [37.5796, 126.9770]);
    expect(trip.coords['C'], [37.5665, 126.9780]);
    expect(trip.coords.containsKey('B'), isFalse);
    // The stop itself still counts toward the plan — only its pin is missing.
    expect(trip.planned[1], ['A', 'B']);
  });

  test('fromStops collects the district from each address', () {
    final stops = [
      Poi.fromJson(
          {'name': 'A', 'address': '서울특별시 종로구 사직로 161'}, day: 1),
      Poi.fromJson({'name': 'B', 'address': '서울 종로구 율곡로 99'}, day: 1),
      Poi.fromJson({'name': 'C', 'address': '서울특별시 성북구 성북로 102'}, day: 2),
      Poi.fromJson({'name': 'D', 'address': '주소 없음'}, day: 2),
    ];
    final trip = TripCheckin.fromStops('t9', stops, null);
    expect(trip.areas, {'종로구', '성북구'});
  });

  test('latLngFor returns only coordinates for visited stops in order', () {
    final stops = [
      Poi.fromJson({'name': 'A', 'lat': 1.0, 'lng': 2.0}, day: 1),
      Poi.fromJson({'name': 'B', 'lat': 3.0, 'lng': 4.0}, day: 1),
      Poi.fromJson({'name': 'C', 'lat': 5.0, 'lng': 6.0}, day: 1),
    ];
    final trip = TripCheckin.fromStops('t9', stops, null)
        .withDay(1, const DayCheckin(visited: {'C', 'A'}));
    // Plan order, not the order the Set happens to iterate in.
    expect(trip.visitedPointsFor(1), [
      const VisitedPoint('A', 1.0, 2.0),
      const VisitedPoint('C', 5.0, 6.0),
    ]);
  });

  test('visitedPointsFor drops visited stops that have no coordinates', () {
    final stops = [
      Poi.fromJson({'name': 'A', 'lat': 1.0, 'lng': 2.0}, day: 1),
      Poi.fromJson({'name': 'B'}, day: 1),
    ];
    final trip = TripCheckin.fromStops('t9', stops, null)
        .withDay(1, const DayCheckin(visited: {'A', 'B'}));
    expect(trip.visitedPointsFor(1), [const VisitedPoint('A', 1.0, 2.0)]);
  });

  test('visitedPointsFor is empty for an unrecorded day', () {
    final stops = [
      Poi.fromJson({'name': 'A', 'lat': 1.0, 'lng': 2.0}, day: 1),
    ];
    expect(TripCheckin.fromStops('t9', stops, null).visitedPointsFor(1),
        isEmpty);
  });

  test('coords and areas survive the json round-trip', () {
    final stops = [
      Poi.fromJson(
          {'name': 'A', 'lat': 1.5, 'lng': 2.5, 'address': '서울 마포구 와우산로'},
          day: 1),
    ];
    final trip = TripCheckin.fromStops('t9', stops, 0.9)
        .withDay(1, const DayCheckin(visited: {'A'}));
    final back = TripCheckin.fromJson(trip.toJson());
    expect(back.coords['A'], [1.5, 2.5]);
    expect(back.areas, {'마포구'});
    expect(back.visitedPointsFor(1), [const VisitedPoint('A', 1.5, 2.5)]);
  });

  test('withDay preserves coords and areas', () {
    final stops = [
      Poi.fromJson({'name': 'A', 'lat': 1.0, 'lng': 2.0, 'address': '서울 중구 세종대로'},
          day: 1),
    ];
    final trip = TripCheckin.fromStops('t9', stops, null);
    final after = trip.withDay(1, const DayCheckin(visited: {'A'}));
    expect(after.coords, trip.coords);
    expect(after.areas, trip.areas);
  });

  test('a record saved before coords existed still loads', () {
    // Records written by the pre-map build carry no coords/areas keys at all.
    final back = TripCheckin.fromJson({
      'trip_id': 'old',
      'planned': {
        '1': ['A']
      },
      'checkins': {
        '1': {
          'visited': ['A'],
          'misses': <String, String>{}
        }
      },
      'feasibility_score': 0.8,
    });
    expect(back.coords, isEmpty);
    expect(back.areas, isEmpty);
    expect(back.visitedPointsFor(1), isEmpty);
    // Everything that does not need coordinates still works.
    expect(back.completionRate, 1.0);
  });
}
