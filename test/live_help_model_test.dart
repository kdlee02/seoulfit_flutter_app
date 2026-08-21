import 'package:flutter_test/flutter_test.dart';
import 'package:seoulfit_flutter/models/live_help.dart';

void main() {
  test('Embassy.matches finds by English, Korean and ISO2', () {
    const e = Embassy(
      countryEn: 'Philippines', countryKo: '필리핀', iso2: 'PH',
      missionKo: '필리핀', addressKo: '서울특별시 용산구 회나무로 80',
      postalCode: '04346', phone: '788-2100/1', phoneDial: '02-7882100',
      email: 'seoulpe@philembassy-seoul.com', website: '',
    );
    expect(e.matches('phil'), isTrue);
    expect(e.matches('필리'), isTrue);
    expect(e.matches('ph'), isTrue);
    expect(e.matches('용산'), isTrue);
    expect(e.matches('japan'), isFalse);
  });

  test('EmergencyRoom.isFull is true when beds_state is full', () {
    final full = EmergencyRoom.fromJson(const {
      'name': '서울아산', 'address': '서울 송파구', 'lat': 37.527, 'lng': 127.108,
      'distance_km': 9.2, 'er_phone': '02-3010-3333',
      'beds': -6, 'beds_state': 'full', 'updated_at': '20260821182414',
    });
    expect(full.isFull, isTrue);
    expect(full.beds, -6);

    final open = EmergencyRoom.fromJson(const {
      'name': '세브란스', 'address': '서울 서대문구', 'lat': 37.5621, 'lng': 126.9408,
      'distance_km': 1.65, 'er_phone': '02-2227-7777',
      'beds': 4, 'beds_state': 'available', 'updated_at': '20260821182414',
    });
    expect(open.isFull, isFalse);
  });

  test('NearbyPlace tolerates missing rating and open_now', () {
    final p = NearbyPlace.fromJson(const {
      'name': 'Brand New Cafe', 'address': 'Seongdong-gu',
      'lat': 37.5537, 'lng': 127.0214, 'distance_m': 155,
      'reviews': 0, 'place_id': 'x',
    });
    expect(p.rating, isNull);
    expect(p.openNow, isNull);
    expect(p.distanceM, 155);
  });
}
