# SeoulFit Backend

FastAPI + LangGraph backend powering the SeoulFit Flutter app.
Self-contained: all AI modules, data, and FAISS vector stores live in this folder.

## Endpoints

- `POST /chat` — conversational trip intake → slot extraction → itinerary (LangGraph + RAG + critic-repair)
- `GET  /state` — current conversation state without invoking the graph
- `POST /reset` — clear a conversation thread
- `POST /analyze-landmark` — Seoul Lens: image → Gemini Vision → seoul.json RAG → English narration
- `GET  /healthz`, `GET /lens/health` — health probes

## Setup

```bash
cd seoulfit_flutter/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

`.env` holds `GEMINI_API_KEY` / `GOOGLE_API_KEY` (already present).

## Run

```bash
source venv/bin/activate
uvicorn api:app --reload --port 8000
```

The Flutter app calls `http://localhost:8000` by default. To point at a deployed
backend, build the app with `--dart-define=API_BASE_URL=https://<host>`.
