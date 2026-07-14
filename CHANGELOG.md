# Changelog

All notable changes to RoomCraft are documented here.

## 1.0.0-beta.1+16 (2026-07-14)

### AR 4-wall chain + training export
- **AR chain mode (default)**: measure walls A→B→C→D; opposite walls averaged for stable W×L.
- Quick mode still available (width then length only).
- **Training export**: scan ratings + plan snapshots saved as on-device JSONL; Settings → Export training data.
- Consistency warning when opposite walls differ significantly.

## 1.0.0-beta.1+15 (2026-07-14)

### ARCore guided measure (consumer accuracy)
- **AR measure mode (default)**: tap floor corners for width × length using ARCore plane hit-testing.
- Optional photos/video afterward for furniture AI placement; size stays locked to AR.
- Graceful fallback when device lacks ARCore → Easy photo/video.
- Native `ArMeasureActivity` + MethodChannel `com.logicrequire.room_craft/ar_measure`.
- minSdk 24 (ARCore). Sceneform maintained fork for plane UX.

## 1.0.0-beta.1+14 (2026-07-14)

### Consumer Easy Scan (no measurements required)
- **Default scan mode**: Easy — record a walkaround video or upload photos; no tape.
- **Auto-scale**: estimate room size from vision + standard door (~2.75 ft) and furniture priors.
- **Review feedback**: Looks right / Close / Off → analytics for future model training.
- **Docs**: `docs/CONSUMER_SCAN_AND_TRAINING.md` accuracy + training roadmap.
- Field measure remains as Advanced for survey-grade accuracy.

## 1.0.0-beta.1+13 (2026-07-14)

### Cloud Sign-In ready
- Refreshed `google-services.json` with OAuth clients (Android SHA-bound + Web).
- CI bundles `ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID` for Google `idToken` / Firebase Auth.
- Auth + Google provider enabled; Firestore already live with per-user rules.

## 1.0.0-beta.1+12 (2026-07-14)

### Signing & cloud readiness
- **Stable CI upload keystore**: App Distribution APKs share one SHA-1 for Google Sign-In (not ephemeral runner debug keys).
- **Google Sign-In**: request `idToken` via optional `ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID`; clearer error if SHA/Auth incomplete.
- **Firestore rules** (`firestore.rules`): per-user `users/{uid}/rooms/*` only.
- **Docs**: `docs/PLAY_AND_SIGNING.md` — fingerprints, console steps, Play closed testing checklist.
- **CI**: decode keystore from secrets; soft-fail-safe Firebase distribute (from +11 fix).

## 1.0.0-beta.1+11 (2026-07-13)

### Precision — designer field measure (tape) as primary path
- **Research**: competitors (magicplan, RoomPlan, Houzz/Twindo) use AR/LiDAR/laser — photos alone cannot place doors/furniture accurately. See `docs/Scan-Precision-Research.md`.
- **Field measure mode (default)**: enter W×L, then per wall **from left corner (facing wall) + opening width** for doors/windows/balconies; furniture with center-from-left + depth + size.
- Optional **photo + AI suggest** fills tape fields — always verify with tape.
- **Fixed facing-wall coordinates** (south/east were mapped as plan-CCW, which scrambled left→right vs how you face the wall).
- Vision prefers **feet along wall** + standard opening width priors (door ~2.5–3.5 ft).
- **Review**: add/edit/delete openings with tape distances; plan confidence higher for tape path.

## 1.0.0-beta.1+10 (2026-07-13)

### Precision redesign — wall-by-wall (how designers & magicplan-class apps work)
- Research: magicplan etc. use **AR/LiDAR + guided walls/corners**, not single photo→LLM freeform XY.
- **Wall-by-wall capture**: photo Wall A–D; openings as fractions along that wall; furniture as t + depth from wall.
- **Deterministic compose** to top-down plan (no freestyle coordinate guessing).
- Optional overview photos for center furniture.
- Free multi-frame/video remains as fallback mode.
- Still not LiDAR: you measure W×L; AI places features **relative to walls**.

## 1.0.0-beta.1+9 (2026-07-13)

### Precision scan — video walkthrough + multi-pass mapping
- **Record / pick room video** (up to ~90s) → extracts diverse sharp keyframes.
- **Multi-pass vision**: architecture (doors/windows on walls) then furniture.
- **No invented openings** on precision path (add Door/Window tools if missing).
- **Scan confidence** bar on review (heuristic; more frames help).
- Still: user width×length is source of truth (not LiDAR). Walk every wall for best results.

## 1.0.0-beta.1+8 (2026-07-13)

### Phase 1 — table stakes (partial)
- **Catalog**: 40 pieces with search + categories (beds, sofas, desks, storage…).
- **Snap**: furniture snaps to grid, outer walls, and neighbor edges on drag end.
- **Home**: search plans + sort (newest / oldest / name).
- **Door swing**: filled arc keep-out visual.
- **Multi-select**: Multi tool + bulk move/delete.
- **Rotate handle**: amber handle on selected piece (45°).
- **Export PDF**: share text plan PDF (+ PNG).
- **Cloud backup**: Google Sign-In + Firestore backup/restore in Settings (needs Firebase SHA config).

## 1.0.0-beta.1+7 (2026-07-13)

### Fix — stop inventing furniture on scan
- **Strict vision prompts**: default to empty furniture; never invent bed/sofa/TV/bookshelf.
- **Confidence + evidence filter**: drop low-confidence guesses; require clear visibility.
- JSON examples no longer show sample SOFA/BED (which models were copying).
- Review UI explains empty plan can be correct.

## 1.0.0-beta.1+6 (2026-07-13)

### Scan furniture as-is + spacious arrange
- **Scan keeps furniture from photos**: vision prompt lists all visible pieces; sizes/positions preserved (center-based); less aggressive drop rules.
- **Richer type aliases**: desk→table, couch→sofa, dresser→wardrobe, etc.
- **Arrange → Suggest more spacious layout**: re-places *your* scanned furniture (same pieces) along walls with open walkways — does not invent new items.
- Room presets (bedroom/living/office) are secondary and explicitly replace pieces.
- Warns before scan if free vision key is missing (frame-only outcome).

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
