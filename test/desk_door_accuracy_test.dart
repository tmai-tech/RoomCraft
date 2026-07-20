import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/opening_chain_fidelity.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/domain/wall_relative_scan.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

/// +112: desk NW + door corner fromLeft must match gold blueprint.
void main() {
  ScanResult gold() =>
      PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);

  void expectGoldDoors(ScanResult out) {
    final roles = PhotoTrueLayout.defaultStudyWallRoles(
      out.roomWidthFt,
      out.roomLengthFt,
    );
    final doors =
        out.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors.length, greaterThanOrEqualTo(2));
    for (final d in doors) {
      expect(d.lengthFt, closeTo(OpeningChainFidelity.goldDoorFt, 0.25));
      final f = WallRelativeComposer.openingToField(
        d,
        out.roomWidthFt,
        out.roomLengthFt,
      );
      expect(f, isNotNull);
      // Corner placement — not mid-wall
      expect(f!.fromLeftFt, lessThan(4.0),
          reason: 'door mid-wall fromLeft=${f.fromLeftFt} on ${f.wall}');
      expect(
        f.wall == roles.doorPrimary || f.wall == roles.doorSecondary,
        isTrue,
        reason: 'door on ${f.wall}, expected ${roles.doorPrimary}/${roles.doorSecondary}',
      );
    }
    // Primary door near 1.2
    final primary = doors.map((d) {
      final f = WallRelativeComposer.openingToField(
        d,
        out.roomWidthFt,
        out.roomLengthFt,
      )!;
      return f;
    }).where((f) => f.wall == roles.doorPrimary);
    expect(primary, isNotEmpty);
    expect(primary.first.fromLeftFt, closeTo(1.2, 0.5));
  }

  void expectGoldDesk(ScanResult out) {
    final roles = PhotoTrueLayout.defaultStudyWallRoles(
      out.roomWidthFt,
      out.roomLengthFt,
    );
    final desk = out.furniture
        .firstWhere((f) => f.included && f.type == FurnitureType.table);
    // West wall for wide room
    expect(desk.posFt.dx, lessThan(3.5),
        reason: 'desk not on west work wall: ${desk.posFt}');
    // NW — toward north (high y)
    expect(desk.posFt.dy, greaterThan(out.roomLengthFt * 0.55),
        reason: 'desk not NW (y=${desk.posFt.dy})');
    final goldDesk = gold().furniture
        .firstWhere((f) => f.type == FurnitureType.table);
    expect((desk.posFt - goldDesk.posFt).distance, lessThan(1.5),
        reason: 'desk MAE vs gold ${(desk.posFt - goldDesk.posFt).distance}');
  }

  test('+112 cleanStudyDeskAndDoors forces gold doors + desk', () {
    final messy = ScanResult(
      roomWidthFt: 20.3,
      roomLengthFt: 17,
      walls: const [
        // mid-wall doors (the bug)
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0.1, 7),
          endFt: Offset(0.1, 8.5),
        ),
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(9, 16.9),
          endFt: Offset(11, 16.9),
        ),
        ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20.2, 4),
          endFt: Offset(20.2, 12),
        ),
      ],
      furniture: const [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10.15, 0.9),
          widthFt: 14,
          lengthFt: 1.6,
        ),
        // desk mid west wall (wrong — should be NW)
        ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(1.6, 8.5),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      warnings: const [
        'Inventory: MUST include WARDROBE; MUST include TABLE; study; mesh; 2 door',
      ],
    );
    final out = PhotoTrueLayout.cleanStudyDeskAndDoors(messy);
    expectGoldDoors(out);
    expectGoldDesk(out);
  });

  test('+112 ensureGoldQuality on free-XY noise → clean desk + doors', () {
    final noisy = ScanResult(
      roomWidthFt: 18,
      roomLengthFt: 15,
      walls: const [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0.2, 5),
          endFt: Offset(0.2, 6.5),
        ),
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(8, 14.8),
          endFt: Offset(10, 14.8),
        ),
        ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(17.7, 2),
          endFt: Offset(17.7, 10),
        ),
      ],
      furniture: const [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(9, 7),
          widthFt: 6,
          lengthFt: 1.5,
        ),
        ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(5, 8),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      warnings: const [
        'Inventory: MUST include WARDROBE; MUST include TABLE; '
            'about 2 door opening(s); MUST include mesh balcony; study',
      ],
      accuracyScore: 0.3,
    );
    final out = PhotoTrueLayout.ensureGoldQuality(noisy);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expectGoldDoors(out);
    expectGoldDesk(out);
    final report = PlanAccuracyMetrics.compare(out, gold());
    expect(report.furnitureCenterMaeFt, lessThanOrEqualTo(1.5));
    expect(report.compositeScore, greaterThanOrEqualTo(0.80));
  });

  test('+112 wall-json mid desk snaps to NW after ensureGold', () {
    final parsed = ScanParser.parse({
      'roomWidth': 20.3,
      'roomLength': 17.0,
      'openings': [
        {
          'type': 'door',
          'wall': 'west',
          'fromLeft': 7.0, // mid-wall bug
          'width': 2.0,
          'confidence': 0.9,
        },
        {
          'type': 'door',
          'wall': 'north',
          'fromLeft': 9.0,
          'width': 3.0,
          'confidence': 0.9,
        },
        {
          'type': 'balcony',
          'wall': 'east',
          'fromLeft': 1.5,
          'width': 10.0,
          'confidence': 0.9,
        },
      ],
      'furniture': [
        {
          'type': 'WARDROBE',
          'wall': 'south',
          'fromLeft': 10.15,
          'depth': 1.6,
          'dim': {'w': 14.0, 'l': 1.6},
          'confidence': 0.9,
        },
        {
          'type': 'TABLE',
          'wall': 'west',
          'fromLeft': 8.0, // mid west
          'depth': 1.6,
          'dim': {'w': 4.0, 'l': 2.0},
          'confidence': 0.9,
        },
      ],
      'warnings': ['study wardrobe desk'],
    });
    final out = PhotoTrueLayout.ensureGoldQuality(ScanRefine.refine(parsed));
    expectGoldDoors(out);
    expectGoldDesk(out);
  });

  test('+112 gold plan identity stable under clean pass', () {
    final g = gold();
    final again = PhotoTrueLayout.cleanStudyDeskAndDoors(g);
    final report = PlanAccuracyMetrics.compare(again, g);
    expect(report.furnitureCenterMaeFt, lessThanOrEqualTo(0.8));
    expect(report.compositeScore, greaterThanOrEqualTo(0.90));
    expectGoldDoors(again);
    expectGoldDesk(again);
  });
}
