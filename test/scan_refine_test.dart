import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('lockSize rescales openings', () {
    final input = ScanResult(
      roomWidthFt: 10,
      roomLengthFt: 10,
      walls: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1, 0),
          endFt: Offset(4, 0),
        ),
      ],
      furniture: const [],
      accuracyScore: 0.5,
    );
    final out = ScanRefine.lockSize(
      input,
      widthFt: 20,
      lengthFt: 20,
    );
    expect(out.roomWidthFt, 20);
    expect(out.roomLengthFt, 20);
    // Door still on south wall after refine
    final doors = out.walls.where((w) => w.type == StrokeType.door);
    expect(doors, isNotEmpty);
    expect(out.accuracyScore!, greaterThan(0.5));
  });

  test('refine keeps wall-anchored piece near same wall', () {
    final input = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 14,
      walls: const [],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.sofa,
          posFt: Offset(6, 0.8), // already near south wall
          widthFt: 7,
          lengthFt: 3,
        ),
      ],
    );
    final out = ScanRefine.refine(input);
    final sofa = out.furniture.first;
    // Must NOT be thrown to another wall (random scramble)
    expect(sofa.posFt.dy, lessThan(3.0));
  });

  test('refine pins only truly floating furniture', () {
    final input = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 14,
      walls: const [],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(6, 7), // room center — floating
          widthFt: 3,
          lengthFt: 2,
        ),
      ],
    );
    final out = ScanRefine.refine(input);
    final t = out.furniture.first;
    // Center piece should move toward a wall
    final minD = [
      t.posFt.dy,
      14 - t.posFt.dy,
      t.posFt.dx,
      12 - t.posFt.dx,
    ].reduce((a, b) => a < b ? a : b);
    expect(minD, lessThan(2.5));
  });

  test('door width prior applied', () {
    // Unrealistic 8 ft door on 12 ft wall
    final input = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 12,
      walls: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1, 0),
          endFt: Offset(9, 0),
        ),
      ],
      furniture: const [],
    );
    final out = ScanRefine.refine(input);
    final door = out.walls.firstWhere((w) => w.type == StrokeType.door);
    expect(door.lengthFt, lessThan(5.0));
    expect(door.lengthFt, greaterThan(1.9));
  });
}
