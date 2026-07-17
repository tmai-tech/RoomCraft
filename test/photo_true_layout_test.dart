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

  test('+51 ensureGoldQuality upgrades empty multi-wall plan', () {
    final empty = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 16,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.2,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final out = PhotoTrueLayout.ensureGoldQuality(empty);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(out.accuracyScore, greaterThanOrEqualTo(0.74));
  });

  test('+50 merge keeps east wardrobe and fills openings', () {
    final partial = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 16,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(16.5, 8),
          widthFt: 6.5,
          lengthFt: 1.5,
          rotationRad: 1.5708,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    );
    final merged = PhotoTrueLayout.mergeWithStudyGold(partial);
    expect(PhotoTrueLayout.isPhotoTrue(merged), isTrue);
    final wardrobe =
        merged.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // Vision east placement preserved (not reset to north template only)
    expect(wardrobe.posFt.dx, greaterThan(10));
    expect(
      merged.furniture.any((f) => f.type == FurnitureType.table),
      isTrue,
    );
    expect(
      merged.walls.any((w) =>
          w.type == StrokeType.door || w.type == StrokeType.balcony),
      isTrue,
    );
  });

  test('+49 composeStudyGold is photo-true dense gold layout', () {
    final gold = PhotoTrueLayout.composeStudyGold(
      widthFt: 18.5,
      lengthFt: 17.2,
    );
    expect(PhotoTrueLayout.isPhotoTrue(gold), isTrue);
    expect(gold.accuracyScore, greaterThanOrEqualTo(0.74));
    final types = gold.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    expect(types, contains(FurnitureType.chair));
    expect(types, isNot(contains(FurnitureType.bed)));
    expect(types, isNot(contains(FurnitureType.sofa)));
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(
      mathMax(wardrobe.widthFt, wardrobe.lengthFt),
      greaterThanOrEqualTo(6.0),
    );
    final opens = gold.walls
        .where((w) =>
            w.type == StrokeType.door || w.type == StrokeType.balcony)
        .length;
    expect(opens, greaterThanOrEqualTo(2));
  });

  test('+47 multi openings land on more than one wall', () {
    final base = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 16,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final polished = PhotoTrueLayout.polish(base);
    final opens = polished.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .toList();
    expect(opens.length, greaterThanOrEqualTo(2));
    // At least two distinct perimeter edges (different midpoints)
    final mids = opens
        .map((o) => Offset(
              (o.startFt.dx + o.endFt.dx) / 2,
              (o.startFt.dy + o.endFt.dy) / 2,
            ))
        .toList();
    var distinct = 0;
    for (var i = 0; i < mids.length; i++) {
      var unique = true;
      for (var j = 0; j < i; j++) {
        if ((mids[i] - mids[j]).distance < 1.0) unique = false;
      }
      if (unique) distinct++;
    }
    expect(distinct, greaterThanOrEqualTo(2));
  });

  test('+46 second polish from forced inventory reaches photo-true', () {
    // Simulates weak wall-by-wall then forced inventory second pass (+46)
    final weak = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 16,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    );
    final first = PhotoTrueLayout.polish(weak);
    expect(PhotoTrueLayout.isPhotoTrue(first), isFalse);
    final second = PhotoTrueLayout.polish(first.copyWith(
      warnings: [
        ...first.warnings,
        'Inventory: MUST include WARDROBE; MUST include TABLE (desk); '
            'include CHAIR if seen; NO BED; NO SOFA; NO TV_UNIT; '
            'about 2 door opening(s); MUST include mesh balcony',
        'Forced photo-true second polish (+46)',
      ],
    ));
    expect(PhotoTrueLayout.isPhotoTrue(second), isTrue);
    expect(second.accuracyScore, greaterThanOrEqualTo(0.74));
    final types = second.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    expect(
      second.walls.any((w) =>
          w.type == StrokeType.door || w.type == StrokeType.balcony),
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

