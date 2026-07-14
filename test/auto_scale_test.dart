import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/auto_scale.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';
import 'package:flutter/material.dart';

void main() {
  test('user size wins', () {
    final r = AutoScale.resolve(userWidthFt: 10, userLengthFt: 12);
    expect(r.widthFt, 10);
    expect(r.lengthFt, 12);
    expect(r.usedUserSize, isTrue);
    expect(r.confidence, greaterThan(0.9));
  });

  test('door prior rescales oversized vision room', () {
    // Vision said room 24×28 but doors look 5.5 ft (2× scale)
    final r = AutoScale.resolve(
      visionWidthFt: 24,
      visionLengthFt: 28,
      visionSizeConfidence: 0.5,
      doorWidthsFt: [5.5, 5.4],
    );
    // standardDoor 2.75 / 5.45 ≈ 0.5 → room ~12×14
    expect(r.widthFt, closeTo(12.1, 1.5));
    expect(r.lengthFt, closeTo(14.1, 1.5));
    expect(r.usedUserSize, isFalse);
  });

  test('fallback when no signals', () {
    final r = AutoScale.resolve();
    expect(r.widthFt, AutoScale.fallbackWidthFt);
    expect(r.lengthFt, AutoScale.fallbackLengthFt);
  });

  test('rescaleResult maps geometry', () {
    final input = ScanResult(
      roomWidthFt: 10,
      roomLengthFt: 10,
      walls: [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: const Offset(1, 0),
          endFt: const Offset(4, 0),
        ),
      ],
      furniture: const [],
    );
    final out = AutoScale.rescaleResult(
      input,
      newWidthFt: 20,
      newLengthFt: 20,
    );
    expect(out.roomWidthFt, 20);
    expect(out.walls.first.startFt.dx, 2);
    expect(out.walls.first.endFt.dx, 8);
  });
}
