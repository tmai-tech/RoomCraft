# RoomCraft

**Closed beta** `1.0.0-beta.1` — interior layout from room photos.

Upload / scan a room → top-down blueprint → arrange furniture → export PNG.

## Features

- AI room scan (Gemini) with review + scale calibration  
- Manual blueprint editor (walls, doors, windows, furniture)  
- Auto-arrange (bedroom / living / office)  
- Layout score & collision tips  
- Layout alternatives A/B/C (spacious / wall-hug / conversation)  
- 3D isometric preview (orbit)  
- Export / share plan as PNG  
- Firebase App Distribution builds from `dev`

## Getting started

```bash
flutter pub get
flutter test
flutter run
```

**Free accurate scan needs no API key** — enter exact width × length; the plan always matches those measurements.

Optional furniture assist (tried in order): **Groq Llama 4 Scout** → **Hugging Face Qwen2.5-VL** → **Gemini Flash**.  
CI secrets / local defines:

```bash
flutter run \
  --dart-define=ROOMCRAFT_GROQ_API_KEY=gsk_... \
  --dart-define=ROOMCRAFT_HF_TOKEN=hf_... \
  --dart-define=ROOMCRAFT_GEMINI_API_KEY=...
```

Personal keys in Settings (Groq / Hugging Face / Gemini) are optional advanced overrides.

## Docs

| Doc | Description |
|-----|-------------|
| [Market study & phase plan](docs/Market-Study-and-Phase-Plan.md) | Competitors, gaps, Phases 0–4 |
| [MVP plan](docs/MVP-Implementation-Plan.md) | Original Phases 0–5 (closed beta) |
| [Beta checklist](docs/BETA_CHECKLIST.md) | Tester ops |
| [Play signing & Google Sign-In](docs/PLAY_AND_SIGNING.md) | SHA fingerprints, Auth, Play closed track |
| [Consumer scan & training](docs/CONSUMER_SCAN_AND_TRAINING.md) | Easy photo/video path + accuracy roadmap |
| [Consumer scan & training](docs/CONSUMER_SCAN_AND_TRAINING.md) | Easy + ARCore measure roadmap |
| [Known issues](docs/KNOWN_ISSUES.md) | Beta limits |
| [Changelog](CHANGELOG.md) | Release notes |
| [Firebase App Distribution](docs/FIREBASE_APP_DISTRIBUTION.md) | CI distribute |

## Branch

- `dev` — active development + CI APKs to testers
