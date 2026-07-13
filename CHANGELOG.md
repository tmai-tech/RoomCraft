# Changelog

All notable changes to RoomCraft are documented here.

## 1.0.0-beta.1+5 (2026-07-13)

### Phase 0 — beta trust
- **OBB collision & hit-test**: rotated furniture selects and collides correctly (SAT), not AABB-only.
- **Secure API keys**: Groq/Gemini keys in platform secure storage (migrated from SharedPreferences).
- **Analytics funnel**: `scan_start`, `scan_success`, `scan_fail`, `auto_arrange`, `export`, `open_editor_from_scan` (Firebase Analytics when available).
- **Honest scan copy**: onboarding, scanner, and review explain measured layout sketch (not LiDAR/CAD).
- **Empty furniture UX**: clear card when vision is offline; warnings when no free vision key on build.

## 1.0.0-beta.1+4 (2026-07-12)

### Added — free accurate scan (no user API key)
- **Default scan mode**: Free accurate plan — no Settings key required.
- **AccurateScan enforcer**: room width × length always match your measurements; clean rectangle walls; furniture uses catalog sizes and stays inside the room.
- **App-bundled free vision**: CI can inject `ROOMCRAFT_GROQ_API_KEY` / `ROOMCRAFT_GEMINI_API_KEY` via dart-define so testers get furniture assist without pasting keys.
- Offline path still works with zero keys (exact empty plan).

### Fixed
- Scan parser no longer inflates room size from AI wall extents.

## 1.0.0-beta.1+3 (2026-07-11)

### Fixed — scan proportions & fake furniture
- **Exact room size**: enter Width × Length (e.g. 10 × 10 stays 10 × 10). Photo aspect no longer warps the plan.
- **No invented beds/sofas**: offline default is empty furniture. Presets only if you pick Bedroom/Living/Office.
- **Free AI (Groq Llama 4 Scout)**: optional key detects only furniture visible in photos; room size stays locked to your measurements.

### Added
- Settings: free Groq API key field (console.groq.com)
- Scan mode picker: Free offline · Free AI (Groq) · Gemini

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
