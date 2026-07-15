import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('parses wall-anchored wardrobe and door like feedback room', () {
    final result = ScanParser.parse({
      'roomWidth': 12.0,
      'roomLength': 14.0,
      'openings': [
        {
          'type': 'door',
          'wall': 'south',
          'fromLeft': 1.0,
          'width': 2.8,
          'confidence': 0.9,
        },
        {
          'type': 'balcony',
          'wall': 'east',
          'fromLeft': 0.5,
          'width': 7.0,
          'confidence': 0.85,
        },
      ],
      'furniture': [
        {
          'type': 'WARDROBE',
          'wall': 'north',
          'fromLeft': 4.0,
          'depth': 1.2,
          'dim': {'w': 8.0, 'l': 2.0},
          'confidence': 0.9,
        },
        {
          'type': 'TABLE',
          'wall': 'east',
          'fromLeft': 3.0,
          'depth': 1.5,
          'dim': {'w': 4.0, 'l': 2.0},
          'confidence': 0.85,
        },
      ],
    });

    expect(result.roomWidthFt, 12.0);
    expect(result.roomLengthFt, 14.0);
    final doors = result.walls.where((w) => w.type == StrokeType.door);
    final balc = result.walls.where((w) => w.type == StrokeType.balcony);
    expect(doors.length, greaterThanOrEqualTo(1));
    expect(balc.length, greaterThanOrEqualTo(1));
    final types = result.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    // Pieces should not all stack at room center (random freeform failure).
    final centers = result.furniture.map((f) => f.posFt).toList();
    expect(centers.any((p) => p.dy < 3 || p.dy > 11 || p.dx < 3 || p.dx > 9),
        isTrue);
  });
}
