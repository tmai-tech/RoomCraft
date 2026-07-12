# RoomCraft

**Closed beta** `1.0.0-beta.1` — interior layout from room photos.

Upload / scan a room → top-down blueprint → arrange furniture → export PNG.

## Features

- AI room scan (Gemini) with review + scale calibration  
- Manual blueprint editor (walls, doors, windows, furniture)  
- Auto-arrange (bedroom / living / office)  
- Layout score & collision tips  
- Export / share plan as PNG  
- Firebase App Distribution builds from `dev`

## Getting started

```bash
flutter pub get
flutter test
flutter run
```

**Free accurate scan needs no API key** — enter exact width × length; the plan always matches those measurements.

Optional furniture assist: set GitHub secret `ROOMCRAFT_GROQ_API_KEY` for CI builds, or run locally with:

```bash
flutter run --dart-define=ROOMCRAFT_GROQ_API_KEY=gsk_...
```

Personal keys in Settings are optional advanced overrides.

## Docs

| Doc | Description |
|-----|-------------|
| [MVP plan](docs/MVP-Implementation-Plan.md) | Phases 0–5 |
| [Beta checklist](docs/BETA_CHECKLIST.md) | Tester ops |
| [Known issues](docs/KNOWN_ISSUES.md) | Beta limits |
| [Changelog](CHANGELOG.md) | Release notes |
| [Firebase App Distribution](docs/FIREBASE_APP_DISTRIBUTION.md) | CI distribute |

## Branch

- `dev` — active development + CI APKs to testers
