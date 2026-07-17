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

  test('+36 enrich inventory notes recovers wardrobe desk doors mesh', () {
    final hint = FreeVisionScanner.formatInventoryHintPublic({
      'hasWardrobe': false,
      'hasDeskOrTable': false,
      'hasBed': false,
      'hasSofa': false,
      'hasTvUnit': false,
      'doorCount': 2,
      'hasMeshOrSlidingGlass': false,
      'notes':
          'pink sliding wardrobe, desk with monitors, mesh doors, two openings',
    });
    expect(hint, contains('MUST include WARDROBE'));
    expect(hint, contains('MUST include TABLE'));
    expect(hint, contains('door opening'));
    expect(hint.toLowerCase(), contains('mesh'));
    expect(hint, contains('NO BED'));
    expect(hint, contains('NO SOFA'));
    expect(hint, contains('NO TV_UNIT'));
  });

  test('+36 seed mesh balcony and furniture for study-room photo-true', () {
    final result = FreeVisionScanner.applyInventoryCompletePublic(
      {
        'roomWidth': 12.0,
        'roomLength': 14.0,
        'furniture': <dynamic>[],
        'openings': <dynamic>[],
      },
      'MUST include WARDROBE; MUST include TABLE (desk); NO BED; NO SOFA; '
      'NO TV_UNIT; MUST include mesh balcony or large window for glass sliding; '
      'about 2 door opening(s)',
    );
    final types = (result.map['furniture'] as List)
        .map((e) => (e as Map)['type']?.toString().toUpperCase())
        .toList();
    expect(types, contains('WARDROBE'));
    expect(types, contains('TABLE'));
    final openings = result.map['openings'] as List? ?? [];
    expect(openings, isNotEmpty);
    final openTypes = openings
        .map((e) => (e as Map)['type']?.toString().toLowerCase())
        .toList();
    expect(
      openTypes.any((t) =>
          t != null &&
          (t.contains('balcony') || t.contains('window') || t.contains('door'))),
      isTrue,
    );
  });
}
