import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/auto_scale.dart';
import 'package:room_craft/domain/accurate_scan.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:flutter/material.dart';

void main() {
  test('+38 wardrobe prior does not shrink long unit rooms', () {
    final size = AutoScale.resolve(
      visionWidthFt: 14,
      visionLengthFt: 12,
      visionSizeConfidence: 0.6,
      furniture: [
        (type: 'WARDROBE', widthFt: 6.7, lengthFt: 1.5),
      ],
    );
    // Prior was 4.0 → factor ~0.6 → room ~8×7; fixed prior 6.5 keeps near 14×12
    expect(size.widthFt, greaterThanOrEqualTo(12));
    expect(size.lengthFt, greaterThanOrEqualTo(11));
  });

  test('+38 photo-true min size raises 12x10 study under-size', () {
    final min = AutoScale.ensurePhotoTrueMinSize(
      widthFt: 12.0,
      lengthFt: 10.5,
      inventoryHint: 'MUST include WARDROBE; MUST include TABLE',
    );
    expect(min.widthFt, greaterThanOrEqualTo(14));
    expect(min.lengthFt, greaterThanOrEqualTo(12));
    expect(min.notes, isNotEmpty);
  });

  test('+45 dense gold floor is 18x16 for wardrobe+mesh', () {
    final min = AutoScale.ensurePhotoTrueMinSize(
      widthFt: 12.0,
      lengthFt: 10.5,
      inventoryHint:
          'MUST include WARDROBE; MUST include mesh balcony; about 2 door opening(s)',
    );
    expect(min.widthFt, greaterThanOrEqualTo(18));
    expect(min.lengthFt, greaterThanOrEqualTo(16));
  });

  test('+38 user size not overridden by photo-true floor', () {
    final min = AutoScale.ensurePhotoTrueMinSize(
      widthFt: 10,
      lengthFt: 10,
      inventoryHint: 'MUST include WARDROBE',
      usedUserSize: true,
    );
    expect(min.widthFt, 10);
    expect(min.lengthFt, 10);
  });

  test('+38 accurate scan keeps long wardrobe ~6.5 not crush to 4', () {
    final result = AccurateScan.enforce(
      widthFt: 14,
      lengthFt: 12,
      furniture: [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: const Offset(1.0, 6.0),
          widthFt: 6.7,
          lengthFt: 1.5,
        ),
      ],
      inventDefaultOpenings: false,
    );
    final w = result.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(mathMax(w.widthFt, w.lengthFt), greaterThanOrEqualTo(5.5));
  });

  test('+70 accurate scan keeps gold full-wall wardrobe on 20x17', () {
    // composeStudyGold ~14.4ft unit must survive sanitize (old code crushed to 6.5)
    final result = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 1.5),
          widthFt: 14.4,
          lengthFt: 1.6,
        ),
      ],
      inventDefaultOpenings: false,
    );
    final w =
        result.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(mathMax(w.widthFt, w.lengthFt), greaterThanOrEqualTo(12.0));
    expect(mathMin(w.widthFt, w.lengthFt), lessThanOrEqualTo(2.5));
  });

  test('+70 accurate scan keeps long wardrobe when along exceeds short side', () {
    // Wide room 18×12: wardrobe along south can be ~13ft > length 12
    final result = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 12,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(9, 1.5),
          widthFt: 13.0,
          lengthFt: 1.6,
        ),
      ],
      inventDefaultOpenings: false,
    );
    final w =
        result.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(mathMax(w.widthFt, w.lengthFt), greaterThanOrEqualTo(11.0));
  });
}

double mathMin(double a, double b) => a < b ? a : b;

double mathMax(double a, double b) => a > b ? a : b;
