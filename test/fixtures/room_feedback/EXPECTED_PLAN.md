# Feedback accuracy analysis (5244fa22-4dd + e89c702e-7e4 + 32ffdc65-a49) — +36

## Report A — `5244fa22-4dd` (+25)

**Message:** plan results still random; input + output attached; needs totally accurate.

| | Content |
|--|---------|
| **Input** (previews 0–2) | Same study room: pink/white sliding **wardrobe**, **desk+monitors**, **mesh sliding glass**, **2 door openings**, AC. No bed/sofa. |
| **Output** | Cloud only stored 3 thumbs (inputs). User says plan still random vs room. |
| **Root causes** | (1) ScanRefine **re-snapped every piece to nearest wall**, scrambling wall-anchored layout. (2) Free monocular XY still weak. (3) Model can invent bed/sofa. (4) Only 3 Firestore previews so output plan not saved for review. |

## Report B — `e89c702e-7e4` (+25)

**Message:** this was the expected output **minimum**.

| | Content |
|--|---------|
| **Expected plan** | Dense labeled floor plan: bed 6.6×4.5, sofa 6.5×3, wardrobe 6.7×1.5, TV 5×1.5, table 3×2, doors/windows, room ~18.5×17.2, score ~74%. |

**Note:** That gold plan includes **bed/sofa/TV** not visible in the study-room photos. Treat it as the **quality bar** (wall-aligned, labeled, complete inventory). For *these* photos the **photo-true minimum** is:

| Must detect | Must NOT invent |
|-------------|-----------------|
| WARDROBE (long sliding) | BED |
| TABLE (desk) | SOFA |
| ≥1 door + mesh balcony/window | TV_UNIT unless seen |
| Wall-anchored placement | Random free XY |

## +26 fixes

1. Inventory pass → placement pass (forbid invented types).
2. Refine only pins **floating** pieces (keeps wall-anchored positions).
3. Softer size overrides for wardrobe/desk.
4. Feedback previews up to 5 smaller thumbs (capture output plan too).
