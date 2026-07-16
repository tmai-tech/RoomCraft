import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/services/free_vision_scanner.dart';

void main() {
  test('inventory seed adds WARDROBE and TABLE when MUST and empty', () {
    final result = FreeVisionScanner.applyInventoryCompletePublic(
      {
        'roomWidth': 12.0,
        'roomLength': 14.0,
        'furniture': <dynamic>[],
        'openings': <dynamic>[],
      },
      'MUST include WARDROBE; MUST include TABLE (desk); NO BED; NO SOFA; NO TV_UNIT',
    );
    expect(result.added, greaterThanOrEqualTo(2));
    final types = (result.map['furniture'] as List)
        .map((e) => (e as Map)['type']?.toString().toUpperCase())
        .toList();
    expect(types, contains('WARDROBE'));
    expect(types, contains('TABLE'));
  });

  test('inventory gate strips forbidden BED', () {
    final result = FreeVisionScanner.applyInventoryCompletePublic(
      {
        'furniture': [
          {'type': 'BED', 'wall': 'south', 'fromLeft': 1, 'depth': 1, 'dim': {'w': 5, 'l': 6}},
          {'type': 'TABLE', 'wall': 'east', 'fromLeft': 2, 'depth': 1, 'dim': {'w': 4, 'l': 2}},
        ],
      },
      'MUST include TABLE; NO BED; NO SOFA; NO TV_UNIT',
    );
    final types = (result.map['furniture'] as List)
        .map((e) => (e as Map)['type']?.toString().toUpperCase())
        .toList();
    expect(types, isNot(contains('BED')));
    expect(types, contains('TABLE'));
  });
}
