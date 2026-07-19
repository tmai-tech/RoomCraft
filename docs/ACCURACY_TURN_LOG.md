# Accuracy turn log (RoomCraft)

**Goal:** 100% *proper* accuracy for scan → plan (photo-true inventory + gold geometry fidelity).  
**Reference:** Planner 5D — real dimensions, wall-anchored furniture, labeled openings, no random free-XY scatter. Photos alone never match LiDAR; we maximize structural match + honest scores.

**Formula (accuracy era resume):** after product Turns 44–54 (+83–+104), accuracy resumes at **Turn 55 / +105**.

| Column | Meaning |
|--------|---------|
| **Turn** | Sequential accuracy fix turn |
| **Build** | `1.0.0-beta.1+N` |
| **What was asked?** | User / loop request |
| **What model did?** | What shipped |
| **What it should have done?** | Honest gap / ideal next step |

---

## Era D — Accuracy resume (Turn 55+)

| Turn | Build | What was asked? | What model did? | What it should have done? |
|-----:|------:|-----------------|-----------------|---------------------------|
| **55** | **+105** | Resume accuracy toward 100% proper; use Planner5D as reference; after each turn log What was asked / What model did / What it should have done | (1) Stop AutoScale from shrinking rooms when vision reports a **full-wall wardrobe ≥7 ft** (6.5 ft freestanding prior was crushing gold 20×17 plans — Planner5D treats wall units as fixed, not scale-down anchors). (2) Gold room floor **20.3×17.0** matching feedback `32ffdc65` manual plan. (3) **`goldGeometryMatchScore`** (room size, wardrobe span, work-wall desk, dual doors, mesh, chair) blended into photo-true finalize → score up to ~**98%** when structure matches gold (honest ceiling; not LiDAR 100%). Tests +105 green. | **Should have done earlier:** treat wall-spanning wardrobes as non-scale anchors from the first gold density work (+53), not only after 43 study-template turns. **Still lacking for true ~100%:** (a) device re-test of same gold photos on +105; (b) bedroom/living dense gold when inventory has bed/sofa (study-only template); (c) AR/tape scale for metric truth; (d) Phase B labeled error metrics (door IoU, room % error) vs heuristic score; (e) multi-view depth / wall polygon like Planner5D AI floor recognition. **Next turn priority:** non-study inventory dense fill OR live gold-photo regression if vision fixtures available. |
| **56** | **+106** | Continue accuracy loop; next highest-impact gap after +105; Planner5D reference; log turn | **Non-study dense gold** for bedroom/living (e89c quality class). (1) `ensureNonStudyDensity` + `composeNonStudyGold` / `mergeWithNonStudyGold` — wall-anchored bed@N wardrobe@S sofa@W tv@E + doors. (2) Pending-inventory gate so polish wardrobe+table cannot early-accept study photo-true when MUST bed/sofa/tv missing. (3) Inventory parse: polish note "no bed invent" no longer forbids bedroom — `must include bed` wins. Dense score **72–84%**. Tests +106 green. | **Should have done:** never treat study photo-true as complete when inventory lists bed/sofa/tv (bug since polish confidence notes said "no bed"). **Still lacking:** (a) device re-test gold photos on +106; (b) AR/tape metric scale; (c) Phase B labeled IoU metrics; (d) bedroom openings can still conflict with dense multi-piece clearances on tight rooms; (e) Planner5D multi-view wall polygon. **Next turn priority:** door/window chain fidelity vs gold photos OR AR scale lock confidence. |
| **57** | **+107** | Next accuracy gap: door/window chain fidelity (Planner5D reference) | **`OpeningChainFidelity`** module: (1) snap walk-through doors to gold **2.8 ft**; (2) reclassify ≥4.5 ft “doors” as mesh when inventory wants balcony; (3) de-overlap same-wall openings; (4) seed missing doors/mesh from inventory counts; (5) blend opening fidelity into finalize score. Wired study + non-study paths. Default door prior 2.8. Tests +107 green. | **Should have done:** treat openings as designer wall-chains from first multi-wall work (+29), not only furniture gold. **Still lacking:** (a) device re-test gold photos on +107; (b) AR/tape metric room scale; (c) Phase B door IoU vs user-corrected plans; (d) multi-view wall polygon. **Next turn priority:** AR scale lock confidence OR Phase B labeled metrics scaffolding. |
| **58** | **+108** | AR scale lock confidence + Phase B metrics (next after +107) | (1) **`ScaleLockConfidence`** — tape/AR/photo floors; blend into score. (2) **`ScanRefine.lockSize`** preserves measured floor, runs opening fidelity, softer footprint scale. (3) **`PlanAccuracyMetrics`** Phase B: room size error %, door MAE, furniture type recall, center MAE, composite vs reference gold. Wired Review AR refine + scanner AR path. Tests +108: gold-vs-gold high, thin-vs-gold low, AR lock ≥90%. | **Should have done:** separate measured-scale trust from photo layout confidence when AR landed (+15). **Still lacking:** (a) device re-test gold photos; (b) wire metrics into training export JSONL on feedback; (c) live user-corrected plan IoU in app UI; (d) multi-view wall polygon. **Next turn priority:** training-export metrics on feedback OR Review UI “vs gold” diagnostics. |
| **59** | **+109** | Wire Phase B into training export + Review diagnostics | (1) **JSONL v2** feedback/snapshots carry `phase_b` (composite, door MAE, type recall, opening fidelity, scale source, room type) + plan geometry. (2) **`syntheticReference` / `diagnosticsJson` / `planToJson`**. (3) Review shows “Phase B vs template …” under confidence; feedback snackbar includes metrics. Tests +109 green. | **Should have done:** log dimension errors with first training export (+16), not only rating chips. **Still lacking:** (a) device re-test gold photos on +109; (b) user-corrected editor plan as reference (not only synthetic template); (c) multi-view wall polygon; (d) server-side training pipeline. **Next turn priority:** editor handoff snapshot as corrected gold reference OR multi-view wall polygon research spike. |
| **60** | **+110** | User-corrected editor plan as Phase B gold reference | (1) **`ScanParser.fromEditor`** reverse of toEditor. (2) **`ScanTrainingSession`** predicted → review → editor. (3) Blueprint Save/pop logs **`corrected_gold_pair`** (predicted vs user gold) with `vs_user_corrected` + geometry JSON. (4) Phase B schema **v2** when user gold present. Tests +110: round-trip, pair diagnostics. | **Should have done:** treat editor corrections as labels from first training export. **Still lacking:** (a) device re-test gold photos; (b) multi-view wall polygon; (c) auto-upload training pairs; (d) UI badge “model error vs your edit”. **Next turn priority:** multi-view wall polygon OR Review badge for vs_user_corrected. |

---

## Prior eras (summary)

| Era | Turns / builds | Outcome |
|-----|----------------|---------|
| A Photo-true gold | 1–12 / +40–+51 | `ensureGoldQuality` all backends |
| B Geometry last-mile | 13–43 / +52–+82 | Desk/chair/openings/wardrobe span |
| C Planner5D product | 44–54 / +83–+104 | 3D, catalog, AR place — **not** scan accuracy |
| D Accuracy resume | 55+ / +105+ | Geometry → openings → AR scale → Phase B → user gold pairs |

Full product retro: `docs/RELEASE_RETRO_40_93.md`.

---

## Planner5D accuracy reference (what “good” means)

| Planner5D behavior | RoomCraft now (+110) | Gap |
|--------------------|----------------------|-----|
| Walls from AR / user measure | AR/tape scale lock floors confidence honestly | Photo path still estimate |
| Furniture catalog fixed sizes | Catalog + wall-anchor | Good |
| No free-float random XY | Wall-relative + gold ensure | Good for study + non-study |
| Opening widths labeled | Opening chain → gold 2.8 ft doors + mesh span | Device proof still open |
| Room size trustworthy | Measured scale floor + gold floor for photo | Device AR re-test open |
| Multi-room types | Study gold + bedroom/living density (+106) | Device proof still open |
| Honest confidence | Phase B template + **user-corrected gold pairs** on editor save | Multi-view polygon; server training |

---

## Related

- Feedback gold: `data/feedback/32ffdc65-a49`, `e89c702e-7e4`, `c8c569e9-e03`
- Code: `lib/domain/photo_true_layout.dart`, `lib/domain/auto_scale.dart`
- Tests: `test/photo_true_layout_test.dart`, `test/auto_scale_wardrobe_test.dart`
