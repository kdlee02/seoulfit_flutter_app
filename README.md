# SeoulFit

**AI-powered itinerary planner for foreign travelers in Seoul.**

SeoulFit turns a short natural-language conversation into a complete, transit-aware
day plan in Seoul — and lets you point your camera at a landmark to get an instant
English narration of what you're looking at.

---

## Features

- **Conversational trip intake** — describe your trip in plain English; the app
  extracts your preferences (interests, pace, budget, time window) through a chat flow.
- **AI itinerary generation** — a LangGraph pipeline with RAG + a critic-repair loop
  builds a coherent, ordered itinerary from a curated Seoul course/POI dataset.
- **Route variations & transit** — explore alternative routes with public-transit
  directions (subway/bus) and an interactive map.
- **Seoul Lens** — snap a photo of a landmark; Gemini Vision + RAG over a Seoul
  knowledge base returns an English explanation of the place.
- **Map-based final itinerary** — view the finished plan on a map with ordered stops.

## Architecture

```
seoulfit_flutter/
├── lib/            Flutter app (UI, state, services)
│   ├── screens/    App screens (intake, itinerary, lens, transit, …)
│   ├── services/   HTTP clients for the backend
│   ├── providers/  State management (provider)
│   └── config/     Local API keys (gitignored)
└── backend/        FastAPI + LangGraph backend (AI, data, FAISS vector stores)
```

The Flutter app talks to the backend over HTTP. See [backend/README.md](backend/README.md)
for endpoint details.

## Prerequisites

- Flutter SDK (Dart `>=3.2.0 <4.0.0`)
- Python 3.10+ (for the backend)
- A Google API key with **Places API** and **Maps SDK** enabled
- A Gemini / Google Generative AI API key (for the backend)

## Setup

### 1. Frontend (Flutter)

```bash
flutter pub get
```

Configure API keys (these files are gitignored and never committed):

```bash
# Google Places key used by the app
cp lib/config/api_keys.example.dart lib/config/api_keys.dart
# then edit lib/config/api_keys.dart and paste your key

# Android Maps SDK key
echo "MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY" >> android/local.properties
```

### 2. Backend (FastAPI)

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create `backend/.env` (gitignored) with your keys:

```env
GEMINI_API_KEY=your_key_here
GOOGLE_API_KEY=your_key_here
```

## Running

Start the backend:

```bash
cd backend
source venv/bin/activate
uvicorn api:app --reload --port 8000
```

Run the app (defaults to `http://localhost:8000`):

```bash
flutter run
```

To point the app at a deployed backend instead of localhost:

```bash
flutter run --dart-define=API_BASE_URL=https://<your-backend-host>
```

> On an Android emulator, use `http://10.0.2.2:8000` to reach a backend running on
> your host machine.

## Configuration reference

| Setting | Where | Notes |
|---|---|---|
| Google Places key | `lib/config/api_keys.dart` | gitignored |
| Google Maps (Android) key | `android/local.properties` (`MAPS_API_KEY`) | gitignored |
| Backend AI keys | `backend/.env` | gitignored |
| Backend URL | `--dart-define=API_BASE_URL=…` | defaults to `localhost:8000` |

## Security note

Never commit real API keys. The files above are gitignored by design — keep them
local and rotate any key that is accidentally exposed.

## Tech stack

- **Frontend:** Flutter, Provider, flutter_map, google_fonts
- **Backend:** FastAPI, LangGraph, FAISS (RAG), Google Gemini
