# Skeptic claim → current tree proof (+90/91)

Objective remains: Planner 5D Play-listing level. This file maps repeated skeptic
claims to **current** code and evidence (do not use pre-+88 line numbers).

## Claim: AR Room Planner is label theater (`home_screen` ~553–564 / `_createNewAI`)

**False on current tree.** Lines in `_showCreateOptions` AR tile call `_createNewAR()`, not `_createNewAI()`.

```dart
// lib/screens/home_screen.dart
void _createNewAR() {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const ScannerScreen(
        initialScanMode: 'ar_guided',
        openAdvanced: true,
      ),
    ),
  )...
}
// AR tile onTap → _createNewAR()  (NOT _createNewAI)
```

Post-measure product path: `ArPlaceLayoutScreen` (measure → AI/catalogue place → 3D).

Evidence: `evidence/ar_distinct_path.txt`, `evidence/ar_place_layout.txt`, `evidence/scanner_ar_initial_mode.txt`.

## Claim: Catalog is ~247 size variants only

**False on current tree.** `FurnitureCatalog.all` is a **getter** that expands seeds to **≥10,000** free SKUs via material × size × collection (`_buildAll`).

Evidence: `evidence/catalog_10k.txt` (`skus=10000`).

Brand marketplace commerce is still open (partners); free décor breadth is shipped.

## Claim: V7 only open+orbit (`test/interactive_3d_styler_test.dart:60-110`)

**False on current tree.** That file now contains a full edit path
`V7 REAL path in interactive_3d_styler: select+rotate+apply+delete` (not open-only):

- furniture picker select (`iso_furniture_picker`)
- rotate (`iso_rotate_btn`) → rotation ≈ π/4
- Apply (`iso_apply_btn`) → `onFurnitureChanged`
- delete second piece → apply

Also covered in `test/skeptic_gaps_test.dart`.

Evidence: `evidence/interactive_3d_widget.txt` includes
`selected_via_picker=true`, `rotated=true`, `onFurnitureChanged_fired=true`,
`deleted_table=true`, `source_test=interactive_3d_styler_test.dart`.

## Claim: 3D is orthographic isometric only

**False on current tree.** `IsometricPainter` defaults to **perspective walkthrough** (`perspective: true`) with first-person eye height + walk pad (`walkX`/`walkY`). Iso remains optional toggle.

Evidence: `evidence/walkthrough_3d.txt`.

## Claim: Plan redefines objective to C1–C8

**False after §5 rewrite.** Objective statement is full Play listing; table tracks **P1–P7** with free-path status and open paid/native work. No “C1–C8 = goal achieved” completion rule.

See `docs/PLANNER5D_PARITY_PLAN.md` §5–§6.

## Still open for full Play clone

| Pillar | Open work |
|--------|-----------|
| Brand marketplace | Partner SKUs / commerce |
| Photoreal mesh HD | Render engine (beyond free HD 3D snapshot) |
| Live-camera AR furniture anchors | Native OpenGL place mode |

## Re-run verification

```bash
flutter test test/skeptic_gaps_test.dart \
  test/blueprint_e2e_path_test.dart \
  test/interactive_3d_styler_test.dart
```
