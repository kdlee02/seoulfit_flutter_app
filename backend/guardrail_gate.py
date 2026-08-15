"""Input gatekeeper — NeMo `self check input` rail in front of /chat.

Loads the LLMRails config in backend/guardrails/ once (module singleton) and
exposes ``is_blocked(text)``. Only the INPUT rail runs (rail_types=["input"]),
so no reply is generated here — LangGraph still produces every response.

The rail costs one extra Gemini call per message; see step 3 (cost/latency)
before turning it on for every turn in production.
"""
from __future__ import annotations

import os

# The self-check LLM runs through langchain-google-genai (engine: google_genai in
# guardrails/config.yml). This env var must be set before nemoguardrails is
# imported so its framework registry picks it up.
os.environ.setdefault("NEMOGUARDRAILS_LLM_FRAMEWORK", "langchain")
# ChatGoogleGenerativeAI reads GOOGLE_API_KEY; mirror GEMINI_API_KEY like api.py.
if os.getenv("GEMINI_API_KEY") and not os.getenv("GOOGLE_API_KEY"):
    os.environ["GOOGLE_API_KEY"] = os.environ["GEMINI_API_KEY"]

from nemoguardrails import LLMRails, RailsConfig
from nemoguardrails.rails.llm.options import RailStatus, RailType

_here = os.path.dirname(os.path.abspath(__file__))
_rails: LLMRails | None = None


def _get_rails() -> LLMRails:
    global _rails
    if _rails is None:
        config = RailsConfig.from_path(os.path.join(_here, "guardrails"))
        _rails = LLMRails(config)
    return _rails


def is_blocked(text: str | None) -> bool:
    """True if the user message should be blocked by the input rail.

    Empty/whitespace input is never blocked (the greeting turn sends no message).
    Any guardrail error falls open (returns False) — a flaky safety check must
    not take down the chat endpoint. ponytail: fail-open here; flip to fail-closed
    only if abuse via induced errors ever shows up.
    """
    if not text or not text.strip():
        return False
    try:
        result = _get_rails().check(
            [{"role": "user", "content": text}],
            rail_types=[RailType.INPUT],
        )
        return result.status == RailStatus.BLOCKED
    except Exception:
        import traceback
        traceback.print_exc()
        return False
