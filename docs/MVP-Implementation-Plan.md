# RoomCraft — Full-Fledged MVP Implementation Plan

**Product vision:** User uploads a photo of their room → app produces a **top-down blueprint** → user **arranges furniture** so the space is usable (clearances, walkways, scale).

**Stack decision:** Continue **Flutter** through MVP (existing app, CI, Firebase App Distribution).

**Success metric for MVP:** A stranger can scan/upload a room, get a usable top view within 2 minutes, rearrange furniture with snap/collision feedback, save the plan, and install from Firebase App Distribution without a developer.

---

## Current baseline (already on `dev`)

| Area | Status |
|------|--------|
| Home: list / open / delete rooms | Done |
| Manual blueprint: walls, doors, windows, balcony | Done |
| Furniture types: bed, sofa, wardrobe, table, chair, TV, bookshelf, nightstand | Done |
| Drag furniture, rotate (basic), undo, local save | Done |
| AI scan via Gemini (photo → JSON walls + furniture) | Done (fragile models/prompts) |
| Settings: API key in SharedPreferences | Done (not production-safe) |
| Firebase App Distribution + GitHub Build APK | Done |
| Tests, onboarding, layout “intelligence”, export | Missing |
| Collision / clearance rules, catalog, cloud sync | Missing |

**Rough size:** ~2k LOC Dart in `lib/`.

---

## MVP scope (in / out)

### In scope (MVP)

1. Reliable **photo → top view** (even if approximate dimensions).
2. **Edit plan** (walls + openings) and **place/move/rotate** furniture.
3. **Organize properly:** snap, collision, min clearances, one-tap “auto arrange”.
4. **Save / reopen** projects locally (solid).
5. **Share/export** plan image (PNG) for WhatsApp/email.
6. **Ship to testers** via Firebase App Distribution every `dev` push.
7. Basic **onboarding**, empty states, error handling.
8. **Android-first** polished UI (Material 3).

### Out of scope (post-MVP)

- Photoreal RoomGPT-style restyle as core loop  
- Full 3D walkthrough / AR place-in-room  
- Pro LiDAR / mm-accurate CAD  
- Multi-floor whole-house  
- Marketplace / IKEA-style commerce  
- iOS App Store launch (keep code ready, don’t block MVP)  
- Cloud multi-device sync (optional stretch)

---

## Phase overview

| Phase | Name | Duration (est.) | Outcome |
|-------|------|-----------------|--------|
| **0** | Stabilize foundation | 3–5 days | Reliable builds, tests, secrets, no crashes |
| **1** | Core plan editor UX | 1.5–2 weeks | Feels like a real planner (not a sketchpad) |
| **2** | Photo → top view pipeline | 1.5–2 weeks | Trustworthy scan path users prefer over manual |
| **3** | Smart arrangement | 1–1.5 weeks | “Organize properly” is demonstrable |
| **4** | Project lifecycle & polish | 1 week | Save, export, onboarding, empty/error states |
| **5** | Closed beta MVP launch | 3–5 days | 10–30 testers, feedback loop, release checklist |

**Total calendar estimate:** ~6–8 weeks (1–2 engineers, Flutter-focused).

---

## Phase 0 — Stabilize foundation

**Goal:** Engineering baseline so later phases don’t fight the platform.

### Deliverables

| # | Task | Details |
|---|------|---------|
| 0.1 | App identity | Rename consistently: RoomCraft; package `com.logicrequire.room_craft`; launcher icon; splash |
| 0.2 | Config / secrets | Move Gemini key off user-pasted prefs for beta: `dart-define` / remote config / secure storage; document setup |
| 0.3 | Model allowlist | Pin working Gemini models; graceful fallback UI when model fails |
| 0.4 | CI gate | CI: `flutter analyze` + `flutter test` must pass; keep Build APK + App Distribution |
| 0.5 | Smoke tests | Widget tests: home loads, open blueprint, add furniture type |
| 0.6 | Crash-safe storage | Versioned JSON schema for rooms; migration stub `v1` |

### Acceptance criteria

- [ ] Clean install → open app → create manual room → save → kill app → room still there  
- [ ] APK on Firebase after push to `dev` without manual steps  
- [ ] `flutter analyze` / tests green on CI  

### Key files

`pubspec.yaml`, `lib/main.dart`, `lib/services/storage_service.dart`, `lib/services/ai_scanner_service.dart`, `.github/workflows/*`

---

## Phase 1 — Core plan editor (top-view product)

**Goal:** Manual path is good enough that AI is an accelerator, not a crutch.

### Deliverables

| # | Task | Details |
|---|------|---------|
| 1.1 | Canvas interaction model | Separate **pan/zoom** (two-finger / dedicated mode) from **draw/select**; fix InteractiveViewer vs GestureDetector conflicts |
| 1.2 | Selection UX | Tap select, highlight handles, delete selected, multi-select later optional |
| 1.3 | Transform furniture | Drag move, rotate handle (15° / 45° snap), optional resize for non-fixed items |
| 1.4 | Wall tools | Orthogonal snap, join walls at corners, show length labels (ft / m toggle) |
| 1.5 | Grid & scale | Visible grid, pixels-per-foot control, room dimensions editable |
| 1.6 | Furniture palette | Bottom sheet catalog with icons/sizes; search; categories (sleep, seating, storage, tables) |
| 1.7 | Units | Feet and meters; persist preference |
| 1.8 | Undo / redo stack | Full history for strokes + furniture ops |

### Acceptance criteria

- [ ] User can draw a rectangular room with door in &lt; 60s  
- [ ] Place bed + sofa + table; rotate; no accidental pan when dragging item  
- [ ] Length labels match entered room size within UI tolerance  

### Suggested structure

```
lib/
  domain/          # pure models + layout rules (no Flutter)
  features/
    editor/        # blueprint screen, tools, gestures
    catalog/       # furniture definitions
  shared/          # widgets, theme
```

### Dependencies to consider

- Keep custom painters first; only add packages if needed (`vector_math` for transforms).

---

## Phase 2 — Photo → top view pipeline

**Goal:** Primary acquisition path: camera/gallery → validated scan → editable plan.

### User flow

```
Home → “Scan room”
  → Capture 1–4 photos (guidance overlays)
  → Optional wall length for scale
  → AI processing (progress + cancel)
  → Review screen (photo | plan side-by-side)
  → Confirm → Blueprint editor (pre-filled)
```

### Deliverables

| # | Task | Details |
|---|------|---------|
| 2.1 | Capture UX | Guided frames: “show full floor edge”, “include corners”; multi-photo |
| 2.2 | Validation | Keep image quality check; show human-readable failures |
| 2.3 | Structured schema | Versioned JSON schema for walls/openings/furniture; schema validation in Dart |
| 2.4 | Coordinate system | Normalize AI output to room bounds; clamp furniture inside walls |
| 2.5 | Scale calibration | User sets one wall length → scale entire plan |
| 2.6 | Review & edit | Accept / reject furniture suggestions; “detect again” |
| 2.7 | Offline / failure | Manual fallback CTA if AI fails; retry; model fallback already started |
| 2.8 | Privacy copy | In-app: photos sent to Gemini; no permanent server of our own in MVP |

### Acceptance criteria

- [ ] 5 sample room photos produce a plan that opens in editor without crash  
- [ ] At least 1 wall dimension can be corrected by user and furniture rescales  
- [ ] AI failure never loses the user—always can draw manually  

### Risks & mitigations

| Risk | Mitigation |
|------|------------|
| AI invents wrong layout | Review step + easy wall edit |
| Model name / quota errors | Pinned models, clear Settings, rate-limit messaging |
| Metric accuracy poor | Market as “layout sketch” + scale calibration, not CAD |

---

## Phase 3 — Smart arrangement (“organize properly”)

**Goal:** Differentiator vs pure planners and pure AI restylers.

### Deliverables

| # | Task | Details |
|---|------|---------|
| 3.1 | Collision detection | AABB (axis-aligned) + simple OBB for rotated items; red flash on overlap |
| 3.2 | Keep-in-bounds | Furniture cannot leave outer walls |
| 3.3 | Clearance rules | Defaults: walkway ≥ 2.5 ft, bed side ≥ 2 ft, door swing keep-out |
| 3.4 | Snap | Snap to grid, wall edges, align to other furniture edges |
| 3.5 | Auto-arrange v1 | Rule-based packer for room type (bedroom / living): place largest first, against walls, preserve door clearance |
| 3.6 | Score / tips | Simple “layout score” + 2–3 tips (“Door blocked”, “Bed too close to wardrobe”) |
| 3.7 | Room type preset | Bedroom, living, office → different default catalogs + rules |

### Acceptance criteria

- [ ] Auto-arrange on empty bedroom produces non-overlapping layout with door free  
- [ ] Dragging sofa into bed shows collision; release either snaps out or rejects  
- [ ] Tips panel updates live  

### Domain module (testable without UI)

```
lib/domain/layout/
  collision.dart
  clearances.dart
  auto_arrange.dart
  layout_score.dart
```

Unit-test heavily—this is product IP.

---

## Phase 4 — Project lifecycle & product polish

**Goal:** Feels shippable, not a demo.

### Deliverables

| # | Task | Details |
|---|------|---------|
| 4.1 | Project model | Name, created/updated, thumbnail, room type, unit system |
| 4.2 | Home redesign | Cards with thumbnail preview of plan; search; sort by date |
| 4.3 | Export PNG | Render blueprint to image; share sheet |
| 4.4 | Duplicate / rename | Project actions |
| 4.5 | Onboarding | 3 screens: Scan → Arrange → Export; skip-able |
| 4.6 | Empty & error states | No key, no network, corrupt file |
| 4.7 | Accessibility | Large tap targets, contrast, semantic labels on tools |
| 4.8 | Analytics (light) | Optional: Firebase Analytics events `scan_start`, `scan_success`, `auto_arrange`, `export` |
| 4.9 | Settings | Units, API key (beta), privacy policy link, app version |

### Acceptance criteria

- [ ] New user understands flow without verbal explanation  
- [ ] Export PNG opens system share sheet  
- [ ] 10 saved rooms still load fast on mid-range Android  

---

## Phase 5 — Closed beta MVP launch

**Goal:** Real testers; measurable feedback.

### Deliverables

| # | Task | Details |
|---|------|---------|
| 5.1 | Tester group | Firebase group `testers`; 10–30 emails |
| 5.2 | Release notes template | What’s new each build |
| 5.3 | Feedback channel | Form or WhatsApp/Telegram + in-app “Send feedback” (email) |
| 5.4 | Beta checklist | Permissions (camera/storage), ProGuard/R8 if release, versionCode bump policy |
| 5.5 | Known issues list | Document AI accuracy limits |
| 5.6 | Success dashboard | Track: installs, scans completed, auto-arrange used, export used |

### Acceptance criteria

- [ ] ≥ 10 external installs via App Distribution  
- [ ] ≥ 5 completed scan→edit→save sessions  
- [ ] Written list of top 5 pain points for v1.1  

---

## Architecture (target for MVP)

```
┌─────────────────────────────────────────────┐
│  UI (Flutter)                               │
│  Home | Scanner | Editor | Settings         │
└───────────────┬─────────────────────────────┘
                │ Riverpod
┌───────────────▼─────────────────────────────┐
│  Application services                       │
│  ScanService | StorageService | ExportService│
└───────────────┬─────────────────────────────┘
                │
┌───────────────▼─────────────────────────────┐
│  Domain (pure Dart)                         │
│  Room, Furniture, Collision, AutoArrange    │
└───────────────┬─────────────────────────────┘
                │
┌───────────────▼─────────────────────────────┐
│  Data                                       │
│  Local JSON | Secure storage | Gemini API   │
└─────────────────────────────────────────────┘
```

---

## Milestone roadmap (calendar)

| Week | Focus | Exit gate |
|------|--------|-----------|
| 1 | Phase 0 + start Phase 1 canvas | Stable CI; save/load solid |
| 2 | Phase 1 editor UX | Manual plan in &lt; 1 min demo |
| 3 | Phase 2 scan pipeline | Scan→editor on sample set |
| 4 | Phase 2 polish + Phase 3 rules | Collision + scale calibration |
| 5 | Phase 3 auto-arrange + score | Differentiator demoable |
| 6 | Phase 4 polish + export | Shareable PNG |
| 7–8 | Phase 5 beta + bugfix | MVP “launched” to testers |

---

## Work breakdown by epic (implementation order)

1. **Storage schema v1** + migrations  
2. **Editor gesture rewrite** (select vs pan vs draw)  
3. **Furniture catalog + transforms**  
4. **Collision + bounds + snap**  
5. **Scan schema + review UI**  
6. **Scale calibration**  
7. **Auto-arrange + tips**  
8. **Export PNG + home thumbnails**  
9. **Onboarding + beta**  

Do **not** start AR/3D before 1–8 are solid.

---

## Testing strategy

| Layer | What |
|-------|------|
| Unit | Domain: collision, clearances, auto-arrange, JSON parse |
| Widget | Home, editor toolbar, scanner happy path mocks |
| Golden (optional) | Blueprint painter snapshots |
| Manual | 10 real rooms, varied lighting; mid-range Android device |
| CI | analyze + test on every PR; APK + distribute on `dev` |

---

## Risks register

| Risk | Impact | Likelihood | Plan |
|------|--------|------------|------|
| AI layout quality low | High | High | Review UI, manual edit, scale calibration; under-promise |
| Gesture conflicts on canvas | High | Medium | Phase 1 dedicated rewrite |
| API cost / key abuse | Medium | Medium | Rate limits, own key for beta, later backend proxy |
| Scope creep (3D/AR) | High | High | Explicit out-of-scope list; park in backlog |
| Dual-stack pressure (Kotlin) | Medium | Low | Stay Flutter through Phase 5 |

---

## Definition of “Full-fledged MVP” (ship checklist)

- [ ] Scan or manual path both produce editable top-down plans  
- [ ] Furniture catalog with move/rotate/snap/collision  
- [ ] Auto-arrange for at least **bedroom** and **living**  
- [ ] Local project list with thumbnails  
- [ ] Export/share PNG  
- [ ] Onboarding + privacy note for AI photos  
- [ ] Firebase App Distribution builds for testers  
- [ ] No P0 crashes in 30 min exploratory testing  

---

## Post-MVP backlog (v1.1+)

| Priority | Item |
|----------|------|
| P1 | Backend proxy for Gemini (no client API key) |
| P1 | Cloud backup / Google Sign-In (Firebase already in deps) |
| P2 | Better detection models / multi-photo stitching |
| P2 | Door swing & window light zones |
| P3 | AR preview (evaluate Kotlin module only if needed) |
| P3 | iOS release  
| P3 | Style restyle image after layout locked |

---

## Immediate next actions (this week)

1. Freeze MVP scope with this document (no 3D/AR).  
2. Phase 0.4–0.6: tests + storage versioning.  
3. Phase 1.1: fix editor gestures (biggest UX debt).  
4. Recruit 5 design partners for beta list.  
5. Keep shipping APKs on every `dev` merge.

---

*Document version: 1.0 · Stack: Flutter · Branch target: `dev`*
