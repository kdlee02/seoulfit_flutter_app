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

  test('EmergencyRoom.isFull is self-sufficient: a non-positive bed count '
      'is full even when beds_state is neither "full" nor "unknown"', () {
    // Guards against app/backend version skew where a missing beds_state
    // key parses to '' instead of a recognized value.
    final skewed = EmergencyRoom.fromJson(const {
      'name': '서울아산', 'address': '서울 송파구', 'lat': 37.527, 'lng': 127.108,
      'distance_km': 9.2, 'er_phone': '02-3010-3333',
      'beds': -6, 'beds_state': '', 'updated_at': '20260821182414',
    });
    expect(skewed.bedsState, '');
    expect(skewed.beds, -6);
    expect(skewed.isFull, isTrue);
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


  test('NearbyPlace carries the photo reference, never a keyed URL', () {
    final p = NearbyPlace.fromJson(const {
      'name': 'Starbucks Korea Press Center',
      'address': '124 Sejong-daero',
      'distance_m': 82,
      'photo_ref': 'AVoNoXTlWIkqC7D005kbZHvIPiAy4lAjuGORdfYymag',
    });
    expect(p.photoRef, startsWith('AVoNoX'));

    // Places 결과 20건 중 1건은 사진이 없다. 카드가 사진 자리를 접을 수
    // 있도록 null 이 아니라 빈 문자열이어야 한다.
    final noPhoto = NearbyPlace.fromJson(const {'name': 'Cafe', 'distance_m': 10});
    expect(noPhoto.photoRef, '');
  });

  test('TourPoi trims the Korean half of the title and formats distance', () {
    // TourAPI 제목은 'English (한글)' 형식이고 앱은 영문 UI 다. 괄호 안 한글이
    // 남으면 카드가 두 줄로 밀리고 지도 마커 툴팁도 깨진다.
    final near = TourPoi.fromJson(const {
      'id': '126079', 'title': 'Seoul Forest (서울숲)', 'category': 'NA',
      'address': '273 Ttukseom-ro, Seongdong-gu, Seoul',
      'lat': 37.5443, 'lng': 127.0374, 'distance_m': 420,
      'image': 'https://tong.visitkorea.or.kr/a.jpg', 'overview': 'A city park.',
      'hours': 'Open 24 hr', 'closed': '', 'fee': '', 'parking': 'Available',
      'tel': '+82-2-460-2905', 'homepage': 'parks.seoul.go.kr',
    });
    expect(near.name, 'Seoul Forest');
    expect(near.distanceLabel, '420 m');

    // 반경 제한이 없어 km 단위 결과가 흔하다.
    final far = TourPoi.fromJson(const {
      'title': 'Hangang River', 'category': 'NA', 'distance_m': 4727,
    });
    expect(far.name, 'Hangang River');
    expect(far.distanceLabel, '4.7 km');
    expect(far.image, '');
    expect(far.lat, 0);
  });

  test('ShoppingPoi maps the Visit Seoul fields and formats distance', () {
    final p = ShoppingPoi.fromJson(const {
      'id': 'ENP6ptemj',
      'title': 'Shinsegae The Heritage',
      'category': 'DS',
      'address': '42 Namdaemun-ro, Jung-gu, Seoul',
      'lat': 37.5610, 'lng': 126.9805,
      'distance_m': 640,
      'image': 'https://api.visitseoul.net/comm/getImage?srvcId=MEDIA',
      'summary': 'A shopping and cultural complex.',
      'overview': 'Long body text.',
      'hours': 'Normal business hours 10:30-20:00',
      'tel': '1588-1234',
      'homepage': 'https://www.shinsegae.com/index.do',
      'subway': 'Subway Line 4, Hoehyeon Station, Exit 7, 187m',
    });
    expect(p.category, 'DS');
    expect(p.distanceLabel, '640 m');
    expect(p.subway, contains('Hoehyeon'));

    // 결측이 흔한 필드들. 시트가 그 줄을 숨길 수 있도록 빈 문자열이어야 한다
    // (null 이면 렌더링에서 터진다). 영업시간 285/310, 홈페이지 229/310.
    final bare = ShoppingPoi.fromJson(const {
      'title': 'Some Market', 'category': 'TM', 'distance_m': 2400,
    });
    expect(bare.hours, '');
    expect(bare.tel, '');
    expect(bare.homepage, '');
    expect(bare.subway, '');
    expect(bare.image, '');
    expect(bare.lat, 0);
    expect(bare.distanceLabel, '2.4 km');
  });
}
