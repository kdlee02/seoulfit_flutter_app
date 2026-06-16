from __future__ import annotations

import re
import json
from types import SimpleNamespace
from langchain_core.messages import HumanMessage, AIMessage
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.memory import MemorySaver
from state import TravelState
from planner import make_retrieve_node, plan_node
from critic_repair import make_critic_repair_node

# ---------------------------------------------------------------------------
# Module-level API key (set by build_graph)
# ---------------------------------------------------------------------------

_api_key: str = ""


# ---------------------------------------------------------------------------
# Direct Gemini helpers (replaces DSPy — avoids response_schema incompatibility)
# ---------------------------------------------------------------------------

def _gemini_json(prompt: str) -> dict:
    from google import genai as _genai
    client = _genai.Client(api_key=_api_key)
    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt,
        config={"response_mime_type": "application/json"},
    )
    try:
        return json.loads(response.text or "{}")
    except json.JSONDecodeError:
        return {}


def _extract_trip_info(text: str) -> SimpleNamespace:
    prompt = (
        f'Extract Seoul trip details from this user message: "{text}"\n\n'
        "Return JSON with exactly these fields:\n"
        '- travel_dates: dates or duration like "June 15-17", "3 days". "MISSING" if not mentioned.\n'
        '- category: interests normalized to K-POP/Cafe/Beauty/Food/Shopping/History/Activity. '
        'Comma-separated if multiple. "MISSING" if not mentioned.\n'
        '- restrictions: dietary or physical restrictions. "none" if user says no restrictions. '
        '"MISSING" if not mentioned.\n'
        '- companion: solo/couple/friends/family. "MISSING" if not mentioned.\n'
        '- pace: "packed" for busy or "relaxed" for slow pace. "MISSING" if not mentioned.'
    )
    data = _gemini_json(prompt)
    return SimpleNamespace(
        travel_dates=str(data.get("travel_dates", "MISSING")),
        category=str(data.get("category", "MISSING")),
        restrictions=str(data.get("restrictions", "MISSING")),
        companion=str(data.get("companion", "MISSING")),
        pace=str(data.get("pace", "MISSING")),
    )


def _extract_region(text: str) -> SimpleNamespace:
    prompt = (
        f'Extract Seoul area preferences from this user message: "{text}"\n\n'
        "Return JSON with exactly this field:\n"
        "- region: one or more areas from Hongdae/Seongsu/Gangnam/Itaewon/Myeongdong/"
        "Jongno/Bukchon/Mapo/Insadong/Dongdaemun/Sinchon/Apgujeong. "
        'Comma-separated if multiple. "NONE" if user asks for recommendation or doesn\'t specify.'
    )
    data = _gemini_json(prompt)
    return SimpleNamespace(region=str(data.get("region", "NONE")))


def _classify_intent(user_message: str) -> SimpleNamespace:
    prompt = (
        f'Classify what the user wants to do with their Seoul trip plan.\n'
        f'Message: "{user_message}"\n\n'
        "Return JSON with exactly this field:\n"
        '- intent: "CONFIRM" if user confirms/agrees/wants to proceed. '
        "Otherwise return exactly one of: travel_dates, category, restrictions, companion, pace, region "
        "(the field they want to change)."
    )
    data = _gemini_json(prompt)
    return SimpleNamespace(intent=str(data.get("intent", "CONFIRM")))


# ---------------------------------------------------------------------------
# Field metadata
# ---------------------------------------------------------------------------

FIELD_LABELS = {
    "travel_dates": "Travel Dates",
    "category":     "Interests",
    "restrictions": "Restrictions",
    "companion":    "Traveling With",
    "pace":         "Trip Style",
    "region":       "Seoul Area",
}

ALL_FIELDS = list(FIELD_LABELS.keys())

FIELD_QUESTIONS = {
    "travel_dates": "What are your travel dates or how many days?",
    "category":     "What are your main interests? (beauty, history, food, shopping, activity)",
    "restrictions": "Any dietary or physical restrictions? (or 'none')",
    "companion":    "Who are you traveling with? (solo/couple/friends/family)",
    "pace":         "Packed schedule or relaxed pace?",
    "region":       "Which area of Seoul? (e.g. Hongdae, Gangnam, Itaewon) -- or I can recommend!",
}

_CATEGORY_REGIONS: dict[str, str] = {
    "beauty":   "Hongdae or Gangnam",
    "history":  "Jongno or Bukchon",
    "food":     "Gwangjang Market or Myeongdong",
    "shopping": "Myeongdong or Gangnam",
    "activity": "Hongdae or Mapo",
}


def _recommend_region(category: str | None) -> str:
    if not category:
        return "Hongdae or Myeongdong"
    cat = category.lower()
    for key, region in _CATEGORY_REGIONS.items():
        if key in cat:
            return region
    return "Hongdae or Myeongdong"


def _parse_regions(raw: str) -> str:
    parts = re.split(r'\s+and\s+|\s*&\s*|\s*,\s*', raw.strip(), flags=re.IGNORECASE)
    cleaned = [p.strip().title() for p in parts if p.strip()]
    return ", ".join(cleaned) if cleaned else raw.strip()


def build_summary(state: TravelState) -> str:
    lines = "\n".join(
        f"{FIELD_LABELS[f]}: {state.get(f) or '--'}" for f in ALL_FIELDS
    )
    return (
        f"Here's your Seoul trip summary:\n\n{lines}\n\n"
        "Ready to generate your itinerary? Type 'confirm'.\n"
        "Want to change something? Just tell me (e.g. 'change region', 'edit dates')."
    )


# ---------------------------------------------------------------------------
# Graph nodes
# ---------------------------------------------------------------------------

def collect_node(state: TravelState) -> TravelState:
    step = state.get("current_step", "start")
    messages = state.get("messages", [])

    if step == "start":
        greeting = (
            "Hi! I'm SeoulFit Buddy \U0001f425\n"
            "To plan your perfect Seoul trip, tell me:\n"
            "\U0001f5d3 Travel dates (or I'll pick for you!)\n"
            "\U0001f3af Interests (beauty, history, food, shopping, activity...)\n"
            "⚠️ Any restrictions? (dietary, physical, etc.)\n"
            "\U0001f465 Who are you traveling with? (solo/couple/friends/family)\n"
            "\U0001f4cb Trip style: packed schedule or relaxed pace?"
        )
        return {**state, "current_step": "collecting_basics",
                "messages": [AIMessage(content=greeting)]}

    last_human = next((m.content for m in reversed(messages) if isinstance(m, HumanMessage)), None)
    if not last_human:
        return state

    if last_human.strip().lower() in ("confirm", "yes", "ok", "go", "generate"):
        return {**state, "current_step": "confirm"}

    if step == "collecting_basics":
        try:
            result = _extract_trip_info(last_human)
            updates: dict = {}
            for field in ["travel_dates", "category", "restrictions", "companion", "pace"]:
                value = getattr(result, field, "").strip()
                if value and value.upper() != "MISSING":
                    updates[field] = value
        except Exception as e:
            return {**state, "messages": [AIMessage(
                content=f"Sorry, I had trouble understanding that. Could you try again? ({e})"
            )]}

        region_ask = (
            "Do you have a specific area in Seoul in mind?\n"
            "(e.g. Hongdae, Seongsu, Gangnam, Itaewon)\n"
            "Or I can recommend based on your interests! \U0001f60a"
        )
        return {**state, **updates, "current_step": "collecting_region",
                "messages": [AIMessage(content=region_ask)]}

    if step == "collecting_region":
        try:
            result = _extract_region(last_human)
            raw = result.region.strip()
        except Exception:
            raw = "NONE"

        if not raw or raw.upper() == "NONE":
            recommended = _recommend_region(state.get("category"))
            region_val = f"{recommended} (recommended)"
        else:
            region_val = _parse_regions(raw)

        return {**state, "region": region_val, "current_step": "confirm"}

    return state


def confirm_node(state: TravelState) -> TravelState:
    return {**state, "current_step": "confirm",
            "messages": [AIMessage(content=build_summary(state))]}


def handle_confirm_node(state: TravelState) -> TravelState:
    messages = state.get("messages", [])
    last_human = next((m.content for m in reversed(messages) if isinstance(m, HumanMessage)), None)
    if not last_human:
        return state

    try:
        result = _classify_intent(last_human)
        intent = result.intent.strip().upper()
    except Exception as e:
        return {**state, "messages": [AIMessage(
            content=f"Error occurred. Please try again. ({e})"
        )]}

    if intent == "CONFIRM":
        lines = "\n".join(f"{FIELD_LABELS[f]}: {state.get(f) or '--'}" for f in ALL_FIELDS)
        return {
            **state,
            "confirmed": True,
            "current_step": "retrieving",
            "messages": [AIMessage(
                content=f"Let's build your Seoul itinerary!\n\n{lines}\n\n"
                        "Searching the Seoul course catalogue..."
            )]
        }

    field = intent.lower()
    if field in ALL_FIELDS:
        next_step = "collecting_region" if field == "region" else "collecting_basics"
        return {
            **state,
            field: None,
            "current_step": next_step,
            "messages": [AIMessage(content=f"Got it! {FIELD_QUESTIONS[field]}")]
        }

    return {**state, "messages": [AIMessage(
        content="Type 'confirm' to proceed, or tell me what you'd like to change."
    )]}


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

def route_entry(state: TravelState) -> str:
    if state.get("itinerary"):
        return END

    step = state.get("current_step", "start")

    if step == "retrieving":
        return "retrieve"
    if step == "planning":
        return "plan"
    if step == "critic":
        return "critic_repair"

    if step == "confirm":
        messages = state.get("messages", [])
        if messages and isinstance(messages[-1], HumanMessage):
            return "handle_confirm"
        return "confirm"

    return "collect"


def _after_collect(state: TravelState) -> str:
    if state.get("current_step") != "confirm":
        return END
    messages = state.get("messages", [])
    last_human = next((m.content for m in reversed(messages) if isinstance(m, HumanMessage)), None)
    if last_human and last_human.strip().lower() in ("confirm", "yes", "ok", "go", "generate"):
        return "handle_confirm"
    return "confirm"


def _after_handle_confirm(state: TravelState) -> str:
    if state.get("current_step") == "retrieving":
        return "retrieve"
    return END


def _after_retrieve(state: TravelState) -> str:
    return "plan" if state.get("current_step") == "planning" else END


def _after_plan(state: TravelState) -> str:
    return "critic_repair" if state.get("current_step") == "critic" else END


# ---------------------------------------------------------------------------
# Graph builder
# ---------------------------------------------------------------------------

def build_graph(api_key: str):
    global _api_key
    _api_key = api_key

    builder = StateGraph(TravelState)

    builder.add_node("collect", collect_node)
    builder.add_node("confirm", confirm_node)
    builder.add_node("handle_confirm", handle_confirm_node)
    builder.add_node("retrieve", make_retrieve_node(api_key))
    builder.add_node("plan", plan_node)
    builder.add_node("critic_repair", make_critic_repair_node())

    builder.set_conditional_entry_point(route_entry, {
        "collect":        "collect",
        "confirm":        "confirm",
        "handle_confirm": "handle_confirm",
        "retrieve":       "retrieve",
        "plan":           "plan",
        "critic_repair":  "critic_repair",
        END:              END,
    })

    builder.add_conditional_edges(
        "collect",
        _after_collect,
        {"confirm": "confirm", "handle_confirm": "handle_confirm", END: END},
    )

    builder.add_edge("confirm", END)

    builder.add_conditional_edges(
        "handle_confirm",
        _after_handle_confirm,
        {"retrieve": "retrieve", END: END},
    )

    builder.add_conditional_edges(
        "retrieve",
        _after_retrieve,
        {"plan": "plan", END: END},
    )

    builder.add_conditional_edges(
        "plan",
        _after_plan,
        {"critic_repair": "critic_repair", END: END},
    )

    builder.add_edge("critic_repair", END)

    memory = MemorySaver()
    return builder.compile(checkpointer=memory)
