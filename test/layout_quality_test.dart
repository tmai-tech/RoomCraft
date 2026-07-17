import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/accurate_scan.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('+40 polish turns partial plan toward photo-true gold bar', () {
    final thin = AccurateScan.enforce(
      widthFt: 12,
      lengthFt: 10.5,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(5, 5),
          widthFt: 3,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.35,
    );
    expect(PhotoTrueLayout.isPhotoTrue(thin), isFalse);

    final gold = PhotoTrueLayout.polish(AccurateScan.enforce(
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
          startFt: Offset(16, 3),
          endFt: Offset(16, 9),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(1.2, 7),
          widthFt: 6.5,
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
      accuracyScore: 0.5,
    ));

    expect(PhotoTrueLayout.isPhotoTrue(gold), isTrue);
    expect(gold.accuracyScore, greaterThanOrEqualTo(0.74));
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    final along = wardrobe.widthFt > wardrobe.lengthFt
        ? wardrobe.widthFt
        : wardrobe.lengthFt;
    expect(along, greaterThanOrEqualTo(5.5));
  });
}
