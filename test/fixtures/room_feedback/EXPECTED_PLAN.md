# Expected plan — feedback `53a501e6-018`

Human ground-truth from the three room photos (not AI).

## What is in the photos

1. **Long sliding wardrobe** — pink + white panels, mirrored section, overhead cabinets. Dominates one wall.
2. **Mesh / glass sliding doors** — full-height dark mesh (balcony or outer opening) on another wall.
3. **Work desk** — wooden table with dual monitors + laptop(s), against wall near wardrobe.
4. **Interior doors** — at least one open doorway to a passage/bathroom; possibly a second door.
5. **AC** wall unit (not furniture for plan).
6. **No bed / sofa clearly dominant** in these frames — do not invent.

## Expected top-down (approx)

| Item | Type | Placement |
|------|------|-----------|
| Room | rectangle | ~10–14 ft × 11–15 ft (small study/bedroom) |
| Wardrobe | WARDROBE | full/long wall, depth ~2 ft |
| Desk | TABLE | against adjacent or opposite wall |
| Mesh opening | balcony or large window | long span on outer wall |
| Entry / bath | door | 1–2 openings ~2.5–3 ft |

## Pass criteria for model smoke test

- Detects **WARDROBE** and **TABLE** (desk)
- At least **1 door** or balcony/window opening
- Does **not** invent bed/sofa if not visible
- Uses wall-anchored fields when prompted
