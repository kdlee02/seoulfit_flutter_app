import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:seoulfit_flutter/services/kakao_links.dart';

void main() {
  const from = LatLng(37.5612, 127.0378);
  const to = LatLng(37.4979, 127.0276);

  test('kakaoRoute builds the by/{mode} scheme with origin then destination', () {
    final uri = kakaoRoute(
      from: from,
      to: to,
      toName: 'Gangnam',
      mode: KakaoRouteMode.car,
    );
    expect(uri.scheme, 'https');
    expect(uri.host, 'map.kakao.com');
    // 카카오는 경로 세그먼트를 순서로 읽는다 — 출발지가 먼저, 도착지가 나중.
    // 뒤집히면 길찾기가 반대로 열리므로 순서 자체를 못박는다.
    expect(
      Uri.decodeFull(uri.path),
      '/link/by/car/My location,37.5612,127.0378/Gangnam,37.4979,127.0276',
    );
  });

  test('kakaoRoute walk mode differs from car', () {
    final walk = kakaoRoute(
        from: from, to: to, toName: 'Cafe', mode: KakaoRouteMode.walk);
    expect(Uri.decodeFull(walk.path), contains('/link/by/walk/'));
    expect(Uri.decodeFull(walk.path), isNot(contains('/link/by/car/')));
  });

  test('kakaoRoute percent-encodes Korean and comma-bearing names', () {
    // 병원명에 쉼표가 들어가면 카카오가 좌표 구분자로 오해한다.
    final uri = kakaoRoute(
      from: from,
      to: to,
      toName: '고려대학교병원, 안암',
      mode: KakaoRouteMode.car,
    );
    expect(uri.toString(), isNot(contains('고려대')));
    expect(uri.toString(), contains('%2C')); // 이름 안의 쉼표는 인코딩되어야 한다
    expect(Uri.decodeFull(uri.path), contains('고려대학교병원, 안암,37.4979'));
  });

  test('kakaoRoute falls back to a readable name when the label is empty', () {
    final uri =
        kakaoRoute(from: from, to: to, toName: '', mode: KakaoRouteMode.car);
    expect(Uri.decodeFull(uri.path), contains('/Destination,37.4979,127.0276'));
  });

  test('kakaoSearch builds the search scheme with an encoded query', () {
    final uri = kakaoSearch('서울특별시 용산구 회나무로 80');
    expect(uri.host, 'map.kakao.com');
    expect(Uri.decodeFull(uri.path), '/link/search/서울특별시 용산구 회나무로 80');
    expect(uri.toString(), isNot(contains(' ')));
  });

  test('coordinates keep full precision', () {
    final uri = kakaoRoute(
      from: const LatLng(37.553945, 127.019638),
      to: const LatLng(37.562117, 126.940828),
      toName: 'X',
      mode: KakaoRouteMode.walk,
    );
    expect(Uri.decodeFull(uri.path), contains('37.553945,127.019638'));
    expect(Uri.decodeFull(uri.path), contains('37.562117,126.940828'));
  });
}
