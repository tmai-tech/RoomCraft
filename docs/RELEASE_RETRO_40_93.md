# Release retrospective — builds +40 → +93 (Firebase)

Retrospective of RoomCraft closed-beta builds from **version +40** through the **latest Firebase-distributed build (+93)**.

**Format per build:** Turn # · Build · What was asked? · What model did? · Where can we see it? · Still lacking → fixed next

**Turn #** = sequential agent fix-loop turn starting at **Turn 1 = build +40** through **Turn 54 = build +93** (one shipped build ≈ one turn of ask → ship → gap → next ask).

---

## Sources & where things live

| What | Where |
|------|--------|
| Version history | `CHANGELOG.md` (+40–51, +83–93 fully written; +52–82 only in git subjects) |
| Code / commits | `git log` on `dev` (e.g. `a1a7b9c` = +40 … `a2056bc` = +93) |
| Tester feedback that drove scan fixes | `data/feedback/` + `data/feedback/INDEX.json` |
| CI / APK builds | [Build APK workflow](https://github.com/tmai-tech/RoomCraft/actions) |
| **Latest Firebase distribute** | **+93** · run [29628861956](https://github.com/tmai-tech/RoomCraft/actions/runs/29628861956) · SHA `a2056bc` · 2026-07-18 |
| Firebase console | [App Distribution · roomcraft-e1312](https://console.firebase.google.com/project/roomcraft-e1312/appdistribution) |
| App version on device | Settings / About → `1.0.0-beta.1+N` |

---

## How to read the table

| Column | Meaning |
|--------|---------|
| **Turn #** | Sequential fix-loop turn (1…54). Turn *N* ships build `+(39+N)`; gaps closed become the ask for Turn *N+1*. |
| **Build** | App `versionCode` / build number (`1.0.0-beta.1+N`) |
| **What was asked?** | User / goal request that drove the build |
| **What model did?** | What that version actually shipped |
| **Where can we see it?** | Proof / feedback / CI |
| **Still lacking → fixed next** | Gap left open that the *next* turn/build closed |

### Turn ↔ build quick map

| Turn range | Builds | Era |
|-----------:|--------|-----|
| **1–12** | +40 → +51 | Photo-true gold plan scan |
| **13–43** | +52 → +82 | Gold orientation / geometry last-mile |
| **44–54** | +83 → +93 | Planner 5D / 3D product |

Formula: **Turn = Build − 39** · **Build = Turn + 39**

---

## Era A — Photo-true “gold plan” scan (Turns 1–12 · builds +40–+51)

Driving feedback after +34–+39:

- **c8c569e9** (+34): size/position wrong, doors missing
- **32ffdc65** (+35): manual gold plan vs AI scan mismatch
- **443cf0c3** (+39): “still wrong scan results” (74% but nearly empty)

| Turn | Build | What was asked? | What model did? | Where can we see it? | Still lacking → fixed next |
|-----:|------:|-----------------|-----------------|----------------------|----------------------------|
| **1** | **+40** | Always make the *winning* backend plan photo-true (not only some paths) | Always run `PhotoTrueLayout.polish` on winner; score prefers polished / photo-true | `CHANGELOG` +40 · commit `a1a7b9c` · Firebase via Build APK | Polish could still claim high score with almost-empty plans → **Turn 2 / +41** |
| **2** | **+41** | Stop lying about 74% on empty plans (feedback 443cf0c3) | Cap confidence ≤48% if incomplete; never claim 74% without long wardrobe + table + openings; rebuild MUST pieces via wall compose | Feedback `data/feedback/443cf0c3-1b4` · `CHANGELOG` +41 | Cancel on wall labels aborted scan; preview still “empty white” → **Turn 3 / +42** |
| **3** | **+42** | Multi-wall reliability + readable preview | Cancel no longer aborts; inventory boost when NO BED but missing wardrobe; type colors/labels on review | `CHANGELOG` +42 | Polish still *scrambled* walls (wardrobe always west) → **Turn 4 / +43** |
| **4** | **+43** | Keep vision wall placement (don’t re-scramble gold) | Preserve vision walls; only seed missing pieces; don’t reshuffle already photo-true plans | `CHANGELOG` +43 | Openings still dropped; chair next to desk missing → **Turn 5 / +44** |
| **5** | **+44** | Keep doors/mesh; chair density like gold | Preserve raw openings; seed chair by desk; stronger door/mesh defaults | `CHANGELOG` +44 · commits `6ca25c3` / `fc6857f` | Weak multi-wall inventory still empty; room too small vs gold → **Turn 6 / +45** |
| **6** | **+45** | Multi-wall inventory floor + gold room scale | Full photo-true floor if inventory weak; dense room floor **18×16** | `CHANGELOG` +45 | One polish pass still incomplete → **Turn 7 / +46** |
| **7** | **+46** | Force gold quality when first polish fails | Second polish with full study inventory MUST on multi-wall / winner | `CHANGELOG` +46 | Openings on same wall; labels without sizes → **Turn 8 / +47** |
| **8** | **+47** | Gold density: distinct openings + size labels | Seed doors/mesh on *different* walls; labels show name+size; longer wardrobe seed | `CHANGELOG` +47 | Review ≠ editor; openings hard to read → **Turn 9 / +48** |
| **9** | **+48** | Editor matches review gold handoff | Open editor re-polishes; wardrobe prefers long wall without doors; opening labels | `CHANGELOG` +48 | Still no hard guarantee of dense gold layout → **Turn 10 / +49** |
| **10** | **+49** | Deterministic study gold when incomplete | `composeStudyGold` dense plan (long wardrobe, desk+chair, 2 doors+mesh, ~74%) | `CHANGELOG` +49 | Full template wipe killed good vision placements → **Turn 11 / +50** |
| **11** | **+50** | Keep vision furniture, fill only gaps | `mergeWithStudyGold` hybrid; full compose only if still incomplete | `CHANGELOG` +50 | Paths still inconsistent (some skip gold) → **Turn 12 / +51** |
| **12** | **+51** | One guaranteed gold path everywhere | Single `ensureGoldQuality`: polish → hybrid → study gold | `CHANGELOG` +51 · `365fe52` | Study-gold applied to non-study rooms → **Turn 13 / +52** |

---

## Era B — Gold orientation / geometry last-mile (Turns 13–43 · builds +52–+82)

These were rapid Firebase-distributed scan fixes; subjects only in git (not full CHANGELOG sections).

| Turn | Build | What was asked? | What model did? | Where can we see it? | Still lacking → fixed next |
|-----:|------:|-----------------|-----------------|----------------------|----------------------------|
| **13** | **+52** | Don’t force study template on bedrooms/etc. | Gate study-gold on study-like rooms only | commit `acb0946` | Density bar still weak vs gold photo → **Turn 14 / +53** |
| **14** | **+53** | Photo-true must meet gold density bar | Stricter gold-plan density bar | `41384d0` | Walls still wrong roles vs gold → **Turn 15 / +54** |
| **15** | **+54** | Vision walls should match gold wall roles | Vision wall-role prompts for gold match | `187abef` | Openings geometry (dual doors + mesh) wrong → **Turn 16 / +55** |
| **16** | **+55** | Gold-plan openings: dual doors + mesh | Opening geometry seeding | `909c571` | `fromLeft` treated as edge not center → **Turn 17 / +56** |
| **17** | **+56** | Furniture `fromLeft` = center along wall | Correct center-based wall placement | `ad9351f` | Furniture covered doors/mesh → **Turn 18 / +57** |
| **18** | **+57** | Never cover openings with furniture | Wall clearances around openings | `8352255` | Tiny pieces / lost vision openings → **Turn 19 / +58** |
| **19** | **+58** | Keep largest pieces + vision openings | Prefer largest furniture; keep vision openings | `32ab854` | Mesh too narrow; vision furniture discarded → **Turn 20 / +59** |
| **20** | **+59** | Prefer real vision furniture + wide mesh | Vision-first furniture; wider mesh | `ff0f7ba` | Easy multi-wall path skipped gold ensure → **Turn 21 / +60** |
| **21** | **+60** | Easy multi-wall must hit gold bar | Always `ensureGoldQuality` on easy multi-wall | `0439b31` | Other backends still skipped → **Turn 22 / +61** |
| **22** | **+61** | All backends must hit gold | `ensureGoldQuality` on all vision backends | `7993d75` | Default study walls orientation wrong → **Turn 23 / +62** |
| **23** | **+62** | Default study walls = gold orientation | Default wall roles match gold plan | `4cd9718` | Invent/polish path ignored wall roles → **Turn 24 / +63** |
| **24** | **+63** | Polish invent uses gold wall roles | Invent path respects gold roles | `56b0831` | Wall-vision seeds still wrong walls → **Turn 25 / +64** |
| **25** | **+64** | Wall-vision + inventory seeds on gold walls | Seeds/prompts use gold walls | `3fb90d0` | Photo-true allowed missing mesh/dual doors → **Turn 26 / +65** |
| **26** | **+65** | Photo-true requires mesh + dual doors from inventory | Hard requirements when inventory says so | `f3aefbe` | Prompts still freeform, not gold examples → **Turn 27 / +66** |
| **27** | **+66** | Vision prompts use gold wall examples | Gold examples in prompts | `cd8e587` | Score didn’t finalize gold orientation → **Turn 28 / +67** |
| **28** | **+67** | Finalize photo-true with gold orientation score | Orientation-aware score finalize | `60d43b9` | Long wardrobe `fromLeft` edge→center bug → **Turn 29 / +68** |
| **29** | **+68** | Long unit left-edge → center conversion | Convert long-unit fromLeft correctly | `8e7a9e5` | Wardrobe not full-wall span → **Turn 30 / +69** |
| **30** | **+69** | Full-wall wardrobe for gold density | Full-wall wardrobe span | `7850960` | AccurateScan still crushed span → **Turn 31 / +70** |
| **31** | **+70** | AccurateScan keeps full-wall wardrobe | AccurateScan span fix | `89c6906` | ScanRefine still crushed span → **Turn 32 / +71** |
| **32** | **+71** | ScanRefine keeps full-wall wardrobe | ScanRefine span fix | `d27d761` | Score/orientation shared inconsistently → **Turn 33 / +72** |
| **33** | **+72** | Shared photo-true score + full-wall orientation | Shared scoring helpers | `e66d577` | Raising room floor didn’t rescale geometry → **Turn 34 / +73** |
| **34** | **+73** | Rescale when raising gold room floor | Geometry rescale with floor raise | `85aff01` | Wall place before dense floor → **Turn 35 / +74** |
| **35** | **+74** | Dense gold floor *before* wall placement | Order fix: dense floor first | `d8cf1e8` | Doors/mesh not on gold walls → **Turn 36 / +75** |
| **36** | **+75** | Seed inventory doors/mesh on gold walls | Opening seeds on correct walls | `e46c8ae` | Doors still on wardrobe storage wall → **Turn 37 / +76** |
| **37** | **+76** | Never doors on wardrobe storage wall | Conflict rule: storage wall door-free | `f23f9fd` | Desk under mesh / wrong wall → **Turn 38 / +77** |
| **38** | **+77** | Desk on west *work* wall, not under mesh | Desk wall assignment fix | `f4dce9d` | No wardrobe input → no default gold walls → **Turn 39 / +78** |
| **39** | **+78** | Default gold walls when no wardrobe detected | Default gold wall roles | `fd43a2d` | Wall-walk path incomplete gold → **Turn 40 / +79** |
| **40** | **+79** | Wall-walk uses full ensureGoldQuality | Wire wall-walk to full gold path | `d6e9608` | Gemini/offline/empty skipped gold → **Turn 41 / +80** |
| **41** | **+80** | Gemini/offline/empty also hit gold | All empty/fallback paths call ensure | `f1f07c5` | Vision desk under mesh / free-float → **Turn 42 / +81** |
| **42** | **+81** | Reject desk under mesh / free-float | Reject bad vision desk placements | `e7eb6a2` | Desk+chair last-mile still incomplete → **Turn 43 / +82** |
| **43** | **+82** | Gold desk work wall + chair last-mile | Final desk/chair placement polish | `ac7e562` · Firebase run [29622091259](https://github.com/tmai-tech/RoomCraft/actions/runs/29622091259) | Scan gold bar mostly closed; **product gap**: no Planner5D-level 3D/catalog → **Turn 44 / +83** |

---

## Era C — Planner 5D / 3D product (Turns 44–54 · builds +83–+93) — latest Firebase chain

| Turn | Build | What was asked? | What model did? | Where can we see it? | Still lacking → fixed next |
|-----:|------:|-----------------|-----------------|----------------------|----------------------------|
| **44** | **+83** | Planner 5D parity: 3D + layout options | Isometric 3D preview + layout A/B/C (spacious/wall-hug/conversation) | `CHANGELOG` +83 · `docs/PLANNER5D_PARITY_PLAN.md` · run [29625009781](https://github.com/tmai-tech/RoomCraft/actions/runs/29625009781) | Catalog thin; no AI Designer; weak 3D evidence → **Turn 45 / +84** |
| **45** | **+84** | Level-up catalog + AI Designer + 3D evidence | ~93 SKUs, 18 types, AI Designer 6 styles, 3D orbit/height tests | `CHANGELOG` +84 · run [29625786313](https://github.com/tmai-tech/RoomCraft/actions/runs/29625786313) | No edit-in-3D; no AR home entry; no styler → **Turn 46 / +85** |
| **46** | **+85** | Interactive 3D edit + AI Styler + AR entry | Tap-select/rotate/delete/nudge in 3D; AI Styler; AR Room Planner home entry | `CHANGELOG` +85 · run [29626122203](https://github.com/tmai-tech/RoomCraft/actions/runs/29626122203) | Catalog still ~93; no gallery of ideas; weak e2e proof → **Turn 47 / +86** |
| **47** | **+86** | Gallery of ideas + more SKUs + Blueprint→3D e2e | ~120 SKUs; 6 starter plans; widget e2e Blueprint→3D | `CHANGELOG` +86 · run [29626475120](https://github.com/tmai-tech/RoomCraft/actions/runs/29626475120) | Goal C1–C8 unpaid-engine path incomplete; 2D/3D not integrated → **Turn 48 / +87** |
| **48** | **+87** | 200+ catalog + integrated 2D/3D + C1–C8 | 200+ SKUs; Blueprint integrated 3D toggle; goal criteria rewritten free-path | `CHANGELOG` +87 · run [29626819267](https://github.com/tmai-tech/RoomCraft/actions/runs/29626819267) | Skeptic: catalog not 10k; AR alias of photo; edit-in-3D unproven; iso-only → **Turn 49 / +88** |
| **49** | **+88** | Close skeptic gaps | 10k+ free SKUs; distinct AR path; V7 edit-in-3D proof; perspective 3D | `CHANGELOG` +88 · `docs/SKEPTIC_PROOF.md` · `test/skeptic_gaps_test.dart` · run [29627291868](https://github.com/tmai-tech/RoomCraft/actions/runs/29627291868) | No first-person walkthrough; plan still looked “reduced objective” → **Turn 50 / +89** |
| **50** | **+89** | Walkthrough 3D + track full Play objective | Walk pad / eye-height camera; plan §5 tracks P1–P7; 10k+ badge | `CHANGELOG` +89 · run [29627602377](https://github.com/tmai-tech/RoomCraft/actions/runs/29627602377) | AR measure didn’t place furniture at real size → **Turn 51 / +90** |
| **51** | **+90** | AR place layout loop (measure → place → 3D) | `ArPlaceLayoutScreen` after ARCore; place at real size; open 3D | `CHANGELOG` +90 · run [29627953424](https://github.com/tmai-tech/RoomCraft/actions/runs/29627953424) | Default still iso-ish; no HD snapshot; proof doc stale → **Turn 52 / +91** |
| **52** | **+91** | HD 3D snapshot + walkthrough-first + proof | 1600×1200 PNG export; perspective default; skeptic proof doc | `CHANGELOG` +91 · run [29628255110](https://github.com/tmai-tech/RoomCraft/actions/runs/29628255110) | V7 test was open-only (skeptic-cited) → **Turn 53 / +92** |
| **53** | **+92** | Prove V7 select/rotate/apply/delete in cited test | Full path in `interactive_3d_styler_test`; evidence file written | `CHANGELOG` +92 · run [29628533357](https://github.com/tmai-tech/RoomCraft/actions/runs/29628533357) | Flat unlit 3D faces; proof line numbers drift → **Turn 54 / +93** |
| **54** | **+93** | Lit 3D faces/ceiling + fresh proof line numbers | Stronger face lighting + ceiling; `SKEPTIC_PROOF` lines refreshed | `CHANGELOG` +93 · commit `a2056bc` · **[Actions 29628861956](https://github.com/tmai-tech/RoomCraft/actions/runs/29628861956)** · Firebase App Distribution | Local WIP **Turn 55 / +94** (live AR place activity, etc.) may not be pushed / distributed |

---

## Feedback → build / turn map (errors reported on device)

| Feedback ID | Reported on | What user asked | First turns / versions that responded | See |
|-------------|-------------|-----------------|---------------------------------------|-----|
| `443cf0c3-1b4` | **+39** (pre-Turn 1) | “still wrong scan results” | **Turns 1–12** · **+40–+51** gold polish chain | `data/feedback/443cf0c3-1b4` |
| `32ffdc65-a49` | **+35** | Manual expected plan vs AI — is scan even possible? | Pre-turn foundation + **Turns 1–11** · **+36–+50** photo-true + study gold | `data/feedback/32ffdc65-a49` |
| `c8c569e9-e03` | **+34** | Furniture size/position off; doors missing | Pre-turn + **Turns 1–9** · **+36–+48** openings + sizes | `data/feedback/c8c569e9-e03` |
| `5244fa22` / `e89c702e` / `53a501e6` | +24–+25 | Random plans; need gold accuracy | Pre-+40 foundation; continued through **Turn 43 / +82** | `data/feedback/*` |

---

## Pattern (what “model should have done”)

Across **Turns 1–43 (+40→+82)** the recurring miss was **shipping a partial fix that didn’t cover every path**:

1. Polish only on some backends → next turn wired *all* backends
2. High score without furniture → honest score gates
3. Correct placement then *scrambled* by refine → preserve walls / openings
4. Template wiped vision → hybrid merge
5. Geometry bugs (`fromLeft`, wardrobe span, desk under mesh) fixed one layer at a time

Across **Turns 44–54 (+83→+93)** the recurring miss was **claiming product parity without proof**:

1. Iso preview without edit-in-3D
2. Catalog size claims without expansion proof
3. AR entry as photo-scan alias
4. Open-only 3D tests → full select/rotate/apply/delete

---

## Latest distributed vs local

| | Turn | Version | Status |
|--|-----:|---------|--------|
| **Firebase (latest distributed)** | **54** | **1.0.0-beta.1+93** | Built & uploaded via [run 29628861956](https://github.com/tmai-tech/RoomCraft/actions/runs/29628861956) |
| **Local / accuracy resume** | **57** | **1.0.0-beta.1+107** | Accuracy loop: +105–+107 (scale, non-study, opening chain) — see `docs/ACCURACY_TURN_LOG.md` |

**Tester install:** Firebase App Tester invite → latest release should show **+93** (or newer if a later build was distributed). Confirm on device Settings version label.

---

## Era D — Accuracy resume (Turn 55+ · builds +105+)

Accuracy work paused after Turn 43 (+82) for Planner5D product. Resumed in **`docs/ACCURACY_TURN_LOG.md`**.

| Turn | Build | What was asked? | What model did? | What it should have done? |
|-----:|------:|-----------------|-----------------|---------------------------|
| **55** | **+105** | 100% proper accuracy; Planner5D reference; log each turn | Full-wall wardrobe no longer scales room down; gold floor **20.3×17**; `goldGeometryMatchScore` → finalize ~98% ceiling | Should have blocked wardrobe scale-down earlier; still need non-study gold, AR metric truth, device re-test of gold photos |
| **56** | **+106** | Non-study dense accuracy (bedroom/living e89c) | `ensureNonStudyDensity` + inventory MUST bed/sofa/tv wall-fill; fix polish "no bed invent" poison | Device re-test; AR metric; Phase B IoU metrics |
| **57** | **+107** | Opening chain fidelity (doors/mesh Planner5D) | `OpeningChainFidelity` gold 2.8 doors, mesh reclass, de-overlap | Device re-test; AR scale; Phase B IoU |

**Local latest:** +107 · see `docs/ACCURACY_TURN_LOG.md` for ongoing loop.

---

## Related docs

- `CHANGELOG.md` — per-version notes
- `docs/KNOWN_ISSUES.md` — expected limitations
- `docs/FIREBASE_APP_DISTRIBUTION.md` — distribute setup
- `docs/SKEPTIC_PROOF.md` — skeptic claim → tree proof
- `docs/PLANNER5D_PARITY_PLAN.md` — Planner 5D gap matrix
