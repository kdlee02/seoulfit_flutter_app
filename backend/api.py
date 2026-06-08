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
