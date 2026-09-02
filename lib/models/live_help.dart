/// 여행 중 도우미 세 기능의 데이터 모델.
///
/// [Embassy] 는 앱에 번들된 assets/data/embassies.json 에서,
/// 나머지 둘은 백엔드 /nearby · /emergency-rooms 응답에서 온다.
library;

String _str(Object? v) => v is String ? v : '';
double _dbl(Object? v) => v is num ? v.toDouble() : 0;
int _int(Object? v) => v is num ? v.toInt() : 0;

/// 주한 공관 한 곳. 서울 소재 118건이 앱에 번들되어 있어 오프라인에서도 읽힌다.
class Embassy {
  final String countryEn;
  final String countryKo;
  final String iso2;
  final String missionKo;
  final String addressKo;
  final String postalCode;

  /// 외교부 원문 그대로. `788-2100/1` 처럼 복수 번호일 수 있어 표시 전용이다.
  final String phone;

  /// `tel:` 링크용으로 지역번호를 채워 정규화한 단일 번호. 비어 있을 수 있다.
  final String phoneDial;

  final String email;

  /// 118건 중 15건만 값이 있다. 비어 있으면 링크 버튼을 숨긴다.
  final String website;

  const Embassy({
    required this.countryEn,
    required this.countryKo,
    required this.iso2,
    required this.missionKo,
    required this.addressKo,
    required this.postalCode,
    required this.phone,
    required this.phoneDial,
    required this.email,
    required this.website,
  });

  factory Embassy.fromJson(Map<String, dynamic> j) => Embassy(
        countryEn: _str(j['country_en']),
        countryKo: _str(j['country_ko']),
        iso2: _str(j['iso2']),
        missionKo: _str(j['mission_ko']),
        addressKo: _str(j['address_ko']),
        postalCode: _str(j['postal_code']),
        phone: _str(j['phone']),
        phoneDial: _str(j['phone_dial']),
        email: _str(j['email']),
        website: _str(j['website']),
      );

  /// 영문명·한글명·ISO2·주소 어느 쪽으로 쳐도 찾히게 한다. 여행자는 자기 나라를
  /// 영어로 치지만 한국인 동행이 한글로 칠 수도 있다.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return countryEn.toLowerCase().contains(q) ||
        countryKo.contains(q) ||
        iso2.toLowerCase() == q ||
        missionKo.contains(q) ||
        addressKo.contains(q);
  }
}

/// 운영 중인 응급실 한 곳. 위치조회와 실시간 병상을 hpid 로 조인한 결과다.
class EmergencyRoom {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double distanceKm;

  /// 응급실 직통번호. 병원 대표번호가 아니라 새벽에도 받는 번호다.
  final String erPhone;

  /// 가용 병상. 정원 초과를 음수로 표현하므로 [isFull] 이 아닐 때만 렌더링한다.
  final int beds;
  final String bedsState;
  final String updatedAt;

  const EmergencyRoom({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceKm,
    required this.erPhone,
    required this.beds,
    required this.bedsState,
    required this.updatedAt,
  });

  factory EmergencyRoom.fromJson(Map<String, dynamic> j) => EmergencyRoom(
        name: _str(j['name']),
        address: _str(j['address']),
        lat: _dbl(j['lat']),
        lng: _dbl(j['lng']),
        distanceKm: _dbl(j['distance_km']),
        erPhone: _str(j['er_phone']),
        beds: _int(j['beds']),
        bedsState: _str(j['beds_state']),
        updatedAt: _str(j['updated_at']),
      );

  /// Self-sufficient on purpose: `hvec` encodes over-capacity as a negative
  /// number, so a `beds_state` that is neither `'full'` nor `'unknown'` (e.g.
  /// `''` from a missing key under app/backend version skew) must still be
  /// treated as full rather than falling through to a `'-6 beds'` render.
  bool get isFull => bedsState == 'full' || beds <= 0;
}

/// 주변 추천 장소 한 곳.
class NearbyPlace {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final int distanceM;

  /// 리뷰가 없는 업소는 구글이 평점을 아예 주지 않는다. null 이면 뱃지를 숨긴다.
  final double? rating;
  final int reviews;

  /// 결측 가능. null 이면 영업 상태 뱃지를 숨긴다.
  final bool? openNow;

  final String placeId;

  const NearbyPlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.distanceM,
    required this.rating,
    required this.reviews,
    required this.openNow,
    required this.placeId,
  });

  factory NearbyPlace.fromJson(Map<String, dynamic> j) => NearbyPlace(
        name: _str(j['name']),
        address: _str(j['address']),
        lat: _dbl(j['lat']),
        lng: _dbl(j['lng']),
        distanceM: _int(j['distance_m']),
        rating: j['rating'] is num ? (j['rating'] as num).toDouble() : null,
        reviews: _int(j['reviews']),
        openNow: j['open_now'] is bool ? j['open_now'] as bool : null,
        placeId: _str(j['place_id']),
      );
}
