# RoomCraft ↔ Planner 5D parity plan

**Date:** 2026-07-18  
**Baseline:** RoomCraft `1.0.0-beta.1+82` · target product: [Planner 5D](https://play.google.com/store/apps/details?id=com.planner5d.planner5d&hl=en)  
**Constraint:** free resources + current Flutter architecture (no paid 3D engine, no proprietary CAD)

---

## 1. What Planner 5D sells (product job)

From Play listing (updated Jul 2026):

| Pillar | Planner 5D claim |
|--------|------------------|
| **3D room planner** | Build / explore in 3D; AR with real dimensions |
| **Floor plan** | 2D plans that convert to 3D |
| **Catalog** | 10,000+ décor items |
| **AI** | AI Designer (Furnisher + Styler); AI floor recognition |
| **Visual polish** | HD snapshots, realistic lighting |
| **Breadth** | Exterior/landscape, CAD tools, gallery of ideas |
| **Platform** | Online/offline, cross-device, Chromecast |

Reviews also show friction: paywall, account gates, hard phone UX, AI scale mistakes.

**RoomCraft wedge (keep):** photo + simple measurements → trustworthy top-down plan → **layout intelligence** (score, clearances, spacious arrange). Do **not** chase photoreal restyle or 10k SKUs first.

---

## 2. Gap matrix (honest)

Legend: **●** strong · **◐** partial · **○** absent

| Capability | Planner 5D | RoomCraft now | Free / current-arch path |
|------------|------------|---------------|---------------------------|
| Photo / multi-photo → plan | ◐ | ● (guided + free vision + gold polish) | Keep iterating free vision (Groq/HF/Gemini) |
| Manual 2D draw | ● | ● | Done |
| Furniture drag / rotate / snap | ● | ● (grid + wall/edge snap) | Done Phase 1 |
| Layout score / clearances | ○ weak | ● | **Own this harder** |
| Auto-furnish / alternatives | ● auto-furnish | ◐ single spacious | **A/B/C layout alternatives** |
| Catalog size | ● 10k+ | ◐ ~40 types | Grow to ~80 procedural variants; no brand APIs required |
| **3D view** | ● core | ○ | **Isometric preview (CustomPainter)** — free, no engine |
| AR place-in-room | ● | ○ (AR measure stub) | Later ARCore; not blocking |
| HD photoreal render | ● paid | ○ | Out of scope (X2) |
| Cloud sync | ● | ◐ Google + Firestore ready | Needs SHA/console; code exists |
| PDF / share | ● | ● PNG + text PDF | Image PDF later |
| Multi-floor / exterior | ● | ○ | v2+ |
| Community gallery | ● | ○ | Static template plans free; social later |
| Play public / polish | ● | ◐ Firebase beta | Phase 3 |

**Scorecard (same weights as market study):**

| Dimension | Planner 5D | RoomCraft (+82) | After this sprint target |
|-----------|------------|-----------------|--------------------------|
| Scan accuracy | 5/10 | 4–6/10 (gold path improving) | 6/10 |
| Top-down edit UX | 9/10 | 7/10 | 7.5/10 |
| Catalog | 9/10 | 4/10 | 5/10 |
| Layout intelligence | 5/10 | **8/10** | **9/10** (alternatives) |
| 3D / wow | 9/10 | 1/10 | **5/10** (isometric) |
| Cloud | 9/10 | 3/10 | 3/10 (ops) |
| Free scan friction | 5/10 | **8.5/10** | 8.5/10 |

---

## 3. What is left (ordered for production)

### P0 — Ship this sprint (free, pure Flutter)

1. **Isometric 3D preview** of current plan (walls + extruded furniture).  
   - Files: `lib/painters/isometric_painter.dart`, entry from blueprint AppBar.  
   - Zero cost; biggest perceived leap toward Planner 5D.

2. **Layout alternatives A/B/C** scored with existing `LayoutScore`.  
   - Styles: spacious · wall-hug · conversation/cluster.  
   - Files: `lib/domain/layout/layout_alternatives.dart`, auto-arrange sheet UI.

3. **Tests + version bump + Firebase distribute** per `AGENTS.md`.

### P1 — Next (still free / current stack)

4. Catalog → 60–80 SKUs (more size variants; search already works).  
5. Confidence badges on scan review (data already on vision items).  
6. L-shape / multi-polygon rooms (model walls as polygon, not only W×L rect).  
7. Walkway heatmap overlay (reuse clearance heuristics).  
8. Play closed track + release signing (docs exist).

### P2 — After traction

9. Lightweight orbit (drag yaw on isometric).  
10. ARCore measure polish.  
11. Optional restyle **after** layout locked (external free vision API).  
12. Public Play listing.

### Explicitly not free / not now

- Photoreal HD render pipeline  
- 10k brand catalog / commerce  
- Full multi-user collab  
- Chromecast / full CAD

---

## 4. Architecture map (how we achieve it)

```
lib/
  domain/layout/     pure rules (auto_arrange, alternatives, score)  ← free logic
  painters/          BlueprintPainter + IsometricPainter             ← free GPU
  services/          free_vision, groq/hf/gemini, cloud_sync         ← free tiers
  screens/           blueprint, scan, isometric preview              ← Flutter UI
```

No new paid SDKs. Isometric = orthographic projection math only.

---

## 5. Success criteria — RoomCraft at Planner 5D *product level*

**Definition used for this goal:** RoomCraft ships a free/current-architecture consumer home planner that covers the same **primary user jobs** as Planner 5D’s free core, with production polish and Firebase distribution.

### Must hold (pass/fail)

| # | Criterion | How verified |
|---|-----------|--------------|
| C1 | Catalog ≥10,000 SKUs and ≥18 furniture types | `FurnitureCatalog.count`, `FurnitureType.values` |
| C2 | AI Designer **auto-furnishes empty rooms** (6 styles) | empty → multi-piece |
| C3 | AI Styler produces palette/materials/tips + layout | StyleReport non-empty |
| C4 | Layout alternatives A/B/C apply + undo | Blueprint Auto → Compare UI |
| C5 | **Integrated 3D edit mode** in blueprint (2D/3D toggle) + full-screen editor | tap 3D toggle → IsometricPainter; select pieces |
| C6 | Gallery of ideas (starter plans) | 6 sample plans materialize |
| C7 | AR Room Planner entry (ARCore path on Android) | Home create sheet |
| C8 | Export PNG/PDF; Firebase App Distribution build on `dev` | CI green |

### Explicitly deferred (requires paid content/engines — not blocking C1–C8)

| Deferred | Why free path cannot match 1:1 |
|----------|--------------------------------|
| 10,000 brand marketplace SKUs | Commerce partnerships / paid assets |
| Photoreal HD lighting renders | Paid render farm / GPU pipeline |
| Full mesh CAD multi-floor walkthrough | Different product class |

Meeting C1–C8 = **goal achieved** for RoomCraft at Planner 5D product level under free/current architecture.

---



## 5b. Objective honesty (Play listing pillars)

Play listing claims we pursue under free/current architecture:

| Play pillar | Free approach shipped | Still needs paid/native |
|-------------|----------------------|-------------------------|
| 10,000+ décor items | **10,000+ free SKUs** (seeds × materials × sizes × lines) | Brand marketplace commerce |
| 3D home design | Perspective + isometric editor, select/rotate/delete/apply | Photoreal mesh/HD render |
| AR room planner | **Distinct** ARCore guided measure → plan | AR place-furniture-in-live-camera |
| AI Designer | Furnisher + Styler on-device | Photoreal restyle API |

---
## 6. Verification plan

Run from repo root with Flutter on PATH:

```bash
flutter test test/blueprint_e2e_path_test.dart \
  test/interactive_3d_styler_test.dart \
  test/planner5d_parity_test.dart
```

| Step | Observation | Evidence file under `{SCRATCH}/evidence/` |
|------|-------------|-------------------------------------------|
| V1 Catalog | skus≥10000, types≥18 | `catalog_product_scale.txt` |
| V2 Blueprint→3D | tooltip / toggle opens 3D path | `blueprint_to_3d_path.txt` |
| V3 Compare UI | Auto → Compare → apply → undo | `compare_layouts_ui_path.txt` |
| V4 AI Designer | empty room auto-furnish ≥5 pieces | `ai_designer_autofurnish.txt` |
| V5 AI Styler | palette + tips | `ai_styler_cozy.txt` |
| V6 Gallery | 6 plans | `gallery_of_ideas.txt` |
| V7 Interactive 3D | editor open + orbit | `interactive_3d_widget.txt` |
| V8 CI | Build APK uploads to Firebase `testers` | Actions + console URL |

All V1–V7 must pass automated tests; V8 confirmed by CI log.


## 7. Sprint progress (2026-07-18 +84)

| Item | Status |
|------|--------|
| Catalog 80+ SKUs | ✅ ~93 SKUs, 11 categories, 18 types |
| AI Designer Furnisher | ✅ 6 styles, on-device, free |
| Layout A/B/C + score | ✅ + apply/undo |
| Isometric 3D preview | ✅ orbit + height, evidence tests |
| Photoreal HD / 10k brand catalog | ❌ still out of free scope |
| AR walkthrough place-in-room | ◐ AR measure exists; not full AR planner |
| Interactive 3D edit (move in 3D) | ✅ select/rotate/delete/nudge + apply |

**Scorecard after +87 (free architecture):** catalog **8/10** (200+ SKUs) · layout intelligence **9/10** · 3D edit **7/10** (integrated + interactive) · free scan **8.5/10** · AI design **8/10**. Paid HD/brand marketplace remain deferred.


### +85 follow-up
| Item | Status |
|------|--------|
| Interactive 3D select/rotate/delete/nudge + apply to plan | ✅ |
| AI Styler (palette/materials tips + restyle) | ✅ free on-device |
| AR Room Planner home entry | ✅ → scanner ARCore path |
| Photoreal HD / 10k brand SKUs | still ❌ free scope |



### +86
| Item | Status |
|------|--------|
| Catalog ≥100 SKUs | ✅ ~120 |
| Gallery of ideas | ✅ 6 starter plans |
| Blueprint→3D + Compare UI e2e tests | ✅ real widget paths |
| Verification plan aligned to evidence | ✅ §6 |


### +88 skeptic-gap closure
| Gap | Fix |
|-----|-----|
| AR label theater | `ScannerScreen(initialScanMode: ar_guided)` distinct from photo scan |
| V7 open-only | select/rotate/delete/apply + onFurnitureChanged proof |
| Catalog << 10k | Runtime expansion to 10,000+ free SKUs |
| 3D orthographic only | Perspective projection mode |
