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
