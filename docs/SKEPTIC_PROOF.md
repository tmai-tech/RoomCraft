# Skeptic claim → CURRENT tree proof (+94)

**Do not use pre-+88 line numbers.** Fresh audit 1.0.0-beta.1+94.

## 1. AR Room Planner is label theater / `_createNewAI`

**FALSE.**

- AR tile title in `lib/screens/home_screen.dart`
- `onTap` calls `_createNewAR()` (not `_createNewAI`) — prove via `test/source_proof_test.dart`
- `_createNewAR` opens `ScannerScreen(initialScanMode: 'ar_guided', openAdvanced: true)`
- Post-measure: `ArPlaceLayoutScreen` + **live AR camera place** (`placeFurniture` → `ArPlaceActivity`)

Evidence files:
- `evidence/ar_distinct_path.txt`
- `evidence/scanner_ar_initial_mode.txt`
- `evidence/ar_place_layout.txt`
- `evidence/source_ar_live_place.txt`

## 2. Catalog is ~247 size variants ≠ 10k

**FALSE.**

- `FurnitureCatalog.all` is a **getter** → `_buildAll()` expands seeds to **≥10,000** free SKUs
- Automated: `C_catalog: free catalog reaches 10,000+ SKUs` passes
- Evidence: `evidence/catalog_10k.txt` → `skus=10000`

Brand marketplace commerce remains open (partners). Free décor breadth is shipped.

## 3. 3D is orthographic isometric only

**FALSE.**

- `IsometricPainter.perspective` **defaults to true** (walkthrough-first)
- First-person eye height + `walkX`/`walkY` walk pad
- Select / rotate / delete / apply in 3D editor
- HD 3D snapshot 1600×1200 PNG export

Evidence: `walkthrough_3d.txt`, `hd_3d_snapshot.txt`, `interactive_3d_widget.txt`

Not photoreal mesh (open). Free path is perspective walkthrough + edit.

## 4. V7 open-only (`interactive_3d_styler_test.dart:60-110`)

**FALSE on current tree.**

- Test at line **61**: `V7 REAL path in interactive_3d_styler: select+rotate+apply+delete`
- Exercises `iso_furniture_picker`, `iso_rotate_btn`, `iso_apply_btn`, `iso_delete_btn`
- Writes `interactive_3d_widget.txt` with rotated / onFurnitureChanged / deleted_table

## 5. Plan redefines objective to free C1–C8

**FALSE after rewrite.**

- §5 title: "Objective = Planner 5D Play listing level"
- Tracks **P1–P7** Play pillars; states goal = full Play parity
- Status tracker, not reduced definition of done

See `docs/PLANNER5D_PARITY_PLAN.md` §5–§6.

## Re-run

```bash
flutter test test/skeptic_gaps_test.dart \
  test/blueprint_e2e_path_test.dart \
  test/interactive_3d_styler_test.dart
```
