import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/accurate_scan.dart';
import 'package:room_craft/domain/opening_chain_fidelity.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('+107 snaps narrow door to gold 2.8 ft', () {
    final base = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: const [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 2),
          endFt: Offset(0, 3.5), // 1.5 ft door — too narrow
        ),
      ],
      furniture: const [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 1.2),
          widthFt: 12,
          lengthFt: 1.5,
        ),
        ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(1.5, 12),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.5,
    ).copyWith(warnings: [
      'Inventory: MUST include WARDROBE; MUST include TABLE; about 2 door opening(s); MUST include mesh balcony',
    ]);
    final out = OpeningChainFidelity.ensure(base);
    final doors = out.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors, isNotEmpty);
    expect(doors.first.lengthFt, closeTo(2.8, 0.35));
    expect(out.warnings.any((w) => w.contains('+107')), isTrue);
  });

  test('+107 reclassifies wide door as mesh when inventory wants mesh', () {
    final base = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: const [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(20, 2),
          endFt: Offset(20, 10), // 8 ft "door"
        ),
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 1),
          endFt: Offset(0, 3.8),
        ),
      ],
      furniture: const [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 1.2),
          widthFt: 12,
          lengthFt: 1.5,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.5,
    ).copyWith(warnings: [
      'MUST include mesh balcony; about 2 door opening(s)',
    ]);
    final out = OpeningChainFidelity.ensure(base);
    expect(
      out.walls.any((w) => w.type == StrokeType.balcony),
      isTrue,
    );
  });

  test('+107 separates overlapping openings on same wall', () {
    final base = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: const [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 2),
          endFt: Offset(0, 4.8),
        ),
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 3),
          endFt: Offset(0, 5.8),
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    ).copyWith(warnings: ['about 2 door opening(s)']);
    final out = OpeningChainFidelity.ensure(base);
    final doors = out.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors.length, greaterThanOrEqualTo(2));
    // Centers should not be nearly identical after de-overlap
    final mids = doors
        .map((d) => Offset(
              (d.startFt.dx + d.endFt.dx) / 2,
              (d.startFt.dy + d.endFt.dy) / 2,
            ))
        .toList();
    expect((mids[0] - mids[1]).distance, greaterThan(1.5));
  });

  test('+107 opening fidelity score high after ensure on gold study', () {
    final empty = AccurateScan.enforce(
      widthFt: 12,
      lengthFt: 10.5,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.25,
    ).copyWith(warnings: [
      'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
          'about 2 door opening(s); MUST include mesh balcony',
      'multi-wall study',
    ]);
    final out = PhotoTrueLayout.ensureGoldQuality(empty);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    final fid = OpeningChainFidelity.score(out);
    expect(fid, greaterThanOrEqualTo(0.7));
    final doors = out.walls.where((w) => w.type == StrokeType.door);
    for (final d in doors) {
      expect(d.lengthFt, inInclusiveRange(2.2, 3.6));
    }
  });
}
