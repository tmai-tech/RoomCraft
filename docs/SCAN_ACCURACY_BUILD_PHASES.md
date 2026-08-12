# Scan accuracy & blueprint fidelity — build phases

**Date:** 2026-08-12  
**Baseline build:** `1.0.0-beta.1+148`  
**Reference product:** [Planner 5D](https://play.google.com/store/apps/details?id=com.planner5d.planner5d) (Home Scan + floor plan + 3D)  
**Goal:** Scan → plan quality that a normal person trusts for furniture layout (size + walls + openings + pieces), not LiDAR CAD.

---

## 1. Status snapshot (where we are)

### What ships today (+144)

| Layer | Capability | State |
|-------|------------|-------|
| **AR size** | Easy walk-to-map (floor hits + pose trail + plane extents) | ✅ Shipped (+125–+138) |
| **AR size** | Wall-distance lock, path-expand, pose drift cap, reject weak ~10×10 | ✅ Shipped (+134–+139) |
| **AR size** | User **confirm/edit W×L** before plan (tape override) | ✅ Shipped (+137–+138) |
| **AR size** | PointCloud densify; conditional Depth API; Open3D export | ✅ Shipped (+130–+131) |
| **AR camera** | SceneView live feed (black/flip bugs fixed on +120–+123) | ✅ Shipped (device QA still needed) |
| **Inventory** | After walk: mark 2 doors / French window / desk / table / bean bag | ✅ Shipped (+140–+142) |
| **Photos** | Multi-gallery photo-true + study gold (+36 density path) | ✅ Restored (+143–+144) |
| **Blueprint 2D** | Walls, doors, windows, furniture, snap, score, heatmap | ✅ Strong |
| **Blueprint view** | Fit-to-screen + Fit button (out-of-screen plans) | ✅ Shipped (+139) |
| **3D / viz** | Isometric + perspective walkthrough, not photoreal mesh | ✅ Partial vs Planner5D |
| **Metrics** | Phase B room%/door MAE/furniture recall + training JSONL | ✅ Scaffolded (+108–+110) |

### Latest field feedback (still not “up to mark”)

| Feedback | On build | User said | Root issue class |
|----------|----------|-----------|------------------|
| `be325971` | +142 | “worse than 36” | Sparse / wrong density vs study gold (mitigated +143–+144; **no retest yet**) |
| `04919d14` | +139 | 2 doors, French window, desk, table, bean bag don’t match | Inventory placement fidelity (fixed +140–+142; **no retest on +144**) |
| `7f07625b` | +138 | Plan off-screen; AR ~30×26 ft | Pose drift + viewport (fixed +139) |
| `71c6e9b6` | +136 | “plan wrong” | Generic accuracy fail |
| `225fb5de` | +132 | Open walls / sparse ~10×10 | Incomplete walk accepted as done (hardened +133–+138) |
| `e7b247fd` | +123 | AR not accurate / not easy / empty floor plan | Easy walk + inventory path built after this |
| `a41da384` / `e43505bf` | +119–+121 | Black / flipping AR camera | SceneView rewrite (+122–+123) |

**Honest read:** Unit tests and gold identity pass for **known study** photos and **synthetic** inventory. Live device loop still reports wrong plans — last negative was on **+142**, and **+144 has no new feedback yet**. Accuracy is not closed until field retest on the same rooms.

### Scorecard vs Planner 5D (2026-08 re-score)

| Dimension | Planner 5D | RoomCraft +144 | Gap to close |
|-----------|------------|----------------|--------------|
| **Metric room size (AR walk)** | 7/10 Home Scan (cloud polish; iOS LiDAR better) | **5–6/10** (on-device fuse + confirm; still drifts / under-sizes without full loop) | Coverage coaching + wall lock + offline RANSAC polish |
| **Walls / closed outline** | 8/10 | **6/10** (always seal 4 walls; weak non-rect) | L / multi-polygon from walk cloud |
| **Openings (doors/windows)** | 7/10 Pro scan | **4/10** (chain priors + inventory chips; little true detection from AR) | Vision+AR opening place after walk |
| **Furniture from scan** | 7/10 Pro catalog match | **4/10** (inventory chips or photo gold; AI fill still random-feeling) | Photo inventory auto after AR size lock |
| **Blueprint 2D readability** | 9/10 | **8/10** (+148 gaps + inward swings + opening labels; edge dims A–D) | North-up editor flip; 3D toggle polish |
| **3D / blueprint “wow”** | 9/10 | **7/10** (isometric + walkthrough; not HD mesh) | Optional textures; keep free painter path |
| **Layout intelligence** | 5/10 | **8–9/10** | Keep as wedge |
| **Ease of scan (consumer)** | 7/10 (walk video 10s–12m) | **6/10** (one-button walk; still needs coaching) | Single guided path, fewer modes |
| **Honest confidence** | 5/10 | **8/10** | Keep |

**Product wedge (unchanged):** free scan → trustworthy top-down → **layout intelligence**. Do **not** chase photoreal restyle first.

**What Planner 5D does that we still do not:**

1. **Cloud reconstruction** of continuous walk video → polished Basic/Pro plan (minutes).  
2. **iOS LiDAR** parametric walls + furniture.  
3. **Catalog match** of detected furniture to thousands of SKUs in Pro scan.  
4. **HD realistic 3D** snapshots as a core sell.

**What we already match or beat free:**

1. On-device ARCore walk without account paywall for basic size.  
2. Layout score / clearances / spacious arrange / A-B-C alternatives.  
3. User-confirm size + Phase B metrics + training export for continuous improvement.

---

## 2. Failure modes to kill (priority order)

1. **Wrong room size** after walk (under-size 10×10, over-size 30×26).  
2. **Wrong openings** (door mid-wall, table in door swing, missing French window).  
3. **Wrong / random furniture** (AI living fill instead of what is in the room).  
4. **Sparse vs dense** (study gold quality regressing vs +36).  
5. **Blueprint hard to read** (off-screen, south-up confusion, open wall gaps).  
6. **AR camera dead** on some OEMs (regression risk).

---

## 3. Build phases

Phases are **sequential for exit criteria**, but engineering can overlap when marked parallel.

### Phase 0 — Field truth gate (1–2 days) · *do first*

**Goal:** Stop guessing; know if +144 is better than the last bad reports.

| # | Deliverable | Exit criteria |
|---|-------------|----------------|
| 0.1 | Distribute **+144** (or next) to testers group | Firebase release live |
| 0.2 | Retest script: same rooms as `04919d14`, `be325971`, `32ffdc65` | Written pass/fail per room |
| 0.3 | Paths: (A) Photos multi-select study gold · (B) AR walk → confirm size → lounge inventory · (C) AR walk → study gold preset | Screenshots + reported W×L |
| 0.4 | Tape or laser one room as ground truth | Size error % logged |

**Exit:** Decision — *ship path A/B/C as default* or *Phase 1 size fixes required*.

---

### Phase 1 — Metric size reliability (Planner5D Home Scan Basic) · ~1 week

**Goal:** After a normal wall-loop walk + optional confirm, room W×L is within **±10%** of tape on residential rooms (target; ±15% hard floor).

| # | Deliverable | Notes |
|---|-------------|-------|
| 1.1 | **Coverage-first Done** | Refuse Done if angular cover & path length fail; coach “walk remaining walls” in plain language |
| 1.2 | **Wall-pair lock v2** | Prefer anti-parallel vertical planes + depth range when available; fuse with pose standoff |
| 1.3 | **Drift hard limits** | Keep residential cap; show “size looks large — measure one wall” when consistencyError high |
| 1.4 | **One-wall calibrate** | After walk, user can set *one known wall length* → scale both axes proportionally (magicplan-class) |
| 1.5 | **Offline polish hook** | Export floor XYZ/PLY already exists — optional Colab Open3D RANSAC re-fit; surface “server polish later” only if needed |
| 1.6 | Metrics | Log `room_size_error_pct` vs confirm/tape in Phase B export |

**Exit:** 3+ rooms, median |size error| ≤ 10% after confirm; no silent 10×10 or 30×26 without warning.

---

### Phase 2 — Openings + inventory fidelity (Planner5D Pro content lite) · ~1–1.5 weeks

**Goal:** Plan contains the **same openings and furniture types** the user saw/marked, placed on correct walls / mid-room rules — not random AI living fill.

| # | Deliverable | Notes |
|---|-------------|-------|
| 2.1 | **Post-size inventory mandatory** | After confirm size, always mark contents (or run photo inventory); no empty “box only” default |
| 2.2 | **Opening chain from photos** | After AR size lock, 1–4 wall photos → door/window fromLeft + width; keep inventory counts as hard constraints |
| 2.3 | **Door keep-out always** | Table/desk never in swing; Review + editor sanitize (already partial — make default for all paths) |
| 2.4 | **French window / mesh** | Inventory chip → correct opening type + width prior (not door) |
| 2.5 | **Placement rules table** | Desk wall-hug NW/work; coffee mid-room; bean bag clear SE; dual doors gold fromLeft when inventory says 2 doors |
| 2.6 | **No study-gold poisoning** | Lounge / bedroom / study presets never cross-contaminate (regression suite for `04919d14` + `32ffdc65`) |
| 2.7 | **Match score UI** | Review shows “2 doors · 1 French window · 3 furniture — all placed” checklist before editor |

**Exit:** `04919d14` inventory reproduces on device; study photos keep +36 density; type recall ≥ 0.9 on labeled cases.

---

### Phase 3 — Blueprint visualization parity (Planner5D floor plan bar) · ~1 week

**Goal:** Top-down plan is immediately readable and editable like a consumer floor-plan app.

| # | Deliverable | Notes |
|---|-------------|-------|
| 3.1 | **Always fit-on-open** | Whole room visible; Fit control obvious |
| 3.2 | **Dimension strings** | W×L on edges; opening widths labeled in ft |
| 3.3 | **Door swing arcs + window light** | Already partial — default on for scan-sourced plans |
| 3.4 | **North-up + wall labels A–D** | Consistent with Review N↑ |
| 3.5 | **Closed walls + thickness** | No open corners; optional double-line wall |
| 3.6 | **Furniture labels** | Catalog name on piece (bean bag not “chair”) |
| 3.7 | **3D toggle polish** | One tap 2D ↔ isometric/perspective; same furniture positions |

**Exit:** Side-by-side screenshot vs Planner5D 2D plan of same room is “same job done” (not same polish). Tester can understand openings without training.

---

### Phase 4 — Unified scan UX (one happy path) · ~3–5 days

**Goal:** One primary flow; hide expert modes.

```
Home → Scan the room
  → AR walk (size fills in, coach cover)
  → Confirm / edit size (or one-wall calibrate)
  → Mark contents OR add wall photos
  → Review checklist + score
  → Blueprint (edit) → 3D / arrange / export
```

| # | Deliverable |
|---|-------------|
| 4.1 | Single CTA; Photos and Draw as secondary |
| 4.2 | Live mini-map during walk (already partial) + finish criteria in words |
| 4.3 | Remove mode confusion (auto / multi-dot / chain buried under Advanced) |
| 4.4 | AR camera health: if black >3s, actionable help (Play Services for AR) |

**Exit:** New tester completes scan → blueprint in one session without reading docs.

---

### Phase 5 — Any-room generalization (not only gold rooms) · ~2 weeks

**Goal:** Bedroom / living / office without template collapse.

| # | Deliverable |
|---|-------------|
| 5.1 | Room-type classifier from inventory + photos (study / bedroom / living / lounge) |
| 5.2 | Dense fill only for missing *plausible* pieces, never invent against inventory |
| 5.3 | L-shape / polygon floor from walk cloud when non-rect coverage |
| 5.4 | Multi-room later (v2) — single room first |

**Exit:** Two non-study rooms pass field checklist with type recall ≥ 0.8 and size error ≤ 15%.

---

### Phase 6 — Continuous accuracy system (training loop) · ongoing

| # | Deliverable |
|---|-------------|
| 6.1 | Every editor Save → `corrected_gold_pair` uploaded (opt-in) or exported |
| 6.2 | Dashboard: median size error, door MAE, furniture center MAE by build |
| 6.3 | Colab benchmark on feedback packs (`experiments/colab`) as regression gate before distribute |
| 6.4 | Optional cloud Home Scan polish (Planner5D-class) only after on-device Phase 1–2 exit |

**Exit:** Each build has a numeric accuracy delta vs previous on fixed gold set.

---

## 4. Explicit non-goals (this roadmap)

| Out | Why |
|-----|-----|
| Photoreal HD mesh / path-traced render | Planner5D paid pillar; not accuracy |
| 10k brand commerce SKUs | Catalog free expansion already exists |
| iOS LiDAR RoomPlan | Android-first; later |
| Full multi-building exterior suite | After single-room trust |
| Claiming photo-only = survey grade | Industry-false |

---

## 5. Suggested execution order (next 3–4 weeks)

| Week | Focus | Build target |
|------|--------|--------------|
| **W0** | Phase 0 field retest of +144 | Decision memo |
| **W1** | Phase 1 size reliability + 1.4 one-wall calibrate | +145–+148 |
| **W2** | Phase 2 openings + inventory + match checklist | +149–+152 |
| **W3** | Phase 3 blueprint viz + Phase 4 unified UX | +153–+156 |
| **W4+** | Phase 5 any-room + Phase 6 metrics gate | +157+ |

**Default product path after Phase 4:**  
**AR walk → confirm size → inventory/photos → Review checklist → Blueprint.**  
Photos-only remains available for the known study gold path.

---

## 6. Definition of done (accuracy era)

Accuracy work is **done** when **all** of:

1. Field: same rooms as last three negative feedbacks pass “looks right” without developer on device.  
2. Size: median |error| ≤ 10% vs tape after confirm on ≥5 rooms.  
3. Inventory: exact type counts place correctly; no table-in-door.  
4. Blueprint: full room visible, dimensions, closed walls, labeled openings.  
5. Regression: gold study + lounge inventory unit tests green on every build.  
6. Score: Review confidence honest (AR measured vs photo estimate) — no fake 100% on gallery-only.

Until then, continue the accuracy turn log (`docs/ACCURACY_TURN_LOG.md`) after each ship.

---

## 7. Related docs

| Doc | Role |
|-----|------|
| `docs/ACCURACY_TURN_LOG.md` | Turn-by-turn what shipped |
| `docs/Scan-Precision-Research.md` | Why photos fail; Planner5D Home Scan research |
| `docs/PLANNER5D_PARITY_PLAN.md` | Full product parity (3D, catalog, AR place) |
| `docs/CONSUMER_SCAN_AND_TRAINING.md` | Easy scan + Phase A–D training |
| `docs/KNOWN_ISSUES.md` | User-facing limitations |
| `data/feedback/` | Device reports + gold rooms |

---

## 8. Immediate next action

1. **Run Phase 0** on build **+144** (or distribute if testers still on older build).  
2. From results, start **Phase 1.1–1.4** (coverage Done + one-wall calibrate) — highest leverage for “AR scan not up to mark.”  
3. Parallel: freeze **regression tests** for `04919d14` inventory + `32ffdc65` study gold so density never regresses again (“worse than 36”).
