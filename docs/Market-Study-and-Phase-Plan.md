# RoomCraft — Market Study & Feature Phase Plan

**Date:** 2026-07-13  
**Product version analyzed:** `1.0.0-beta.1+4` (`dev`)  
**Stack:** Flutter · ~6.7k LOC Dart · Android closed beta (Firebase App Distribution)  
**Target product:** Photo/scan of a room → **top-down blueprint** → **arrange furniture properly** (clearances, walkways, scale)

---

## 1. Market landscape (2026)

The category is **not one market**. 2026 tools split into three jobs that users often confuse:

| Bucket | Job | Typical tools | RoomCraft fit |
|--------|-----|---------------|---------------|
| **A. Layout planners** | Measured 2D/3D plan, drag furniture | Planner 5D, Homestyler, RoomSketcher, Floorplanner, Sweet Home 3D | **Primary** |
| **B. Scan / measure apps** | Phone AR/LiDAR → floor plan | magicplan, Home Planner AI scanner, AR Plan 3D | **Primary acquisition** |
| **C. AI restylers / staging** | Photo in → pretty photo out | RoomGPT, Remodel AI, Interior AI, REimagine, Collov, Decor8 | **Adjacent — not core** |

### Strategic insight

- **Style tools** win speed and “wow” (10-second redesign) but **do not** produce a measured top-down plan or let you test whether a sofa fits.  
- **Layout tools** win measurements and furniture drag, but photo→plan is still weak or paywalled; auto “organize for traffic flow” is rare.  
- **Scan tools** (magicplan) win accuracy for contractors; consumer furniture-arrange UX is secondary.  

**RoomCraft wedge (unchanged, still valid):**  
> Casual user → room photo + simple measurements → trustworthy top view → **suggest & fix layout for real living** (not photoreal restyle, not contractor estimating).

Nobody owns that loop end-to-end as a polished free consumer product. That gap is the opportunity.

---

## 2. Competitive brands — who they are

### Tier 1 — Direct competitors (same user job)

| # | Brand | Platform | Scale / notes | Pricing (approx.) | Why they matter to RoomCraft |
|---|-------|----------|---------------|-------------------|------------------------------|
| 1 | **Home Planner AI** (Room Planner) | Android / iOS / web | **10M+** Play installs, ~4.7★, top-grossing House & Home | Freemium subscription | Closest all-in-one: **scan + plan + AI layout + huge catalog + 3D** |
| 2 | **magicplan** | iOS / Android | Pro/contractor leader | Free limited (≈2 plans); paid from ~$10–40/mo or per-project | Best **AR scan → measured plan**; estimates/reports for pros |
| 3 | **Planner 5D** | Web + iOS + Android | Consumer plan leader | Free tier + ~$7+/mo HD | Strongest free **2D+3D draw + auto-furnish**; AI floor-plan recognition |
| 4 | **Homestyler** (Autodesk) | Web + mobile | Huge free catalog | Free + studio tiers | Furniture placement + brand materials; 3D dated vs AI photo tools |
| 5 | **IKEA Kreativ** (in IKEA app) | Mobile | Mass market | Free (commerce) | Scan + place **real SKUs** + AR; brand-locked |

### Tier 2 — Layout / pro adjacent

| Brand | Focus | Note |
|-------|-------|------|
| **RoomSketcher** | Clean 2D for real estate | Watermarked free output |
| **Floorplanner** | Detailed architectural plans | Steep learning curve |
| **Sweet Home 3D** | OSS gold standard 2D→3D | Desktop free GPL; mobile commercial |
| **HomeByMe** | 3D collab | Web-led |
| **Coohom / Foyr Neo** | Pro 3D / renders | Enterprise-ish pricing |
| **SketchUp Free** | Full 3D modeling | Not consumer “arrange my room” |

### Tier 3 — AI restyle (do not compete head-on)

| Brand | Core | RoomCraft response |
|-------|------|-------------------|
| RoomGPT, Remodel AI, Interior AI, REimagine, Collov, Decor8, HouseGPTs, Laurel & Wolf | Photo → styled photo in seconds | Optional **post-layout** polish only after plan is locked |

---

## 3. Feature inventory by competitive brand

Legend: **●** strong · **◐** partial / limited · **○** weak or absent

### 3.1 Acquisition: how the room gets into the app

| Feature | RoomCraft | magicplan | Home Planner AI | Planner 5D | Homestyler | IKEA Kreativ | Restylers |
|---------|-----------|-----------|-----------------|------------|------------|--------------|-----------|
| Photo upload | ● | ● | ● | ◐ | ◐ | ● | ● |
| Guided multi-photo | ● | ● | ● | ○ | ○ | ● | ○ |
| AR / LiDAR room scan | ○ | ● | ● | ◐ (iOS scan) | ○ | ● | ○ |
| Manual wall draw | ● | ● | ● | ● | ● | ◐ | ○ |
| User-entered exact W×L | ● | ◐ | ● | ● | ● | ◐ | ○ |
| Scale calibration | ● | ● | ● | ● | ● | ◐ | ○ |
| Auto walls/doors from scan | ◐ (rect + optional vision) | ● | ● | ◐ AI recognition | ○ | ● | ○ |
| Multi-floor / whole house | ○ | ● | ● | ● | ● | ○ | ○ |

### 3.2 Plan editor (top view / blueprint)

| Feature | RoomCraft | magicplan | Home Planner AI | Planner 5D | Homestyler | Sweet Home 3D |
|---------|-----------|-----------|-----------------|------------|------------|---------------|
| 2D top-down canvas | ● | ● | ● | ● | ● | ● |
| Grid + dimensions | ● | ● | ● | ● | ● | ● |
| Doors / windows | ● | ● | ● | ● | ● | ● |
| Diagonal / free walls (balcony etc.) | ● | ● | ● | ● | ● | ● |
| Wall thickness / join polish | ○ | ● | ● | ● | ● | ● |
| Length labels on strokes | ● | ● | ● | ● | ● | ● |
| Units ft / m | ● | ● | ● | ● | ● | ● |
| Undo / redo | ● | ● | ● | ● | ● | ● |
| Multi-select | ○ | ● | ● | ● | ● | ● |
| Layers / rooms list | ○ | ● | ● | ● | ● | ● |

### 3.3 Furniture & arrange

| Feature | RoomCraft | magicplan | Home Planner AI | Planner 5D | Homestyler | IKEA |
|---------|-----------|-----------|-----------------|------------|------------|------|
| Catalog size | ○ (~8 types) | ◐ objects | ● 400k+ | ● huge | ● huge brand | ● IKEA SKUs |
| Catalog search | ○ | ● | ● | ● | ● | ● |
| Custom size | ● | ● | ● | ● | ● | ◐ |
| Drag / rotate / resize | ● | ◐ | ● | ● | ● | ● |
| Grid snap | ● | ● | ● | ● | ● | ● |
| Wall / edge / align snap | ○ | ● | ● | ● | ● | ● |
| Collision detection | ◐ AABB | ◐ | ◐ | ◐ | ◐ | ◐ |
| Clearance rules / walkways | ● tips | ○ | ○ | ○ | ○ | ○ |
| Layout score | ● | ○ | ○ | ○ | ○ | ○ |
| Auto-arrange / AI layout | ● rule packer | ○ | ● Planner AI | ● auto-furnish | ◐ | ◐ |
| Real brand product links | ○ | ○ | ● | ● | ● | ● |

### 3.4 Intelligence & AI

| Feature | RoomCraft | magicplan | Home Planner AI | Planner 5D | Restylers |
|---------|-----------|-----------|-----------------|------------|-----------|
| Free plan without user API key | ● | ● free tier | freemium | freemium | freemium |
| Furniture detect from photos | ◐ (needs build key) | ● objects | ● | ◐ | N/A |
| Photoreal restyle | ○ | ○ | ● styles | ● AI tools | ● core |
| Virtual staging | ○ | ○ | ● | ● | ● |
| Cost estimates / BOQ | ○ | ● core | ◐ shopping list | ○ | ○ |
| Layout quality score | ● | ○ | ○ | ○ | ○ |

### 3.5 Project lifecycle & platform

| Feature | RoomCraft | magicplan | Home Planner AI | Planner 5D | Homestyler |
|---------|-----------|-----------|-----------------|------------|------------|
| Local save | ● | ● | ● | ● | ● |
| Cloud sync / account | ○ (deps unused) | ● | ● | ● | ● |
| Project thumbnails | ● | ● | ● | ● | ● |
| Duplicate / rename | ● | ● | ● | ● | ● |
| Search / sort projects | ○ | ● | ● | ● | ● |
| Export PNG / image | ● | ● | ● | ● | ● |
| Export PDF / DXF / reports | ○ | ● | ● PDF + list | ● | ● |
| Share link / collab | ○ | ● | ● | ● | ● |
| 3D walkthrough | ○ | ● | ● | ● | ● |
| 360 / 4K render | ○ | ● | ● | ● | ● |
| AR place furniture | ○ | ◐ | ● | ◐ | ○ |
| Analytics | ○ | ● | ● | ● | ● |
| iOS ship | ○ | ● | ● | ● | ● |
| Android Play public | ○ (beta only) | ● | ● | ● | ● |
| Offline mode | ● | ◐ | ● | ◐ | ◐ |

---

## 4. RoomCraft current state (complete vs incomplete)

### 4.1 Complete (closed-beta MVP — keep)

| Area | What exists | Key files |
|------|-------------|-----------|
| Home | List rooms, thumbnails, empty/error, duplicate, pull-to-refresh, beta banner | `home_screen.dart`, `room_thumbnail.dart` |
| Onboarding | 3-step skip-able | `onboarding_screen.dart` |
| Manual editor | Walls, doors, windows, balcony (diagonal), pan/select, grid | `blueprint_screen.dart`, `room_provider.dart` |
| Furniture | Catalog categories, custom size, drag, rotate 45°, resize FAB | `furniture_catalog.dart`, catalog sheet |
| Layout IP | Collision, bounds clamp, clearances, auto-arrange (bed/living/office), score 0–100 | `domain/layout/*` |
| Scan path | Guided photos, free accurate W×L plan, review, scale, include/exclude furniture | `scanner_screen`, `accurate_scan`, `scan_review` |
| Free AI | Offline plan always; optional Groq vision + Gemini path | `ai_scanner_service`, `free_vision_scanner` |
| Export | PNG + system share | `export_service.dart` |
| Settings | Units, optional keys, privacy, feedback, onboarding reset | `settings_screen.dart` |
| Storage | Versioned local JSON, migration stub | `storage_service.dart` |
| CI / beta | Build APK + Firebase App Distribution on `dev` | `.github/workflows`, `AGENTS.md` |
| Tests | Unit/widget coverage for scan, layout, storage, history | `test/*` |

### 4.2 Incomplete — must finish for product quality (MVP debt)

| ID | Feature | Status | Why it matters | Competitor bar |
|----|---------|--------|----------------|----------------|
| D1 | True rotated hit-test + OBB collision | Partial / broken feel | Dragging rotated pieces is unreliable | Sweet Home / Planner 5D |
| D2 | Furniture-from-photo always works for testers | Blocked on build secret | Empty furniture after scan kills trust | Home Planner AI, magicplan |
| D3 | Scan copy under-promises (“measured sketch, not LiDAR”) | Weak messaging | Avoids bad reviews vs magicplan | All honest scanners |
| D4 | Analytics funnel (`scan_start`, `scan_success`, `auto_arrange`, `export`) | Missing | No way to measure beta success | All mature apps |
| D5 | Beta tester cohort + pain list | Ops incomplete | Market study said install top apps + talk to users | — |
| D6 | Secure storage for API keys | SharedPreferences only | Security hygiene | Table stakes |
| D7 | Dead Firebase Auth/Firestore deps | In pubspec, unused | Either wire or remove | All cloud apps |
| D8 | Selection ignores rotation | Known MVP shortcut | Feels unfinished | All planners |

### 4.3 Incomplete — competitive table stakes (v1.1)

| ID | Feature | Status | Who has it |
|----|---------|--------|------------|
| T1 | Cloud backup + Google Sign-In | Not started (deps ready) | Everyone except pure OSS desktop |
| T2 | Backend vision proxy (no client key) | Not started | Pros / serious freemium |
| T3 | Catalog 30–50+ pieces + search | 8 types, no search | Homestyler, Planner 5D, Home Planner AI |
| T4 | Snap to wall edges + align furniture | Grid only | Sweet Home 3D, all major planners |
| T5 | Door swing arcs + window light zones (visual) | Tips only | Planner 5D, Sweet Home |
| T6 | Home search / sort by date/name | Missing | All consumer apps |
| T7 | Multi-select + bulk delete/rotate | Missing | All planners |
| T8 | PDF export / dimensioned print sheet | PNG only | magicplan, Home Planner AI, RoomSketcher |
| T9 | On-canvas rotate handle (15°/45°) | FAB only | Sweet Home, Planner 5D |
| T10 | Wall join / corner merge polish | Weak | CAD-ish planners |
| T11 | Release-signed APK + Play closed testing | Debug beta only | Public competitors |
| T12 | Accessibility pass (semantics, targets) | Partial | Play quality bar |

### 4.4 Incomplete — differentiator upgrades (v1.2)

| ID | Feature | Status | Strategic value |
|----|---------|--------|-----------------|
| U1 | Non-rectangular rooms (L-shape) | Rectangle-only scan | Matches real apartments |
| U2 | Multi-photo furniture/opening fusion | Capture multi, weak merge | Closes gap vs scan apps |
| U3 | Stronger auto-arrange (walkway graph, door corridor) | Largest-first packer | **Own “organize properly”** |
| U4 | Better free vision model + confidence UI | Basic Groq path | Photo→plan trust |
| U5 | Optional layout alternatives (A/B suggestions) | Single auto-arrange | Beats Planner 5D auto-furnish on utility |
| U6 | Walkway heatmap / traffic tips v2 | Heuristic score | Unique vs catalog apps |

### 4.5 Explicitly out of scope until traction (v2+)

| ID | Feature | Who owns market | Why wait |
|----|---------|-----------------|----------|
| X1 | Photoreal AI restyle as core loop | RoomGPT / Remodel AI / Interior AI | Crowded, low layout trust |
| X2 | Full 3D walkthrough / 4K render | Planner 5D, Homestyler, Home Planner AI | Expensive; not wedge |
| X3 | AR place-in-room / LiDAR pro scan | IKEA, magicplan | Revisit Kotlin hybrid only if ceiling |
| X4 | Contractor estimates / BOQ | magicplan | Different buyer |
| X5 | Brand marketplace / IKEA commerce | IKEA, Houzz | Different business model |
| X6 | Multi-user collab live edit | Coohom / pro tools | After sync exists |
| X7 | iOS public launch | All majors | After Android PMF |

---

## 5. RoomCraft vs closest competitors — summary scorecard

| Dimension (weight) | RoomCraft | magicplan | Home Planner AI | Planner 5D | Homestyler | Restylers |
|--------------------|-----------|-----------|-----------------|------------|------------|-----------|
| Scan accuracy | 4/10 | **9/10** | **8/10** | 5/10 | 3/10 | 1/10 |
| Top-down edit UX | 6/10 | 7/10 | **8/10** | **9/10** | 8/10 | 0/10 |
| Furniture catalog | 2/10 | 4/10 | **10/10** | **9/10** | **9/10** | 0/10 |
| Layout intelligence | **8/10** | 2/10 | 5/10 | 5/10 | 3/10 | 0/10 |
| Auto organize | **7/10** | 1/10 | 6/10 | 6/10 | 3/10 | 0/10 |
| Free / no-friction scan | **8/10** | 5/10 | 5/10 | 5/10 | 6/10 | 5/10 |
| 3D / wow polish | 1/10 | 6/10 | **9/10** | **9/10** | 7/10 | **10/10** |
| Cloud / multi-device | 1/10 | **8/10** | **9/10** | **9/10** | **8/10** | 7/10 |
| Ship readiness | 5/10 (beta) | 9/10 | 9/10 | 9/10 | 9/10 | 9/10 |

**Takeaway:** RoomCraft is **ahead only on layout intelligence** (score, clearances, auto-arrange). Everywhere else is behind. Do not dilute into restyle; **double down on measured layout quality** while closing scan trust + catalog + cloud table stakes.

---

## 6. Phase plan (what to build, in order)

### Phase 0 — Stabilize beta trust (1–2 weeks) ✅ *shipped in 1.0.0-beta.1+5*  
**Goal:** Testers finish scan → arrange → export without “broken / empty / lying” moments.

| # | Deliverable | Incomplete IDs | Exit criteria |
|---|-------------|----------------|---------------|
| 0.1 | OBB collision + rotation-aware hit-test | D1, D8 | Rotated sofa selects & collides correctly |
| 0.2 | CI always injects free vision key; empty-furniture UX explains why | D2 | Fresh APK scan shows real furniture when photo has it |
| 0.3 | Honest scan messaging + KNOWN_ISSUES update | D3 | Onboarding/scan copy matches capability |
| 0.4 | Firebase Analytics events | D4 | Events visible in console after smoke test |
| 0.5 | Secure key storage | D6 | Keys not in plain SharedPreferences |
| 0.6 | Recruit ≥10 testers; write top-5 pains | D5 | Feedback doc exists |

**Not in this phase:** 3D, restyle, AR, catalog mega-expansion.

---

### Phase 1 — Competitive table stakes (2–4 weeks) → **v1.1**  
**Goal:** App feels like a real consumer planner, not a demo.

| # | Deliverable | Incomplete IDs | Competitor parity |
|---|-------------|----------------|-------------------|
| 1.1 | Google Sign-In + Firestore cloud backup of rooms | T1, D7 | Home Planner AI, Planner 5D |
| 1.2 | Backend proxy for vision (rate-limited; no user key) | T2 | Mature freemium |
| 1.3 | Expand catalog to 30–50 pieces + search | T3 | Still far from 400k — enough for daily use |
| 1.4 | Snap: wall edges + neighbor alignment | T4 | Sweet Home / Planner 5D |
| 1.5 | Draw door swing arcs; optional window light wedges | T5 | Visual clearance |
| 1.6 | Home search + sort | T6 | All apps |
| 1.7 | Multi-select | T7 | All planners |
| 1.8 | PDF one-page plan export | T8 | magicplan / RoomSketcher |
| 1.9 | On-canvas rotate handle (15°/45°) | T9 | Sweet Home UX |
| 1.10 | Release signing + Play closed testing track | T11 | Public path |

**Exit:** New user can scan, arrange, cloud-save, export PDF without pasting API keys.

---

### Phase 2 — Differentiator depth (3–5 weeks) → **v1.2**  
**Goal:** Own “organize this room properly” so reviews mention layout help, not catalog size.

| # | Deliverable | Incomplete IDs | Why |
|---|-------------|----------------|-----|
| 2.1 | L-shape / multi-wall rooms from openings or multi-segment input | U1 | Real homes |
| 2.2 | Multi-photo fusion for furniture + openings | U2 | Scan quality |
| 2.3 | Auto-arrange v2: door corridor graph, walkway ≥2.5 ft, room-type rules | U3, U6 | Core wedge |
| 2.4 | 2–3 alternative layouts + one-tap apply | U5 | Beats single auto-furnish |
| 2.5 | Vision confidence badges + “detect again” quality | U4 | Trust |
| 2.6 | Wall corner join / orthogonal polish | T10 | Editor polish |
| 2.7 | Accessibility audit | T12 | Play readiness |

**Exit:** Blind test — users prefer RoomCraft auto-arrange tips over Planner 5D auto-furnish for a real bedroom.

---

### Phase 3 — Distribution & growth (2–3 weeks) → **v1.3 public beta**  
**Goal:** Leave closed Firebase-only distribution.

| # | Deliverable |
|---|-------------|
| 3.1 | Play Store listing (short form), screenshots, privacy, data safety |
| 3.2 | Crashlytics / ANR budget green |
| 3.3 | In-app feedback → issue triage weekly |
| 3.4 | Soft paywall experiment only if needed (export HD / cloud projects) — optional |
| 3.5 | iOS TestFlight (Flutter already multi-platform) — if Android metrics healthy |

---

### Phase 4 — Post-PMF expansion (later / v2)  
**Only after Phase 2 metrics prove weekly use.**

| # | Deliverable | Condition |
|---|-------------|-----------|
| 4.1 | Optional restyle **after** layout locked | Users ask for “how it looks” |
| 4.2 | Lightweight 3D orbit (not full Coohom) | Demand for shareable 3D |
| 4.3 | AR preview / better scan via **Kotlin module** or ARCore plugin | Scan accuracy still loses to magicplan |
| 4.4 | Brand catalog partnerships | Monetization path |
| 4.5 | Contractor PDF pack | Only if B2B pivot |

---

## 7. Prioritized backlog (implementation order)

```
Phase 0
  1. Rotation hit-test + OBB collision
  2. Free vision always-on for tester builds
  3. Analytics events
  4. Secure prefs for keys
  5. Scan honesty copy + tester ops

Phase 1
  6. Auth + cloud rooms
  7. Vision backend proxy
  8. Catalog expansion + search
  9. Wall/edge snap + align
 10. Door swing visuals
 11. Home search/sort + multi-select
 12. PDF export
 13. Rotate handle
 14. Play closed testing

Phase 2
 15. L-shape rooms
 16. Multi-photo fusion
 17. Auto-arrange v2 + alternatives
 18. Vision confidence UX
 19. Corner join + a11y

Phase 3
 20. Public Play beta
 21. Optional iOS TestFlight

Phase 4 (later)
 22. Restyle after layout
 23. Light 3D / AR hybrid
```

---

## 8. Success metrics by phase

| Phase | Metric | Target |
|-------|--------|--------|
| 0 | Crash-free sessions | ≥ 99% exploratory |
| 0 | Scan → editor complete | ≥ 70% of scan starts |
| 1 | Cloud save used | ≥ 40% of active users |
| 1 | Export used | ≥ 30% |
| 2 | Auto-arrange used | ≥ 50% of sessions with furniture |
| 2 | “Layout score improved after auto-arrange” | Median +15 points |
| 3 | Play install → day-7 return | ≥ 20% |
| 3 | NPS / “would use weekly” | Qualitative top-5 pains closed |

---

## 9. What NOT to build (reaffirm)

1. **RoomGPT-style restyle as the home screen** — crowded, wrong job.  
2. **Full magicplan contractor suite** (estimates, insurance forms) — wrong buyer.  
3. **400k catalog day one** — lose; win on layout rules first.  
4. **Kotlin rewrite** — stay Flutter until AR/CV hard ceiling.  
5. **3D photoreal** before scan trust + cloud + catalog table stakes.

---

## 10. Competitor install links (reference)

| App | Android / install |
|-----|-------------------|
| Home Planner AI | https://play.google.com/store/apps/details?id=com.icandesignapp.all |
| magicplan | https://play.google.com/store/apps/details?id=com.sensopia.magicplan |
| Planner 5D | https://play.google.com/store/apps/details?id=com.planner5d.planner5d |
| Homestyler | https://play.google.com/store/apps/details?id=com.autodesk.homestyler |
| IKEA | https://play.google.com/store/apps/details?id=com.ingka.ikea.app |
| Sweet Home 3D mobile | https://play.google.com/store/apps/details?id=com.eteks.sweethome3d.mobile |
| Sweet Home 3D desktop (OSS) | https://www.sweethome3d.com/ |
| RoomGPT (web) | https://www.roomgpt.io/ |

---

## 11. Open-source references (build, don’t fork blindly)

| Project | Use for RoomCraft |
|---------|-------------------|
| **Sweet Home 3D** (GPL desktop) | Best UX reference for 2D furniture + 3D later |
| arcada-planner / arcada (web) | Canvas interaction patterns |
| floor_plan_builder (Flutter) | Canvas package patterns only |

There is still **no strong OSS** that ships: `casual phone photo → accurate top-down → intelligent packing` as a mobile product.

---

## 12. One-page executive summary

| Question | Answer |
|----------|--------|
| Market job RoomCraft should own | Measured layout: photo → top view → organize furniture properly |
| Biggest competitor threat | Home Planner AI (scan+catalog+3D) + magicplan (scan accuracy) |
| What we already have | Full MVP loop, layout score, auto-arrange, free accurate dimensions |
| What’s incomplete (critical) | Rotation collision, always-on photo furniture, analytics, cloud, catalog, snap polish |
| What competitors have that we skip for now | Photoreal restyle, 400k catalog, contractor estimates, full 3D/AR |
| Next build phase | **Phase 0** (trust) → **Phase 1** (table stakes) → **Phase 2** (layout IP) |
| Stack decision | Stay Flutter |

---

*Document version: 2.0 · Research date: 2026-07-13 · Branch target: `dev`*
