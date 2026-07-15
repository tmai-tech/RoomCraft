import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('parses valid AI payload', () {
    final result = ScanParser.parse({
      'roomWidth': 15,
      'roomLength': 12,
      'walls': [
        {
          'type': 'wall',
          'start': {'x': 0, 'y': 0},
          'end': {'x': 15, 'y': 0},
        },
        {
          'type': 'door',
          'start': {'x': 5, 'y': 0},
          'end': {'x': 8, 'y': 0},
        },
      ],
      'furniture': [
        {
          'type': 'BED',
          'pos': {'x': 2, 'y': 3},
          'dim': {'w': 5, 'l': 6.5},
          'rot': 90,
        },
        {
          'type': 'TV_UNIT',
          'pos': {'x': 10, 'y': 1},
          'dim': {'w': 4, 'l': 1.5},
        },
      ],
    });

    expect(result.roomWidthFt, 15);
    expect(result.roomLengthFt, 12);
    expect(result.walls.length, 2);
    expect(result.walls[1].type, StrokeType.door);
    expect(result.furniture.length, 2);
    expect(result.furniture[0].type, FurnitureType.bed);
    expect(result.furniture[1].type, FurnitureType.tvUnit);
  });

  test('synthesizes rectangle when no walls', () {
    final result = ScanParser.parse({
      'roomWidth': 10,
      'roomLength': 8,
      'walls': [],
      'furniture': [],
    });
    expect(result.walls.length, 4);
    expect(
      result.warnings.any(
        (w) =>
            w.contains('No walls') ||
            w.contains('rectangular outline'),
      ),
      isTrue,
    );
  });

  test('scale calibration multiplies lengths', () {
    final base = ScanParser.parse({
      'roomWidth': 10,
      'roomLength': 10,
      'walls': [
        {
          'type': 'wall',
          'start': {'x': 0, 'y': 0},
          'end': {'x': 10, 'y': 0},
        },
      ],
      'furniture': [
        {
          'type': 'SOFA',
          'pos': {'x': 2, 'y': 2},
          'dim': {'w': 6, 'l': 3},
        },
      ],
    });

    final scaled = ScanParser.applyScaleCalibration(
      base,
      wallIndex: 0,
      targetLengthFt: 20, // 2x
    );
    expect(scaled.walls.first.lengthFt, closeTo(20, 0.01));
    expect(scaled.furniture.first.widthFt, closeTo(12, 0.01));
  });

  test('toEditor converts feet to pixels', () {
    final base = ScanParser.parse({
      'roomWidth': 10,
      'roomLength': 8,
      'walls': [
        {
          'type': 'wall',
          'start': {'x': 0, 'y': 0},
          'end': {'x': 10, 'y': 0},
        },
      ],
      'furniture': [
        {
          'type': 'CHAIR',
          'pos': {'x': 1, 'y': 1},
          'dim': {'w': 2, 'l': 2},
        },
      ],
    });
    // Exclude furniture
    final withToggle = base.copyWith(
      furniture: [base.furniture.first.copyWith(included: false)],
    );
    final editor = ScanParser.toEditor(withToggle, 20);
    expect(editor.strokes.single.points.last.dx, 200); // 10ft * 20
    expect(editor.furniture, isEmpty);
  });

  test('defaults missing room size', () {
    final result = ScanParser.parse({
      'walls': [
        {
          'type': 'wall',
          'start': {'x': 0, 'y': 0},
          'end': {'x': 5, 'y': 0},
        },
      ],
    });
    expect(result.roomWidthFt, greaterThan(0));
    expect(result.warnings, isNotEmpty);
  });
}
