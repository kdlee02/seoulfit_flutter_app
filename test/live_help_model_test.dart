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

  test('Embassy.fromJson maps every field from a real embassies.json record',
      () {
    final e = Embassy.fromJson(const {
      'country_en': 'Philippines', 'country_ko': '필리핀', 'iso2': 'PH',
      'kind': 'embassy', 'mission_ko': '필리핀', 'city': '서울',
      'postal_code': '04346', 'address_ko': '서울특별시 용산구 회나무로 80',
      'phone': '788-2100/1', 'phone_dial': '02-7882100',
      'email': 'seoulpe@philembassy-seoul.com', 'website': '',
    });
    expect(e.countryEn, 'Philippines');
    expect(e.countryKo, '필리핀');
    expect(e.iso2, 'PH');
    expect(e.missionKo, '필리핀');
    expect(e.addressKo, '서울특별시 용산구 회나무로 80');
    expect(e.postalCode, '04346');
    expect(e.phone, '788-2100/1');
    expect(e.phoneDial, '02-7882100');
    expect(e.email, 'seoulpe@philembassy-seoul.com');
    expect(e.website, '');
    // The factory-parsed object must behave identically to one built
    // directly through the constructor.
    expect(e.matches('phil'), isTrue);
    expect(e.matches('필리'), isTrue);
    expect(e.matches('ph'), isTrue);
    expect(e.matches('용산'), isTrue);
    expect(e.matches('japan'), isFalse);
  });

  test('EmergencyRoom.fromJson maps every field; isFull tracks beds_state',
      () {
    final full = EmergencyRoom.fromJson(const {
      'name': '서울아산', 'address': '서울 송파구', 'lat': 37.527, 'lng': 127.108,
      'distance_km': 9.2, 'er_phone': '02-3010-3333',
      'beds': -6, 'beds_state': 'full', 'updated_at': '20260821182414',
    });
    expect(full.name, '서울아산');
    expect(full.address, '서울 송파구');
    expect(full.lat, 37.527);
    expect(full.lng, 127.108);
    expect(full.distanceKm, 9.2);
    expect(full.erPhone, '02-3010-3333');
    expect(full.beds, -6);
    expect(full.bedsState, 'full');
    expect(full.updatedAt, '20260821182414');
    expect(full.isFull, isTrue);

    final open = EmergencyRoom.fromJson(const {
      'name': '세브란스', 'address': '서울 서대문구', 'lat': 37.5621, 'lng': 126.9408,
      'distance_km': 1.65, 'er_phone': '02-2227-7777',
      'beds': 4, 'beds_state': 'available', 'updated_at': '20260821182414',
    });
    expect(open.name, '세브란스');
    expect(open.address, '서울 서대문구');
    expect(open.lat, 37.5621);
    expect(open.lng, 126.9408);
    expect(open.distanceKm, 1.65);
    expect(open.erPhone, '02-2227-7777');
    expect(open.beds, 4);
    expect(open.bedsState, 'available');
    expect(open.updatedAt, '20260821182414');
    expect(open.isFull, isFalse);
  });

  test('NearbyPlace tolerates missing rating and open_now', () {
    final p = NearbyPlace.fromJson(const {
      'name': 'Brand New Cafe', 'address': 'Seongdong-gu',
      'lat': 37.5537, 'lng': 127.0214, 'distance_m': 155,
      'reviews': 0, 'place_id': 'x',
    });
    expect(p.name, 'Brand New Cafe');
    expect(p.address, 'Seongdong-gu');
    expect(p.lat, 37.5537);
    expect(p.lng, 127.0214);
    expect(p.distanceM, 155);
    expect(p.rating, isNull);
    expect(p.reviews, 0);
    expect(p.openNow, isNull);
    expect(p.placeId, 'x');
  });

  test('NearbyPlace maps every field when rating and open_now are present',
      () {
    final p = NearbyPlace.fromJson(const {
      'name': 'Onion Seongsu', 'address': 'Seongdong-gu, Achasan-ro 9-gil',
      'lat': 37.5445, 'lng': 127.0557, 'distance_m': 320,
      'rating': 4.3, 'reviews': 1204, 'open_now': true,
      'place_id': 'ChIJ_onion_seongsu',
    });
    expect(p.name, 'Onion Seongsu');
    expect(p.address, 'Seongdong-gu, Achasan-ro 9-gil');
    expect(p.lat, 37.5445);
    expect(p.lng, 127.0557);
    expect(p.distanceM, 320);
    expect(p.rating, 4.3);
    expect(p.reviews, 1204);
    expect(p.openNow, isTrue);
    expect(p.placeId, 'ChIJ_onion_seongsu');
  });
}
