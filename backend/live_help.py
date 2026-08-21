"""live_help.py — 여행 중 도우미 라우터 (주변 추천 · 응급실).

api.py 에 include_router 로 마운트한다.
여권분실은 앱에 번들한 assets/data/embassies.json 을 쓰므로 여기 없다 —
여권을 잃은 사람은 데이터로밍이 끊겨 있을 수 있다.
"""
from __future__ import annotations

import math
import os

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(tags=["live-help"])

_PLACES_URL = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"

# 반경 상한 1000m. 상한이 없으면 주거지역에서 5개를 채우려고 2km 밖까지 끌어와
# 도보 20분 거리를 '내 위치 기반 추천'으로 내놓는다. 못 채우면 적게 준다.
_RADII = (500, 1000)
_MIN_REVIEWS = 50


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """두 좌표 사이 대권거리(미터)."""
    r = 6371000.0
    rad = math.radians
    a = (
        math.sin(rad(lat2 - lat1) / 2) ** 2
        + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(rad(lng2 - lng1) / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def filter_places(
    results: list[dict], lat: float, lng: float, min_reviews: int = _MIN_REVIEWS
) -> dict[str, dict]:
    """Places 결과를 리뷰 수로 거르고 거리를 붙여 place_id 로 키잉해 돌려준다.

    구글은 리뷰가 하나도 없는 업소에서 user_ratings_total 과 rating 을 아예 빼고
    내려준다. 키 없음 = 리뷰 0개 이므로 0 으로 읽는 것이 크래시 회피가 아니라
    의미상 정확하고, 그러면 필터가 알아서 걸러낸다.
    """
    out: dict[str, dict] = {}
    for p in results:
        if p.get("user_ratings_total", 0) < min_reviews:
            continue
        loc = (p.get("geometry") or {}).get("location") or {}
        if "lat" not in loc or "lng" not in loc:
            continue
        pid = p.get("place_id") or p.get("name", "")
        out[pid] = {
            "name": p.get("name", ""),
            "address": p.get("vicinity", ""),
            "lat": loc["lat"],
            "lng": loc["lng"],
            "distance_m": round(haversine_m(lat, lng, loc["lat"], loc["lng"])),
            "rating": p.get("rating"),
            "reviews": p.get("user_ratings_total", 0),
            "open_now": (p.get("opening_hours") or {}).get("open_now"),
            "place_id": p.get("place_id", ""),
        }
    return out


class NearbyRequest(BaseModel):
    lat: float
    lng: float
    type: str = "cafe"
    want: int = 5


@router.post("/nearby")
def nearby(req: NearbyRequest):
    """현재 위치 도보권의 카페/음식점을 거리순으로 돌려준다."""
    key = os.getenv("GOOGLE_PLACES_API_KEY", "")
    if not key:
        raise HTTPException(status_code=500, detail="GOOGLE_PLACES_API_KEY is not set")

    found: dict[str, dict] = {}
    radius_used = _RADII[0]
    for radius in _RADII:
        radius_used = radius
        # rankby=distance 는 radius 와 함께 못 쓴다. 반경 확장 전략을 쓰므로
        # radius 를 쓰고 거리 정렬은 하버사인으로 직접 한다.
        try:
            data = httpx.get(
                _PLACES_URL,
                params={
                    "location": f"{req.lat},{req.lng}",
                    "radius": radius,
                    "type": req.type,
                    "key": key,
                    "language": "en",
                },
                timeout=15,
            ).json()
        except httpx.HTTPError as e:
            raise HTTPException(status_code=502, detail=f"Places request failed: {e}")

        status = data.get("status")
        if status not in ("OK", "ZERO_RESULTS"):
            raise HTTPException(
                status_code=502,
                detail=f"Places error {status}: {data.get('error_message', '')}",
            )
        found.update(filter_places(data.get("results", []), req.lat, req.lng))
        if len(found) >= req.want:
            break

    places = sorted(found.values(), key=lambda x: x["distance_m"])[: req.want]
    return {"radius_used": radius_used, "places": places}
