# RoomCraft

Interior layout MVP: **upload / scan a room → top-down blueprint → arrange furniture**.

## Stack

- Flutter (Android-first)
- Riverpod state
- Gemini AI (optional room scan)
- Local project storage (versioned JSON)
- Firebase App Distribution for tester builds

## Getting started

```bash
flutter pub get
flutter test
flutter run
```

Set a Gemini API key in **Settings** to use AI scan.

## Docs

- [MVP Implementation Plan](docs/MVP-Implementation-Plan.md)
- [Firebase App Distribution](docs/FIREBASE_APP_DISTRIBUTION.md)

## Branches

- `dev` — active development + CI APKs
