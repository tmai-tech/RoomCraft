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

---

## Prior eras (summary)

| Era | Turns / builds | Outcome |
|-----|----------------|---------|
| A Photo-true gold | 1–12 / +40–+51 | `ensureGoldQuality` all backends |
| B Geometry last-mile | 13–43 / +52–+82 | Desk/chair/openings/wardrobe span |
| C Planner5D product | 44–54 / +83–+104 | 3D, catalog, AR place — **not** scan accuracy |
| D Accuracy resume | 55+ / +105+ | Geometry score + scale fix |

Full product retro: `docs/RELEASE_RETRO_40_93.md`.

---

## Planner5D accuracy reference (what “good” means)

| Planner5D behavior | RoomCraft now (+105) | Gap |
|--------------------|----------------------|-----|
| Walls from AR / user measure | AR 4-wall + field measure + photo auto-scale | Photo path still estimate |
| Furniture catalog fixed sizes | Catalog + wall-anchor | Good |
| No free-float random XY | Wall-relative + gold ensure | Good for study |
| Opening widths labeled | Openings + size labels | Good |
| Room size trustworthy | Gold floor 20.3×17; door prior scale | Full-wall wardrobe no longer destroys scale |
| Multi-room types | Study gold strong; bedroom polish-only | **Open** |
| Honest confidence | Geometry match % in warnings | Heuristic ≠ survey |

---

## Related

- Feedback gold: `data/feedback/32ffdc65-a49`, `e89c702e-7e4`, `c8c569e9-e03`
- Code: `lib/domain/photo_true_layout.dart`, `lib/domain/auto_scale.dart`
- Tests: `test/photo_true_layout_test.dart`, `test/auto_scale_wardrobe_test.dart`
