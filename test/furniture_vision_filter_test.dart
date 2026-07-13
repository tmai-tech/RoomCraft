import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/furniture_vision_filter.dart';

void main() {
  test('drops low confidence and missing evidence', () {
    final result = FurnitureVisionFilter.filter([
      {'type': 'BED', 'confidence': 0.4, 'pos': {'x': 1, 'y': 1}, 'dim': {'w': 5, 'l': 6}},
      {'type': 'SOFA', 'confidence': 0.9, 'pos': {'x': 2, 'y': 2}, 'dim': {'w': 6, 'l': 3}},
      {'type': 'TV_UNIT', 'pos': {'x': 3, 'y': 3}, 'dim': {'w': 5, 'l': 1.5}}, // no conf/evidence
      {
        'type': 'TABLE',
        'evidence': 'wooden table clearly in center of room photo',
        'pos': {'x': 4, 'y': 4},
        'dim': {'w': 3, 'l': 2},
      },
    ]);
    expect(result.dropped, 2); // bed + tv
    expect(result.kept.length, 2);
    expect(result.kept.map((e) => e['type']), containsAll(['SOFA', 'TABLE']));
  });

  test('empty input stays empty', () {
    final result = FurnitureVisionFilter.filter([]);
    expect(result.kept, isEmpty);
    expect(result.dropped, 0);
  });
}
