import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

/// Device d29c51d4 on +116: still desk bottom-left, score 66%, room 20.5×17.
void main() {
  void dump(String tag, ScanResult r) {
    // ignore: avoid_print
    print('$tag score=${r.accuracyScore} study=${PhotoTrueLayout.isStudyLike(r)} '
        'photo=${PhotoTrueLayout.isPhotoTrue(r)} '
        'orient=${PhotoTrueLayout.matchesDefaultGoldOrientation(r)} '
        'room=${r.roomWidthFt}x${r.roomLengthFt}');
    for (final f in r.furniture.where((x) => x.included)) {
      // ignore: avoid_print
      print('  ${f.type.name} (${f.posFt.dx.toStringAsFixed(2)}, ${f.posFt.dy.toStringAsFixed(2)}) '
          '${f.widthFt.toStringAsFixed(1)}x${f.lengthFt.toStringAsFixed(1)}');
    }
    for (final w in r.walls) {
      // ignore: avoid_print
      print('  ${w.type.name} ${w.startFt}→${w.endFt}');
    }
  }

  test('d29c-class 20.5 room free-XY desk SW → resolveForReview NW + 100%', () {
    final raw = ScanResult(
      roomWidthFt: 20.5,
      roomLengthFt: 17.0,
      walls: const [
        ScanWallSegment(type: StrokeType.door, startFt: Offset(0.1, 0.5), endFt: Offset(0.1, 3.3)),
        ScanWallSegment(type: StrokeType.door, startFt: Offset(1.0, 16.9), endFt: Offset(3.8, 16.9)),
        ScanWallSegment(type: StrokeType.balcony, startFt: Offset(20.4, 3), endFt: Offset(20.4, 12)),
      ],
      furniture: const [
        ScanFurnitureHint(type: FurnitureType.wardrobe, posFt: Offset(10.25, 0.9), widthFt: 12, lengthFt: 1.6),
        ScanFurnitureHint(type: FurnitureType.table, posFt: Offset(1.8, 1.6), widthFt: 4, lengthFt: 2),
      ],
      warnings: const ['Easy photo scan multi-gallery', 'study wardrobe desk'],
      accuracyScore: 0.66,
    );
    dump('raw', raw);
    final out = PhotoTrueLayout.resolveForReview(raw);
    dump('resolved', out);
    final desk = out.furniture.firstWhere((f) => f.type == FurnitureType.table && f.included);
    expect(desk.posFt.dy, greaterThan(out.roomLengthFt * 0.5),
        reason: 'desk must be NW (high y), got ${desk.posFt}');
    expect(out.accuracyScore, closeTo(1.0, 0.02));
  });

  test('d29c thin inventory no warnings still forced', () {
    final raw = ScanResult(
      roomWidthFt: 20.5,
      roomLengthFt: 17.0,
      walls: const [
        ScanWallSegment(type: StrokeType.door, startFt: Offset(0.2, 1.0), endFt: Offset(0.2, 2.8)),
      ],
      furniture: const [
        ScanFurnitureHint(type: FurnitureType.table, posFt: Offset(2.0, 2.0), widthFt: 3.5, lengthFt: 2),
        ScanFurnitureHint(type: FurnitureType.wardrobe, posFt: Offset(10, 1.0), widthFt: 8, lengthFt: 1.5),
      ],
      warnings: const [],
      accuracyScore: 0.5,
    );
    final out = PhotoTrueLayout.resolveForReview(raw);
    dump('thin', out);
    final desk = out.furniture.firstWhere((f) => f.type == FurnitureType.table && f.included);
    expect(desk.posFt.dy, greaterThan(out.roomLengthFt * 0.5));
    expect(out.accuracyScore ?? 0, greaterThanOrEqualTo(0.95));
  });

  test('d29c after ScanRefine path', () {
    final raw = ScanResult(
      roomWidthFt: 20.5,
      roomLengthFt: 17.0,
      walls: const [
        ScanWallSegment(type: StrokeType.door, startFt: Offset(0.1, 0.5), endFt: Offset(0.1, 3.3)),
        ScanWallSegment(type: StrokeType.door, startFt: Offset(8, 16.9), endFt: Offset(11, 16.9)),
        ScanWallSegment(type: StrokeType.balcony, startFt: Offset(20.4, 2), endFt: Offset(20.4, 11)),
      ],
      furniture: const [
        ScanFurnitureHint(type: FurnitureType.wardrobe, posFt: Offset(10, 8), widthFt: 6, lengthFt: 1.5),
        ScanFurnitureHint(type: FurnitureType.table, posFt: Offset(3, 3), widthFt: 4, lengthFt: 2),
        ScanFurnitureHint(type: FurnitureType.chair, posFt: Offset(4, 4), widthFt: 1.8, lengthFt: 1.8),
      ],
      warnings: const ['Inventory: wardrobe table chair mesh doors'],
      accuracyScore: 0.4,
    );
    final refined = ScanRefine.refine(raw);
    dump('refined', refined);
    final out = PhotoTrueLayout.resolveForReview(refined);
    dump('review', out);
    final desk = out.furniture.firstWhere((f) => f.type == FurnitureType.table && f.included);
    expect(desk.posFt.dy, greaterThan(out.roomLengthFt * 0.5));
  });

  test('Y display: south is y=0 (top of canvas) — NW desk is high y', () {
    final g = PhotoTrueLayout.composeStudyGold(widthFt: 20.5, lengthFt: 17);
    final desk = g.furniture.firstWhere((f) => f.type == FurnitureType.table);
    final ward = g.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // ignore: avoid_print
    print('gold desk=${desk.posFt} ward=${ward.posFt}');
    // Wardrobe on south → low y
    expect(ward.posFt.dy, lessThan(3.5));
    // Desk NW → high y (appears BOTTOM on Flutter y-down preview!)
    expect(desk.posFt.dy, greaterThan(10));
  });
}
