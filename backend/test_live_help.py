"""Self-check for live_help (주변 추천 · 응급실).

네트워크를 타지 않는 순수 함수만 검증한다 — 거리 계산, Places 필터, E-Gen 조인.
실호출 검증은 설계 단계에서 이미 끝냈고, 여기서는 조용히 틀리면 위험한 로직만 잡는다.

Run:  backend/venv/bin/python backend/test_live_help.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from live_help import filter_places, haversine_m  # noqa: E402


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


if __name__ == "__main__":
    test_haversine()
    test_filter_places_drops_low_review_counts()
    test_filter_places_treats_missing_review_key_as_zero()
    test_filter_places_skips_rows_without_coordinates()
    print("live_help self-check ok")
