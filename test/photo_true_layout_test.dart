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
    expect(min.widthFt, greaterThanOrEqualTo(16));
    expect(min.lengthFt, greaterThanOrEqualTo(14));
  });
}
