import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/catalog/furniture_catalog.dart';
import 'package:room_craft/domain/accurate_scan.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('exact 10×10 plan never changes dimensions', () {
    final result = AccurateScan.enforce(
      widthFt: 10,
      lengthFt: 10,
      furniture: [
        ScanFurnitureHint(
          type: FurnitureType.bed,
          posFt: const Offset(50, 50), // way outside — must clamp in
          widthFt: 99,
          lengthFt: 99,
        ),
      ],
    );

    expect(result.roomWidthFt, 10);
    expect(result.roomLengthFt, 10);
    expect(result.walls.where((w) => w.type == StrokeType.wall).length, 4);

    // Rectangle corners
    final walls = result.walls.where((w) => w.type == StrokeType.wall).toList();
    expect(walls.any((w) => w.startFt == Offset.zero && w.endFt == const Offset(10, 0)),
        isTrue);
  });

  test('furniture uses catalog sizes and stays inside room', () {
    final result = AccurateScan.enforce(
      widthFt: 12,
      lengthFt: 14,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.sofa,
          posFt: Offset(1, 1),
          widthFt: 20, // nonsense AI size
          lengthFt: 20,
        ),
      ],
    );

    expect(result.roomWidthFt, 12);
    expect(result.roomLengthFt, 14);
    expect(result.furniture, isNotEmpty);
    final sofa = result.furniture.first;
    final catalog = FurnitureCatalog.entryFor(FurnitureType.sofa);
    expect(sofa.widthFt, catalog.defaultWidthFt);
    expect(sofa.lengthFt, catalog.defaultLengthFt);
    expect(sofa.posFt.dx, greaterThanOrEqualTo(0));
    expect(sofa.posFt.dy, greaterThanOrEqualTo(0));
    expect(sofa.posFt.dx + sofa.widthFt, lessThanOrEqualTo(12.01));
    expect(sofa.posFt.dy + sofa.lengthFt, lessThanOrEqualTo(14.01));
  });

  test('openings project onto outer walls', () {
    final result = AccurateScan.enforce(
      widthFt: 10,
      lengthFt: 10,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(3, 0.4), // slightly off wall
          endFt: Offset(6, 0.5),
        ),
      ],
    );

    final door = result.walls.firstWhere((w) => w.type == StrokeType.door);
    expect(door.startFt.dy, 0);
    expect(door.endFt.dy, 0);
  });

  test('empty furniture when AI invents nothing usable', () {
    final result = AccurateScan.enforce(
      widthFt: 8,
      lengthFt: 8,
      furniture: const [],
    );
    expect(result.furniture, isEmpty);
    expect(result.roomWidthFt, 8);
    expect(result.roomLengthFt, 8);
  });
}
