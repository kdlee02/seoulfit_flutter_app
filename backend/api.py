"""
api.py — Seoul Travel Buddy FastAPI backend.

Local dev:
    uvicorn api:app --reload --port 8000

Production (Render binds $PORT):
    python -m uvicorn api:app --host 0.0.0.0 --port $PORT
"""

import os
import sys

# All backend modules (graph.py, state.py, planner.py, …) now live flat in
# this same directory, so add it to sys.path to stay import-safe regardless of
# where uvicorn is launched from.
_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _here)

# ── Compatibility patch ────────────────────────────────────────────────────────
# langchain_core ≤0.3.x tries to set `langchain.debug` as a module attribute,
# but langchain 0.3+ removed it. Patch it back in before any other import.
import langchain as _lc
if not hasattr(_lc, "debug"):
    _lc.debug = False
if not hasattr(_lc, "verbose"):
    _lc.verbose = False
# ──────────────────────────────────────────────────────────────────────────────

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from langchain_core.messages import HumanMessage, AIMessage

# In dev we load .env from disk; in prod (Render) env vars are injected
# directly into the process so load_dotenv is a no-op.
load_dotenv(os.path.join(_here, ".env"))

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
if not GEMINI_API_KEY:
    raise RuntimeError(
        "GEMINI_API_KEY is not set. "
        "In dev, add it to flutter/backend/.env. "
        "In prod, set it as an environment variable on the host."
    )

# langchain-google-genai (used by rag.py for embeddings) checks
# GOOGLE_API_KEY first and only falls back to GEMINI_API_KEY in newer
# versions. To stay robust across versions, mirror GEMINI_API_KEY into
# GOOGLE_API_KEY when the latter isn't explicitly set.
if not os.getenv("GOOGLE_API_KEY"):
    os.environ["GOOGLE_API_KEY"] = GEMINI_API_KEY

from graph import build_graph
from lens import router as lens_router

_graph = build_graph(GEMINI_API_KEY)

app = FastAPI(title="Seoul Travel Buddy API")

# CORS — in dev (FRONTEND_ORIGIN unset) we allow any origin so `flutter
# run -d chrome` and similar tools work without ceremony. In prod, set
# FRONTEND_ORIGIN to a comma-separated list of the deployed frontend URLs.
#
# Render's `fromService.property: host` returns a bare hostname like
# "seoul-buddy-web.onrender.com" with no scheme. Browsers send the full
# `https://...` form in the Origin header, so we have to normalize each
# entry to a full origin or CORS will silently reject every request.
def _normalize_origin(o: str) -> str:
    o = o.strip()
    if not o or o == "*":
        return o
    if "://" not in o:
        # Render production hosts are HTTPS-only; assume https for bare hosts.
        o = f"https://{o}"
    # Trim any accidental trailing slash so the comparison is exact.
    return o.rstrip("/")


_frontend_origin = os.getenv("FRONTEND_ORIGIN", "").strip()
_cors_origins = (
    [_normalize_origin(o) for o in _frontend_origin.split(",") if o.strip()]
    if _frontend_origin
    else ["*"]
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Lens (camera → landmark) endpoints
app.include_router(lens_router)


# ---------------------------------------------------------------------------
# Health probe — Render / k8s style "is the process alive?" endpoint.
# ---------------------------------------------------------------------------
@app.get("/healthz")
def healthz():
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class ChatRequest(BaseModel):
    thread_id: str = "travel-session-1"
    message: str | None = None  # None on first call → triggers greeting


class StateResponse(BaseModel):
    duration: str | None
    location: str | None
    budget: str | None
    dietary: str | None
    purpose: str | None
    current_step: str
    confirmed: bool
    reply: str | None           # latest AI message text
    itinerary: dict | None = None  # full day-by-day plan once available


class TransitStop(BaseModel):
    name: str | None = None
    lat: float | None = None
    lng: float | None = None


class TransitLegsRequest(BaseModel):
    stops: list[TransitStop]    # ordered list of selected stops


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _config(thread_id: str) -> dict:
    return {"configurable": {"thread_id": thread_id}}


def _get_state(thread_id: str) -> dict:
    snapshot = _graph.get_state(_config(thread_id))
    if snapshot and snapshot.values:
        return snapshot.values
    return {
        "duration": None, "location": None, "budget": None,
        "dietary": None, "purpose": None,
        "current_step": "start", "confirmed": False, "messages": [],
    }


def _latest_ai_message(state: dict) -> str | None:
    for msg in reversed(state.get("messages", [])):
        if isinstance(msg, AIMessage):
            return msg.content
    return None


def _run(thread_id: str, user_input: str | None) -> dict:
    state = _get_state(thread_id)
    messages = list(state.get("messages", []))
    if user_input:
        messages = messages + [HumanMessage(content=user_input)]
    updated = {**state, "messages": messages}
    return _graph.invoke(updated, _config(thread_id))


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.post("/chat", response_model=StateResponse)
def chat(req: ChatRequest):
    """Send a message (or None for the initial greeting) and get back
    the updated state plus the latest AI reply."""
    try:
        new_state = _run(req.thread_id, req.message)
    except Exception as e:
        import traceback
        traceback.print_exc()          # prints full stack to uvicorn terminal
        raise HTTPException(status_code=500, detail=str(e))

    return StateResponse(
        duration=new_state.get("duration"),
        location=new_state.get("location"),
        budget=new_state.get("budget"),
        dietary=new_state.get("dietary"),
        purpose=new_state.get("purpose"),
        current_step=new_state.get("current_step", "start"),
        confirmed=new_state.get("confirmed", False),
        reply=_latest_ai_message(new_state),
        itinerary=new_state.get("itinerary"),
    )


@app.get("/state", response_model=StateResponse)
def get_state(thread_id: str = "travel-session-1"):
    """Return current state without invoking the graph."""
    state = _get_state(thread_id)
    return StateResponse(
        duration=state.get("duration"),
        location=state.get("location"),
        budget=state.get("budget"),
        dietary=state.get("dietary"),
        purpose=state.get("purpose"),
        current_step=state.get("current_step", "start"),
        confirmed=state.get("confirmed", False),
        reply=_latest_ai_message(state),
        itinerary=state.get("itinerary"),
    )


@app.post("/reset")
def reset(thread_id: str = "travel-session-1"):
    """Clear the conversation (reinitialises the graph)."""
    global _graph
    _graph = build_graph(GEMINI_API_KEY)
    return {"status": "reset"}


class PoiSummaryRequest(BaseModel):
    name: str
    type: str = ""


@app.post("/poi-summary")
def poi_summary(req: PoiSummaryRequest):
    """Return a 1-2 sentence Gemini summary for a Seoul POI."""
    try:
        from google import genai as _genai
        client = _genai.Client(api_key=GEMINI_API_KEY)
        prompt = (
            f"In 1-2 sentences, describe {req.name} in Seoul, South Korea "
            "and what visitors can experience there. Be specific and engaging. "
            "Do not include any markdown formatting."
        )
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
        )
        return {"summary": (response.text or "").strip()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/poi-image")
def poi_image(req: PoiSummaryRequest):
    """Return the best-matching thumbnail for a Seoul POI.

    Steps:
    1. Ask Gemini to write a Seoul-specific image search query from the POI name/type.
    2. Fetch the top 10 results from SerpApi.
    3. Ask Gemini to pick the thumbnail that actually shows the place, or 'none'.
    """
    serpapi_key = os.getenv("SERPAPI_KEY", "")
    if not serpapi_key:
        raise HTTPException(status_code=503, detail="SERPAPI_KEY not configured")
    try:
        from google import genai as _genai
        import serpapi

        gemini = _genai.Client(api_key=GEMINI_API_KEY)

        # Step 1 — generate a disambiguation-safe search query.
        type_hint = f" ({req.type})" if req.type else ""
        query_prompt = (
            f"Generate a concise Google Images search query (max 8 words) to find a "
            f"photo of '{req.name}'{type_hint} in Seoul, South Korea. "
            "Make it specific enough to avoid confusion with similarly named places "
            "or people elsewhere in the world. Return only the search query string, "
            "nothing else."
        )
        query_resp = gemini.models.generate_content(
            model="gemini-2.5-flash",
            contents=query_prompt,
        )
        search_query = (query_resp.text or req.name).strip().strip('"')

        # Step 2 — fetch images from SerpApi (no aspect-ratio/size filter so we
        # don't exclude valid shots; SerpApi's thumbnail field is already a
        # pre-scaled CDN image for every result).
        serp_client = serpapi.Client(api_key=serpapi_key)
        results = serp_client.search({
            "engine": "google_images_light",
            "google_domain": "google.co.kr",
            "q": search_query,
            "hl": "en",
            "gl": "kr",
            "location": "Seoul, Seoul, South Korea",
            "safe": "active",
            "image_type": "photo",
        })
        images = (results.get("images_results") or [])[:5]
        if not images:
            return {"image_url": ""}

        # Step 3 — let Gemini pick the best match (or reject all).
        candidates = "\n".join(
            f"{i+1}. title={img.get('title','')!r} url={img.get('thumbnail','')}"
            for i, img in enumerate(images)
        )
        pick_prompt = (
            f"I need a photo of '{req.name}'{type_hint} in Seoul, South Korea.\n"
            f"Here are 5 image search results:\n{candidates}\n\n"
            "Return ONLY the thumbnail URL of the image that best shows the actual "
            "Seoul location. If none of them clearly show the correct place, "
            "return exactly: none"
        )
        pick_resp = gemini.models.generate_content(
            model="gemini-2.5-flash",
            contents=pick_prompt,
        )
        chosen = (pick_resp.text or "").strip()
        if not chosen or chosen.lower() == "none":
            return {"image_url": ""}
        return {"image_url": chosen}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/poi-detail")
def poi_detail(req: PoiSummaryRequest):
    """Return structured visitor bullet points for a Seoul POI (stop selection screen).

    Tavily fetches live web data (hours, fees, tips); Gemini formats it into
    labeled bullet lines so the info is distinct from the Gemini prose summary.
    """
    tavily_key = os.getenv("TAVILY_API_KEY", "")
    if not tavily_key:
        raise HTTPException(status_code=503, detail="TAVILY_API_KEY not configured")
    try:
        from tavily import TavilyClient
        from google import genai as _genai

        # Step 1 — Tavily web search for practical visitor info.
        tavily = TavilyClient(api_key=tavily_key)
        response = tavily.search(
            query=(
                f"{req.name} Seoul opening hours admission fee visitor tips highlights"
            ),
            search_depth="basic",
            max_results=3,
            include_answer=True,
        )
        raw = response.get("answer") or ""
        if not raw:
            return {"detail": ""}

        # Step 2 — Gemini reformats the raw web answer into 3-4 labeled bullets.
        type_hint = f" ({req.type})" if req.type else ""
        format_prompt = (
            f"Here is live web information about '{req.name}'{type_hint} in Seoul:\n\n"
            f"{raw}\n\n"
            "Reformat this into exactly 3-4 short bullet lines using these labels "
            "(skip a label if the info isn't available):\n"
            "• Hours: ...\n"
            "• Entry: ...\n"
            "• Highlight: ...\n"
            "• Tip: ...\n\n"
            "Keep each line to one sentence or less. Return only the bullet lines, "
            "no intro or extra text."
        )
        gemini = _genai.Client(api_key=GEMINI_API_KEY)
        fmt_resp = gemini.models.generate_content(
            model="gemini-2.5-flash",
            contents=format_prompt,
        )
        return {"detail": (fmt_resp.text or "").strip()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/transit-legs")
def transit_legs(req: TransitLegsRequest):
    """Recompute distance / walk / car / Kakao links / ODsay public-transit
    options for an arbitrary ordered list of stops.

    Used when the user re-selects a subset of stops on the route screen, so the
    transit between the *new* consecutive pairs is real ODsay data rather than a
    straight-line estimate. Returns one leg per consecutive pair (N-1 legs)."""
    from planner import compute_transit_legs

    pois = [
        {"name": s.name, "lat": s.lat, "lng": s.lng}
        for s in req.stops
    ]
    try:
        legs = compute_transit_legs(pois)
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    return {"transit_legs": legs}
