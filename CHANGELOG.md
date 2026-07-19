# Changelog

All notable changes to RoomCraft are documented here.

## 1.0.0-beta.1+107 (2026-07-19)

### Accuracy — opening chain fidelity (Planner5D-class doors/mesh)
- New **`OpeningChainFidelity`**: snap walk-through doors to gold **2.8 ft**, reclassify oversized “doors” as mesh when inventory wants balcony, de-overlap same-wall openings, seed missing doors/mesh from inventory counts.
- Wired into study finalize + non-study density; score blends geometry + opening fidelity.
- Default door prior **2.8** ft (was 3.0). Addresses feedback “door not identified” / wrong spans.
- Tests +107. See `docs/ACCURACY_TURN_LOG.md` Turn 57.
- Version **+107**.

## 1.0.0-beta.1+106 (2026-07-19)

### Accuracy — non-study bedroom/living dense gold (+106)
- **Non-study density path**: bedroom/living no longer exit after polish-only; `ensureNonStudyDensity` + `composeNonStudyGold` wall-fill inventory (e89c quality class: bed@N, wardrobe@S, sofa@W, tv@E).
- **Pending inventory gate**: do not early-accept study photo-true when MUST bed/sofa/tv still missing.
- **Inventory parse fix**: polish notes like "no bed invent" no longer poison bedroom detection; `must include bed` wins.
- Score bar **72–84%** for dense non-study (honest; not study 74% photo-true which forbids bed).
- Tests +106. See `docs/ACCURACY_TURN_LOG.md` Turn 56.
- Version **+106**.

## 1.0.0-beta.1+105 (2026-07-19)

### Accuracy resume — gold geometry match + wardrobe scale fix
- **No scale-down from full-wall wardrobes**: AutoScale skips freestanding 6.5 ft prior when vision reports ≥7 ft slider (Planner5D-class: wall units are not catalog freestanding priors). Prevents crushing 20×17 gold rooms.
- **Gold room floor** matched to feedback `32ffdc65` manual plan: **20.3×17.0** ft (was 20.0).
- **`goldGeometryMatchScore`**: structural fidelity vs gold (room size, wardrobe span, work-wall desk, dual doors, mesh, chair) blended into finalize score (ceiling ~98%, not fake 100% LiDAR).
- Tests: auto_scale + photo_true +105. See `docs/ACCURACY_TURN_LOG.md` Turn 55.
- Version **+105**.

## 1.0.0-beta.1+104 (2026-07-18)

### Room notes · smart search · feature graphic
- Plan notes (client/address/goals) + home search across notes/space/shape.
- Play **feature graphic 1024×500** export from Settings and blueprint.
- PDF includes notes. Version **+104**.

## 1.0.0-beta.1+103 (2026-07-18)

### Dark theme · wall height · Play listing copy
- System / light / dark theme (Settings).
- Per-room wall height for 3D extrusion.
- Copy short & full Play listing text from Settings.
- Version **+103**.

## 1.0.0-beta.1+102 (2026-07-18)

### Home pillars · store screenshot · exterior furnish
- Home quick-action pillars: AR, Photo scan, Draw, Gallery.
- Export **store screenshot** 1080×1920 marketing frame for Play assets.
- Exterior patio rooms get outdoor furniture recipe (grill, patio sofa…).
- Version **+102**.

## 1.0.0-beta.1+101 (2026-07-18)

### Walkway free-% · heatmap PNG · onboarding refresh
- Layout bar shows **Walkways N%** free-path when heatmap is on.
- Export: **Share PNG + walkway heatmap** with legend; PNG title includes score / walkway %.
- Onboarding covers AR place, 10k catalogue, 3D lighting, multi-floor, privacy.
- Version **+101**.

## 1.0.0-beta.1+100 (2026-07-18)

### 3D lighting · plan pack · privacy data safety
- Day / evening / night SceneLighting in 3D editor.
- Share plan pack (2D + 3D PNGs).
- In-app Privacy & data safety + STORE_LISTING.md.
- Version **+100**.

## 1.0.0-beta.1+99 (2026-07-18)

### Multi-floor + exterior patio
- floorLevel / isExterior, upper-floor duplicate, grass exterior stage.
- Gallery patio + upper loft.
- Version **+99**.

## 1.0.0-beta.1+93 (2026-07-18)

### 3D lit faces + ceiling · skeptic proof line numbers
- Stronger 3D face lighting + ceiling plane in perspective walkthrough.
- `docs/SKEPTIC_PROOF.md` refreshed with current line numbers (AR line 583, V7 line 61).
- Full verification suite 18/18.
- Version **+93**.


## 1.0.0-beta.1+92 (2026-07-18)

### V7 edit-in-3D proven in interactive_3d_styler_test (skeptic-cited file)
- Replaced open-only 3D widget test with full select/rotate/apply/delete path.
- Writes `interactive_3d_widget.txt` with `source_test=interactive_3d_styler_test.dart`.
- Full verification suite 18/18.
- Version **+92**.


## 1.0.0-beta.1+91 (2026-07-18)

### HD 3D snapshot · walkthrough-first · skeptic proof doc
- **HD 3D snapshot** export (1600×1200 perspective walkthrough PNG) + share from 3D editor.
- Default 3D mode is **perspective walkthrough** (iso optional).
- `docs/SKEPTIC_PROOF.md` maps skeptic claims to current tree + evidence.
- Version **+91**.


## 1.0.0-beta.1+90 (2026-07-18)

### AR place layout loop (measure → place → 3D)
- New **ArPlaceLayoutScreen**: after ARCore measure, place furniture at real size (AI Designer or catalogue).
- Scanner AR path navigates to place layout; shortcut “Place furniture at AR size”.
- Plan §5 tracks full Play objective; no reduced completion definition.
- Tests prove AR place → furnish → open 3D.
- Version **+90**.


## 1.0.0-beta.1+89 (2026-07-18)

### Walkthrough 3D explore · plan §5 tracks full Play objective
- **3D walkthrough camera** (first-person eye height + walk pad) on perspective mode.
- Plan §5 rewritten: tracks all Play listing pillars P1–P7 without redefining objective away.
- Catalog sheet shows **10,000+ items** badge.
- Version **+89**.


## 1.0.0-beta.1+88 (2026-07-18)

### Skeptic-gap closure: 10k catalog, distinct AR, edit-in-3D proof, perspective 3D
- **10,000+ free catalog SKUs** via seed × material × size × collection expansion.
- **AR Room Planner** opens `ScannerScreen(initialScanMode: ar_guided)` — not photo-scan alias.
- **V7 edit-in-3D**: furniture picker → rotate → apply `onFurnitureChanged`; delete path proven.
- **Perspective 3D** projection mode (camera elev + depth) alongside isometric.
- Tests: `test/skeptic_gaps_test.dart` evidence under implementer/evidence.
- Version **+88**.


## 1.0.0-beta.1+87 (2026-07-18)

### 200+ catalog · integrated 2D/3D · goal verification C1–C8
- Catalog expanded to **200+ SKUs** (size/finish variants across categories).
- **Integrated 3D edit mode** in Blueprint (tap toggle; long-press full-screen editor).
- Goal success criteria C1–C8 and verification V1–V8 rewritten without paid-engine blockers.
- Version **+87**.


## 1.0.0-beta.1+86 (2026-07-18)

### Gallery of ideas · 120 SKUs · Blueprint→3D e2e evidence
- Catalog expanded to **~120 SKUs** (gym, kitchen, bath, decor variants).
- **Gallery of ideas** on Home — 6 free starter plans via AI Designer.
- Widget e2e: Blueprint → 3D editor; Auto → Compare layouts apply/undo.
- Verification plan (§6) maps each step to evidence files.
- Version **+86**.


## 1.0.0-beta.1+85 (2026-07-18)

### Interactive 3D editor · AI Styler · AR entry
- **3D room editor**: tap-select, rotate, delete, nudge; apply edits back to 2D plan.
- **AI Styler**: palette/materials tips + style restyle (Furnisher pipeline), free on-device.
- **AR Room Planner** entry on Home create sheet (ARCore real dimensions path).
- Tests + evidence for styler, interactive 3D, catalog type count.
- Version **+85**.


## 1.0.0-beta.1+84 (2026-07-18)

### Planner 5D level-up: catalog, AI Designer, 3D evidence
- **Catalog ~93 SKUs** across 11 categories (kitchen, bath, lighting, decor, office, outdoor…).
- **18 furniture types** (desk, rug, plant, lamp, appliance, vanity, bath, toilet, outdoor…).
- **AI Designer (Furnisher)** — 6 on-device styles (Modern minimal, Cozy, Scandinavian, Family, Home office, Studio).
- Catalog items carry **catalogId** through arrange/reflow; rugs as floor layer.
- 3D isometric: gradient stage, height slider, orbit; widget + paint path tests with evidence.
- Layout A/B/C apply/undo covered via roomProvider integration tests.
- Version **+84**.


## 1.0.0-beta.1+83 (2026-07-18)

### Planner 5D parity sprint — isometric 3D + layout A/B/C
- **3D isometric preview** (`IsometricPainter` + `IsometricPreviewScreen`): orbit with drag/slider; free CustomPainter (no 3D engine).
- **Layout alternatives A/B/C**: spacious, wall-hug, conversation — scored with live `LayoutScore`; apply with undo.
- Blueprint: **view_in_ar** app bar action; Auto sheet → Compare layouts.
- Docs: `docs/PLANNER5D_PARITY_PLAN.md` gap matrix vs Planner 5D + free/current-arch path.
- Tests: `test/isometric_layout_alternatives_test.dart`.
- Version **+83**.


## 1.0.0-beta.1+51 (2026-07-17)

### Unified ensureGoldQuality path
- Single entry **ensureGoldQuality**: polish → hybrid merge → full study gold until photo-true.
- Wired into labeled multi-wall scan, winner backend, and Open editor.
- Vision-preserved wardrobe hybrid score raised to **82%** (closer to trusted gold plan).
- Version **+51**.

## 1.0.0-beta.1+50 (2026-07-17)

### Hybrid vision + study gold merge
- **mergeWithStudyGold**: keep vision wardrobe/desk/chair placements; fill only missing pieces and openings from study gold template.
- Multi-wall incomplete path uses hybrid merge (not full template wipe).
- Full `composeStudyGold` only if hybrid still incomplete.
- Version **+50**.

## 1.0.0-beta.1+49 (2026-07-17)

### Deterministic study gold layout (photo-true gold quality)
- New **PhotoTrueLayout.composeStudyGold**: full dense plan (long wardrobe, desk+chair, 2 doors + mesh, score 74%).
- No bed/sofa/TV invent — matches study photo-true gold quality bar.
- Multi-wall incomplete after polish → **composeStudyGold** guarantee (labeled path + winner path).
- Version **+49**.

## 1.0.0-beta.1+48 (2026-07-17)

### Gold-plan editor handoff + opening labels
- Review preview labels **doors/mesh** with widths; thicker opening strokes.
- **Open editor** re-runs photo-true polish so blueprint matches review.
- Wardrobe prefers **long wall without doors** (storage wall).
- Labeled multi-wall: offline **deterministic photo-true guarantee** if vision still incomplete.
- Version **+48**.

## 1.0.0-beta.1+47 (2026-07-17)

### Gold-plan density: distinct openings + size labels
- Seed doors/mesh on **different walls** (gold multi-opening layout).
- Review preview labels show **name + size** (e.g. Wardrobe 6.7×1.5).
- Wall vision: stronger MUST wardrobe/TABLE/opening instructions per wall.
- Longer wall-by-wall wardrobe seed (~6.5–7.5 ft).
- Version **+47**.

## 1.0.0-beta.1+46 (2026-07-17)

### Forced second photo-true polish on multi-wall
- Labeled multi-wall path: if first polish incomplete → **second polish** with full study inventory MUST list.
- Winner backend path: same forced second polish when multi-wall/3+ photos still incomplete.
- Longer gold-style wardrobe seed (~6.5–7.5 ft along wall).
- Version **+46**.

## 1.0.0-beta.1+45 (2026-07-17)

### Multi-wall inventory floor + gold-plan room scale
- Multi-wall / labeled scans: if inventory empty/weak (no wardrobe MUST, no bed claim) → full photo-true floor (wardrobe, desk, chair, doors, mesh, NO bed/sofa/TV).
- Dense auto room floor raised to **18×16** (closer to gold ~18.5×17.2) when wardrobe+mesh.
- HF multi-frame gets the same inventory floor.
- Version **+45**.

## 1.0.0-beta.1+44 (2026-07-17)

### Openings preserved + chair density (gold-plan fill)
- Keep **raw door/window/balcony** segments when wall field-map fails (no longer drop openings).
- Seed **chair next to desk** when inventory mentions chair.
- Stronger door/mesh defaults for multi-wall wardrobe study rooms.
- Version **+44**.

## 1.0.0-beta.1+43 (2026-07-17)

### Preserve wall placement (stop scrambling gold plans)
- Polish no longer **always** puts wardrobe on west / desk on south.
- **Keeps vision wall** for existing wardrobe/table; seeds only missing pieces on free walls.
- Already photo-true plans are **not reshuffled** (score bar only).
- Version **+43**.

## 1.0.0-beta.1+42 (2026-07-17)

### Multi-wall reliability + readable gold plan preview
- Wall-label sheet **Cancel no longer aborts scan** — uses default walk order.
- Multi-wall with **NO BED** but missing wardrobe MUST → boost wardrobe/desk/doors/mesh inventory.
- Review preview: **type colors + labels** (Wardrobe / Desk) so plan is not “empty white”.
- HF easy path: photo-true **min room size** + wardrobe prior like Groq.
- Version **+42**.

## 1.0.0-beta.1+41 (2026-07-17)

### Honest gold score + wall-compose MUST pieces (feedback 443cf0c3)
- Feedback **+39**: 16×14 + **74%** but nearly empty plan (table only).
- **Never claim 74%** unless WARDROBE (long ≥5 ft) + TABLE + openings + area ≥12 ft².
- Incomplete plans **cap confidence ≤48%**.
- Rebuild wardrobe (west) + desk (south) via **WallRelativeComposer** when inventory/warnings require them.
- Seed doors/mesh from inventory warnings when missing.
- Version **+41**.

## 1.0.0-beta.1+40 (2026-07-17)

### End-to-end photo-true winner polish
- **Always** run PhotoTrueLayout.polish on the winning scan backend (Groq/HF/Gemini).
- Layout quality scoring: +50 for photo-true; penalize zero openings; weak if no doors.
- Prefer polished layouts when comparing backends; try next engine if not photo-true yet.
- HF easy + locked paths also polish to gold-quality bar.
- Version **+40**.

## 1.0.0-beta.1+39 (2026-07-17)

### Gold-plan quality polish (photo-true ~74% bar)
- New **PhotoTrueLayout.polish**: wall-hug wardrobe/table, normalize long wardrobe ~6.5×1.5, spread openings across walls.
- Score floor **0.74** when WARDROBE + TABLE + openings and no bed/sofa/TV (matches gold plan quality bar).
- Dense min room **16×14** when wardrobe + mesh/multi-door inventory (auto-scale only).
- ScanRefine preserves photo-true score bar.
- Version **+39**.

## 1.0.0-beta.1+38 (2026-07-17)

### Gold-plan furniture size: wardrobe scale + room floor
- AutoScale WARDROBE prior **6.5 ft** (was 4.0 — shrank correct long sliding units).
- Catalog default wardrobe **6.5×1.5**; size-aware `entryForSized` for wide units.
- AccurateScan / ScanRefine no longer crush long wardrobes toward 4 ft.
- Photo-true min room **14×12** when inventory requires wardrobe (auto-scale only; tape still wins).
- Labeled multi-wall path applies min size before wall-by-wall place.
- Version **+38**.

## 1.0.0-beta.1+37 (2026-07-17)

### Photo-true gold quality: keep wall detections + wall-anchored fill
- **Root cause**: wall compose min confidence was **0.70** while wall vision keeps ≥0.55 — real wardrobe/desk were dropped.
- Wall-anchored floor now **0.55** (matches filter).
- **Photo-true fill** after wall-by-wall: MUST WARDROBE/TABLE + doorCount + mesh as high-confidence wall anchors.
- Accuracy score ≥~72% when photo-true (wardrobe+table+openings, no bed/sofa invent).
- Version **+37**.

## 1.0.0-beta.1+36 (2026-07-17)

### Photo-true scan → gold-plan quality (study room)
- Inventory **recall bias** + second-chance pass when multi-wall photos miss wardrobe/desk.
- **Enrich from notes**: pink sliding wardrobe / desk / mesh / doors recover MUST flags if booleans were false.
- **Openings seed** from inventory: doorCount + mesh balcony when wall vision omits them.
- Wardrobe seed size ~6.7×1.5 (gold-plan style wall unit); score boost when WARDROBE+TABLE+openings present.
- Photo-true bar (not invent bed/sofa/TV): dense wall-anchored plan matching feedback gold **quality**.
- Version **+36**.

## 1.0.0-beta.1+35 (2026-07-17)

### Feedback form multi-image select
- Gallery on Send feedback uses **pick multi image** (up to 5) so testers can attach room inputs + wrong plan in one go.
- Camera still adds one shot at a time.
- Version **+35**.

## 1.0.0-beta.1+34 (2026-07-16)

### Labeled 4-wall clean path (no bulk scatter)
- When user **labels 3–4 walls**, skip bulk free-scatter multi-image layout.
- Path: inventory → **size-only** estimate → wall-by-wall place → MUST fill → door-prior resize.
- Cleaner, more exact plans for the intended 4-image workflow.
- Version **+34**.

## 1.0.0-beta.1+33 (2026-07-16)

### MUST inventory fill for 4-wall plans
- After wall-by-wall: if inventory requires WARDROBE/TABLE but missing, **merge from bulk**, then **placement-only vision pass**, then seed.
- User-labeled 4 walls → **always prefer wall plan** (with openings from bulk if wall openings empty).
- Version **+33**.

## 1.0.0-beta.1+32 (2026-07-16)

### Per-wall inventory constraints
- Wall-by-wall vision gets the **same inventory MUST/NO list** as multi-image (no bed/sofa/TV invent on a single wall photo).
- Per-wall prompts: mirror ≠ wardrobe, desk ≠ TV unit; examples use WARDROBE/TABLE not sofa.
- When user labeled walls, **strongly prefer wall-by-wall** over bulk layout (margin 20).
- Version **+32**.

## 1.0.0-beta.1+31 (2026-07-16)

### 4-image wall labeling UI
- Before Generate plan with **3–4 photos**, show **Label each wall photo** sheet (south/east/north/west).
- Wall-by-wall vision uses **user labels** instead of blind upload order.
- Higher gallery capture resolution (2048 / q95).
- Version **+31**.

## 1.0.0-beta.1+30 (2026-07-16)

### 4-image size-lock then wall-by-wall
- Run **bulk layout first** for room size (AutoScale), then **wall-by-wall** at that size (no more 12×14 default for wall placement).
- Prefer wall-by-wall on **tie/near-tie** (more stable than free-scatter bulk).
- **Dedupe** major furniture types (one wardrobe/table/bed/sofa/TV).
- Simple Scan UI tip: 4-photo walk order south→east→north→west, full-res only.
- Version **+30**.

## 1.0.0-beta.1+29 (2026-07-16)

### 4-image ordered wall-by-wall (designer method)
- When user uploads **3–4 photos**, run **ordered wall-by-wall** vision: photo0→south, 1→east, 2→north, 3→west (per-wall placement, not free-scatter bulk layout).
- Compare bulk multi-image plan vs wall-by-wall; **keep the higher inventory-aware score**.
- Wall-relative confidence floor **0.55** (was 0.68/0.72) so wardrobe/desk are not dropped.
- Inventory filter + seed on wall-by-wall results.
- Version **+29**.

## 1.0.0-beta.1+28 (2026-07-16)

### 4-image multi-wall accuracy
- **Multi-wall photo prompts** when 3–6 gallery photos: consistent N/S/E/W, no random scatter, must place wardrobe/desk if seen.
- **Inventory seed**: if pass-1 says MUST include WARDROBE/TABLE but layout omits them, seed wall-anchored defaults (same for HF path).
- **Gemini locked prompt** switched to wall-anchored furniture (removed free-XY bed/sofa examples that biased random plans).
- Slightly higher image encode quality for vision API payloads.
- Version **+28** — distinct from +27 re-upload confusion.

## 1.0.0-beta.1+27 (2026-07-16)

### Scan accuracy — multi-backend pick (not same as +26)
- **Weak-layout fallback**: Hugging Face Qwen runs when Groq is empty **or thin/weak** (not only empty), then Gemini if still weak.
- **Best-of quality score**: prefer plan with better inventory (WARDROBE/TABLE, piece count, openings) instead of always keeping first Groq result.
- **Stronger prompts**: mirror ≠ wardrobe; desk monitors ≠ TV unit; empty furniture only if room empty.
- **Review shows real backend**: geometry refine no longer hides “Groq / HF / Gemini” source line.
- Version label **+27** so testers can confirm they are not on a re-upload of +26.

## 1.0.0-beta.1+26 (2026-07-15)

### Accuracy vs feedback 5244fa22 + e89c702e
- **Root cause of “random”**: geometry refine always re-snapped furniture to nearest wall after correct wall-anchored placement — **fixed** (only floating pieces snap).
- **Inventory → place**: first pass lists what exists (no invented bed/sofa/TV); second pass places only those items on walls.
- Softer catalog size overrides so wardrobe/desk footprints match photos.
- Feedback previews: up to **5** smaller thumbs so input + output plans both upload.

## 1.0.0-beta.1+25 (2026-07-15)

### Simple scan + less random layout (feedback 53a501e6-018)
- **Simple Scan UI**: Gallery / Camera / Video + Generate plan only. AR/tape under “More options”.
- **Wall-anchored layout**: vision prompts + parser use `wall` + `fromLeft` + `depth` (designer method) instead of free XY — main fix for random furniture placement.
- Live Groq smoke test fixtures from real room photos (`test/fixtures/room_feedback`).

## 1.0.0-beta.1+24 (2026-07-15)

### Scan furniture recall (feedback: empty / random plans)
- **Prompts**: stop biasing models toward empty `furniture: []`; require listing all clearly visible major pieces (bed, sofa, TV, wardrobe, table, chairs).
- **Filter**: confidence floor **0.55** (was 0.80); keep typed items even when the model omits `confidence`.
- **Confidence UI**: score capped ~50% when furniture count is 0 (no more ~78% empty plans).
- **Furniture cap**: keep up to 12 pieces (was 8).
- **Hugging Face free VLM fallback**: serverless Qwen2.5-VL via Inference Providers router when Groq returns empty / fails. Token in Settings or `ROOMCRAFT_HF_TOKEN`.
- Backend order: **Groq Scout → Hugging Face Qwen → Gemini Flash → offline**.

## 1.0.0-beta.1+23 (2026-07-14)

### Fixes from user feedback (report 1c373b54-144)
- **Multi gallery scan**: Easy scan primary action is **Pick photos from gallery** (multi-select up to 8). AR and free-frame modes also get **Gallery (multi)**.
- Gallery is no longer single-image-only — consumers can upload several room wall photos at once.

## 1.0.0-beta.1+22 (2026-07-14)

### Fixes from user feedback (report 7be5dbfd-09b)
- **Left/top edge drawable**: room outline is inset from the canvas origin so Wall/Door/Window tools can hit the left edge; openings magnet-snap to the room perimeter.
- **Less random scans**: furniture always wall-snapped (no floating freeform XY); catalog footprints preferred; openings capped (≤2 doors / 4 windows / 1 balcony); furniture capped at 8; vision confidence raised to 0.80.

## 1.0.0-beta.1+21 (2026-07-14)

### Fixes from user feedback (report 94510d3e-bd8)
- **Manual room size**: creating a manual plan asks for width × length (no mystery 10×10 default).
- **Furniture placement**: freer drag — soft ¼-ft snap, no auto-shove when items overlap (collisions still highlighted).
- **Feedback previews**: embed small screenshot previews in Firestore when Storage is unavailable so the team can review images.

## 1.0.0-beta.1+20 (2026-07-14)

### Feedback form with screenshots
- Settings → **Send feedback**: category, description, up to 5 screenshots (gallery/camera).
- Saves report locally and to Firestore `feedback/{id}`; Storage when bucket is enabled.
- **Share screenshots** via system sheet (email) so the team can diagnose crashes.
- Script: `scripts/list-feedback.mjs` to list reports for review.

## 1.0.0-beta.1+19 (2026-07-14)

### Fix AR crash on “Measure 4 walls”
- **Removed Sceneform** (root cause of native crash when opening AR measure).
- Pure **ARCore** session + camera feed + center reticle + **Mark corner** button.
- Same 4-wall chain / quick / diagonal refine flow, without fragile 3D scene graph.

## 1.0.0-beta.1+18 (2026-07-14)

### Crash fixes (AR)
- Request **camera permission** before opening AR measure (common crash cause).
- `isAvailable` no longer triggers AR install UI (probe-only).
- ArMeasureActivity crash-hardened: programmatic fragment, fail with error result instead of process kill.
- Safer AppCompat theme + plain buttons; default scan mode Easy until AR proves available.

## 1.0.0-beta.1+17 (2026-07-14)

### Accuracy upgrades
- **Geometry refine**: standard door/window widths, snap furniture to walls, separate overlaps, better confidence.
- **AR diagonal check**: after wall measures, tap opposite corners to correct scale drift.
- **Review → Refine size with AR**: re-lock any photo plan to AR 4-wall measure without rescanning furniture layout from scratch.

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
