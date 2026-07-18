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

## 5. Success criteria for “Planner 5D level” *for our wedge*

**Product-level** means users can do the Planner 5D *job* on free/current architecture:

1. Scan / AR measure / enter room size **without** pasting API keys.  
2. Edit a real 2D plan with snap, multi-select, doors, score.  
3. **AI Designer auto-furnish** empty rooms (6 styles) + **AI Styler** tips.  
4. Pick among **3 layout alternatives** and undo.  
5. Open **interactive 3D editor** (select/rotate/delete/nudge, apply to plan).  
6. **Gallery of ideas** starter plans + catalog ≥100 SKUs / ≥18 types.  
7. Export PNG/PDF and Firebase App Distribution build.

**Explicitly not required for this milestone** (paid Planner stack): 10,000 brand SKUs, photoreal HD, mesh walkthrough CAD.

---

## 6. Verification plan

| Step | Observation | Evidence artifact |
|------|-------------|-------------------|
| `flutter test test/blueprint_e2e_path_test.dart` | All green | test output |
| Catalog scale | skus≥100, types≥18 | evidence/catalog_product_scale.txt |
| Blueprint → 3D | tap tooltip “3D preview” opens `IsometricPreviewScreen` | evidence/blueprint_to_3d_path.txt |
| Compare layouts UI | Auto → Compare → apply → undo | evidence/compare_layouts_ui_path.txt |
| AI Designer auto-furnish | empty room → ≥5 pieces | evidence/ai_designer_autofurnish.txt |
| Gallery of ideas | 6 sample plans materialize | evidence/gallery_of_ideas.txt |
| CI distribute | Build APK → Firebase testers | Actions + console URLs |


---

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

**Honest scorecard after +84:** catalog **6/10** · layout intelligence **9/10** · 3D wow **5.5/10** · free scan **8.5/10**.  
Still not a clone of Planner 5D’s paid 3D/AR stack — competitive on the **measured layout + AI furnish** job with free resources.


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
