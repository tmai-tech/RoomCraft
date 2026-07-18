# Skeptic claim → current tree proof (+90/91)

Objective remains: Planner 5D Play-listing level. This file maps repeated skeptic
claims to **current** code and evidence (do not use pre-+88 line numbers).

## Claim: AR Room Planner is label theater (`_createNewAI`)

**False on current tree.**

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

## Claim: V7 only open+orbit

**False on current tree.** `test/skeptic_gaps_test.dart` drives real `IsometricPreviewScreen` UI:

- furniture picker select
- rotate button → rotation ≈ π/4
- Apply → `onFurnitureChanged`
- delete second piece → apply

Evidence: `evidence/interactive_3d_widget.txt` includes `selected_via_picker=true`, `rotated=true`, `onFurnitureChanged_fired=true`, `deleted_table=true`.

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
