import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/accurate_scan.dart';
import 'package:room_craft/domain/auto_scale.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('+39 polish yields photo-true gold score ~74%', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1, 0),
          endFt: Offset(4, 0),
        ),
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(16, 2),
          endFt: Offset(16, 8),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(1.2, 7),
          widthFt: 6.7,
          lengthFt: 1.5,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    );

    final polished = PhotoTrueLayout.polish(base);
    expect(PhotoTrueLayout.isPhotoTrue(polished), isTrue);
    expect(polished.accuracyScore, greaterThanOrEqualTo(0.74));
    final wardrobe = polished.furniture
        .firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(
      wardrobe.widthFt > wardrobe.lengthFt
          ? wardrobe.widthFt
          : wardrobe.lengthFt,
      greaterThanOrEqualTo(5.5),
    );
  });

  test('+39 refine keeps photo-true score bar', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(2, 0),
          endFt: Offset(5, 0),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(1, 6),
          widthFt: 6.5,
          lengthFt: 1.5,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(6, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.74,
    );
    final refined = ScanRefine.refine(base);
    expect(refined.accuracyScore, greaterThanOrEqualTo(0.74));
  });

  test('+39 dense min room for wardrobe+mesh', () {
    final min = AutoScale.ensurePhotoTrueMinSize(
      widthFt: 12,
      lengthFt: 10.5,
      inventoryHint:
          'MUST include WARDROBE; MUST include mesh balcony; about 2 door opening(s)',
    );
    // +45 dense floor raised toward gold-plan scale
    expect(min.widthFt, greaterThanOrEqualTo(18));
    expect(min.lengthFt, greaterThanOrEqualTo(16));
  });

  test('+41 caps confidence when plan is table-only (feedback 443cf0c3)', () {
    final thin = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.74, // falsely high from older builds
    );
    final polished = PhotoTrueLayout.polish(thin);
    // Without inventory MUST wardrobe in warnings, polish may still seed if
    // table-only — table-only without wardrobe must not stay at 74%.
    if (!PhotoTrueLayout.isPhotoTrue(polished)) {
      expect(
        polished.accuracyScore ?? 0,
        lessThanOrEqualTo(PhotoTrueLayout.incompleteScoreCap),
      );
    } else {
      // If warnings/seed made it photo-true, wardrobe must be large and visible
      final w = polished.furniture
          .firstWhere((f) => f.type == FurnitureType.wardrobe);
      expect(mathMax(w.widthFt, w.lengthFt), greaterThanOrEqualTo(5.0));
      expect(polished.accuracyScore, greaterThanOrEqualTo(0.74));
    }
  });

  test('+41 inventory MUST in warnings yields wardrobe+table+openings', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE (desk); '
            'NO BED; NO SOFA; NO TV_UNIT; MUST include mesh balcony; '
            'about 2 door opening(s)',
      ],
    );
    final polished = PhotoTrueLayout.polish(base);
    expect(PhotoTrueLayout.isPhotoTrue(polished), isTrue);
    expect(polished.accuracyScore, greaterThanOrEqualTo(0.74));
    final types = polished.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    expect(
      polished.walls.any((w) =>
          w.type == StrokeType.door ||
          w.type == StrokeType.window ||
          w.type == StrokeType.balcony),
      isTrue,
    );
  });

  test('+44 seeds chair at desk when inventory has chair', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE (desk); '
            'include CHAIR if seen; NO BED; about 2 door opening(s); '
            'MUST include mesh balcony',
      ],
    );
    final polished = PhotoTrueLayout.polish(base);
    final types = polished.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    expect(types, contains(FurnitureType.chair));
    expect(
      polished.walls.any((w) =>
          w.type == StrokeType.door || w.type == StrokeType.balcony),
      isTrue,
    );
  });

  test('+43 keeps wardrobe on east wall (does not force west)', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(2, 0),
          endFt: Offset(5, 0),
        ),
      ],
      furniture: [
        // Against east wall (x near 16)
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(14.5, 7),
          widthFt: 6.5,
          lengthFt: 1.5,
          rotationRad: 1.5708,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.5,
    );
    final polished = PhotoTrueLayout.polish(base);
    expect(PhotoTrueLayout.isPhotoTrue(polished), isTrue);
    final wardrobe =
        polished.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // Still on east half of room (not forced to west x≈1)
    expect(wardrobe.posFt.dx, greaterThan(10));
  });
}

double mathMax(double a, double b) => a > b ? a : b;

