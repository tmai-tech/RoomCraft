# Changelog

All notable changes to RoomCraft are documented here.

## 1.0.0-beta.1 (2026-07-11)

Closed beta — Android via Firebase App Distribution.

### Added
- **Scan room**: guided multi-photo capture → AI top-down plan (Gemini)
- **Review scan**: scale calibration, furniture include/exclude, plan preview
- **Blueprint editor**: pan / select / draw walls, doors, windows, balconies
- **Furniture catalog** with categories; rotate 45°/90°; grid snap
- **Undo / redo** history for editor actions
- **Units**: feet / meters display toggle
- **Smart layout**: collision highlights, bounds clamp, door clearance tips
- **Auto-arrange** presets: bedroom, living, office (+ re-flow existing)
- **Layout score** 0–100 with tips list
- **Export PNG** and system share sheet
- **Onboarding** (first launch)
- **Home**: thumbnails, duplicate, pull-to-refresh, empty/error states
- **Settings**: API key, units, privacy, feedback, onboarding reset
- CI: Build APK + Firebase App Distribution on `dev`

### Known limitations
See [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md).

### Security / privacy
- Gemini API key stored only on device (MVP)
- Room photos sent to Google Gemini only when you run AI scan
