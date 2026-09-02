"""Self-check for live_help (주변 추천 · 응급실).

네트워크를 타지 않는 순수 함수만 검증한다 — 거리 계산, Places 필터, E-Gen 조인.
실호출 검증은 설계 단계에서 이미 끝냈고, 여기서는 조용히 틀리면 위험한 로직만 잡는다.

Run:  backend/venv/bin/python backend/test_live_help.py
"""
import os
import sys
import xml.etree.ElementTree as ET

from fastapi import HTTPException

sys.path.insert(0, os.path.dirname(__file__))
import live_help  # noqa: E402
from live_help import filter_places, haversine_m, join_er, parse_beds  # noqa: E402


def test_haversine():
    # 위도 1도는 약 111km. 경도 0도 차이일 때 가장 깔끔하게 확인된다.
    d = haversine_m(37.0, 127.0, 38.0, 127.0)
    assert 110_000 < d < 112_000, d
    assert haversine_m(37.5, 127.0, 37.5, 127.0) == 0


def test_filter_places_drops_low_review_counts():
    results = [
        # 좌표·평점·리뷰수는 신금호 이디야 실측값이다. 155m 는 하버사인 실계산 결과.
        {"place_id": "a", "name": "Busy Cafe", "user_ratings_total": 80, "rating": 4.1,
         "vicinity": "Seongdong-gu", "geometry": {"location": {"lat": 37.553945, "lng": 127.019638}}},
        {"place_id": "b", "name": "Quiet Cafe", "user_ratings_total": 3, "rating": 5.0,
         "vicinity": "Seongdong-gu", "geometry": {"location": {"lat": 37.5537, "lng": 127.0214}}},
    ]
    out = filter_places(results, 37.553675, 127.021367)
    assert set(out) == {"a"}, out
    assert out["a"]["distance_m"] == 155, out["a"]["distance_m"]
    assert out["a"]["reviews"] == 80


def test_filter_places_treats_missing_review_key_as_zero():
    # 구글은 리뷰가 0인 업소에서 user_ratings_total 과 rating 을 아예 뺀다.
    # KeyError 로 터지지 않고, 리뷰 0개로 읽혀 필터에서 떨어져야 한다.
    results = [
        {"place_id": "new", "name": "Brand New Cafe",
         "geometry": {"location": {"lat": 37.5537, "lng": 127.0214}}},
    ]
    assert filter_places(results, 37.553675, 127.021367) == {}
    # min_reviews 를 0 으로 낮추면 통과하되 rating 은 None 으로 남는다.
    kept = filter_places(results, 37.553675, 127.021367, min_reviews=0)
    assert kept["new"]["rating"] is None
    assert kept["new"]["reviews"] == 0
    assert kept["new"]["open_now"] is None


def test_filter_places_skips_rows_without_coordinates():
    results = [{"place_id": "x", "name": "No Geo", "user_ratings_total": 999}]
    assert filter_places(results, 37.5, 127.0) == {}


_BEDS_XML = """<response><body><items>
  <item><hpid>A1100007</hpid><dutyName>세브란스</dutyName>
        <dutyTel3>02-2227-7777</dutyTel3><hvec>4</hvec><hvidate>20260821182414</hvidate></item>
  <item><hpid>A1100028</hpid><dutyName>서울아산</dutyName>
        <dutyTel3>02-3010-3333</dutyTel3><hvec>-6</hvec><hvidate>20260821182414</hvidate></item>
</items></body></response>"""

_NEAR_XML = """<response><body><items>
  <item><hpid>A1100028</hpid><dutyName>서울아산</dutyName><dutyAddr>서울 송파구</dutyAddr>
        <latitude>37.5270</latitude><longitude>127.1080</longitude>
        <distance>9.20</distance><dutyTel1>02-3010-3114</dutyTel1></item>
  <item><hpid>A1100007</hpid><dutyName>세브란스</dutyName><dutyAddr>서울 서대문구 연세로 50-1</dutyAddr>
        <latitude>37.5621</latitude><longitude>126.9408</longitude>
        <distance>1.65</distance><dutyTel1>02-2228-0114</dutyTel1></item>
  <item><hpid>A9999999</hpid><dutyName>응급실 없는 일반병원</dutyName><dutyAddr>서울 마포구</dutyAddr>
        <latitude>37.5525</latitude><longitude>126.9337</longitude>
        <distance>0.98</distance><dutyTel1>02-337-7582</dutyTel1></item>
</items></body></response>"""


def test_parse_beds_reads_er_phone_and_capacity():
    beds = parse_beds(ET.fromstring(_BEDS_XML).findall(".//item"))
    assert set(beds) == {"A1100007", "A1100028"}
    # 응급실 직통번호(dutyTel3)는 실시간 병상 응답에만 있다. 위치조회의
    # dutyTel1 은 병원 대표번호라 새벽에 받지 않는다.
    assert beds["A1100007"]["er_phone"] == "02-2227-7777"
    assert beds["A1100007"]["hvec"] == 4
    assert beds["A1100028"]["hvec"] == -6


def test_join_er_drops_hospitals_without_live_beds():
    near = ET.fromstring(_NEAR_XML).findall(".//item")
    beds = parse_beds(ET.fromstring(_BEDS_XML).findall(".//item"))
    rows = join_er(near, beds, want=5)
    # 실시간 목록에 없는 A9999999 는 응급실 미운영이라 조인에서 떨어진다.
    assert [r["name"] for r in rows] == ["세브란스", "서울아산"], rows
    assert rows[0]["distance_km"] == 1.65
    assert rows[0]["er_phone"] == "02-2227-7777"
    assert rows[0]["address"] == "서울 서대문구 연세로 50-1"


def test_join_er_marks_negative_capacity_as_full():
    # hvec 는 정원 초과를 음수로 표현한다. '-6 beds' 로 렌더링되면 안 된다.
    near = ET.fromstring(_NEAR_XML).findall(".//item")
    beds = parse_beds(ET.fromstring(_BEDS_XML).findall(".//item"))
    rows = {r["name"]: r for r in join_er(near, beds, want=5)}
    assert rows["세브란스"]["beds_state"] == "available"
    assert rows["서울아산"]["beds_state"] == "full"


def test_join_er_respects_want():
    near = ET.fromstring(_NEAR_XML).findall(".//item")
    beds = parse_beds(ET.fromstring(_BEDS_XML).findall(".//item"))
    assert len(join_er(near, beds, want=1)) == 1


# data.go.kr 의 에러 봉투(quota 초과, Encoding 키 오사용 등)에는 resultCode
# 자체가 없다. 이걸 성공으로 오인하면 _egen 이 빈 리스트를 돌려주고, 그게 그대로
# HTTP 200 'hospitals: []' 로 나가 응급 화면이 조용히 빈 화면이 된다.
_ERROR_ENVELOPE_XML = """<OpenAPI_ServiceResponse>
    <cmmMsgHeader>
        <errMsg>SERVICE ERROR</errMsg>
        <returnAuthMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg>
        <returnReasonCode>30</returnReasonCode>
    </cmmMsgHeader>
</OpenAPI_ServiceResponse>"""

# resultCode == "00" 인데 item 이 0개인 건 진짜 빈 결과다 (예: STAGE1 조회에서
# 해당 지역에 아무 것도 없을 때) — 에러로 취급하면 안 된다.
_EMPTY_OK_XML = """<response><header><resultCode>00</resultCode>
<resultMsg>NORMAL SERVICE.</resultMsg></header><body><items></items></body></response>"""


def _patch_egen_http(xml_text: str):
    """네트워크를 타지 않고 _egen 의 파싱·에러 처리만 검증하기 위해 httpx.get 을
    갈아끼운다. (원래 get, 원래 EGEN_API_KEY) 를 돌려주니 finally 에서 되돌린다."""

    class _FakeResponse:
        text = xml_text

    original_get = live_help.httpx.get
    original_key = os.environ.get("EGEN_API_KEY")
    os.environ["EGEN_API_KEY"] = "test-key"
    live_help.httpx.get = lambda *a, **k: _FakeResponse()
    return original_get, original_key


def _unpatch_egen_http(original_get, original_key):
    live_help.httpx.get = original_get
    if original_key is None:
        os.environ.pop("EGEN_API_KEY", None)
    else:
        os.environ["EGEN_API_KEY"] = original_key


def test_egen_raises_on_error_envelope_without_resultcode():
    original_get, original_key = _patch_egen_http(_ERROR_ENVELOPE_XML)
    try:
        try:
            live_help._egen("getEgytLcinfoInqire", WGS84_LON=127.0, WGS84_LAT=37.5)
            assert False, "expected HTTPException"
        except HTTPException as e:
            assert e.status_code == 502, e.status_code
            assert "SERVICE_KEY_IS_NOT_REGISTERED_ERROR" in e.detail, e.detail
    finally:
        _unpatch_egen_http(original_get, original_key)


def test_egen_allows_legitimate_empty_result():
    original_get, original_key = _patch_egen_http(_EMPTY_OK_XML)
    try:
        assert (
            live_help._egen("getEmrrmRltmUsefulSckbdInfoInqire", STAGE1="서울특별시")
            == []
        )
    finally:
        _unpatch_egen_http(original_get, original_key)


if __name__ == "__main__":
    test_haversine()
    test_filter_places_drops_low_review_counts()
    test_filter_places_treats_missing_review_key_as_zero()
    test_filter_places_skips_rows_without_coordinates()
    test_parse_beds_reads_er_phone_and_capacity()
    test_join_er_drops_hospitals_without_live_beds()
    test_join_er_marks_negative_capacity_as_full()
    test_join_er_respects_want()
    test_egen_raises_on_error_envelope_without_resultcode()
    test_egen_allows_legitimate_empty_result()
    print("live_help self-check ok")
