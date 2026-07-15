import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/furniture_vision_filter.dart';

void main() {
  test('keeps moderate confidence and typed pieces without conf', () {
    final result = FurnitureVisionFilter.filter([
      {
        'type': 'BED',
        'confidence': 0.4,
        'pos': {'x': 1, 'y': 1},
        'dim': {'w': 5, 'l': 6},
      },
      {
        'type': 'SOFA',
        'confidence': 0.9,
        'pos': {'x': 2, 'y': 2},
        'dim': {'w': 6, 'l': 3},
      },
      // No conf — but typed + pos → keep at default ~0.65
      {
        'type': 'TV_UNIT',
        'pos': {'x': 3, 'y': 3},
        'dim': {'w': 5, 'l': 1.5},
      },
      {
        'type': 'TABLE',
        'evidence': 'wooden table clearly in center of room photo',
        'pos': {'x': 4, 'y': 4},
        'dim': {'w': 3, 'l': 2},
      },
      {
        'type': 'WARDROBE',
        'confidence': 0.6,
        'pos': {'x': 1, 'y': 8},
        'dim': {'w': 6, 'l': 2},
      },
    ]);
    // bed 0.4 dropped; sofa, tv, table, wardrobe kept
    expect(result.dropped, 1);
    expect(result.kept.length, 4);
    expect(
      result.kept.map((e) => e['type']),
      containsAll(['SOFA', 'TV_UNIT', 'TABLE', 'WARDROBE']),
    );
  });

  test('drops items with no type', () {
    final result = FurnitureVisionFilter.filter([
      {'confidence': 0.9, 'pos': {'x': 1, 'y': 1}},
    ]);
    expect(result.kept, isEmpty);
    expect(result.dropped, 1);
  });

  test('empty input stays empty', () {
    final result = FurnitureVisionFilter.filter([]);
    expect(result.kept, isEmpty);
    expect(result.dropped, 0);
  });

  test('min confidence default is 0.55 for recall', () {
    expect(FurnitureVisionFilter.minConfidence, 0.55);
  });
}
