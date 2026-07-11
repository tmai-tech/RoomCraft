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

Set a **Gemini API key** in Settings to use AI scan.

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
