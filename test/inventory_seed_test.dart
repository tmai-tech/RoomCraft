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

  test('+75 wide 20×17: doors on W+N not south wardrobe; mesh east', () {
    // Gold wide study: wardrobe south, mesh east, doors west+north.
    final result = FreeVisionScanner.applyInventoryCompletePublic(
      {
        'roomWidth': 20.0,
        'roomLength': 17.0,
        'furniture': <dynamic>[],
        'openings': <dynamic>[],
      },
      'MUST include WARDROBE; MUST include TABLE (desk); NO BED; NO SOFA; '
      'NO TV_UNIT; MUST include mesh balcony or large window for glass sliding; '
      'about 2 door opening(s)',
    );
    final openings = (result.map['openings'] as List? ?? [])
        .whereType<Map>()
        .toList();
    expect(openings, isNotEmpty);

    final doors = openings.where((o) {
      final t = o['type']?.toString().toLowerCase() ?? '';
      return t.contains('door') && !t.contains('wardrobe');
    }).toList();
    expect(doors.length, greaterThanOrEqualTo(2));
    // Never seed a door through the storage (south) wall
    expect(
      doors.every((d) => d['wall']?.toString().toLowerCase() != 'south'),
      isTrue,
      reason: 'doors must not sit on south wardrobe wall',
    );
    final doorWalls =
        doors.map((d) => d['wall']?.toString().toLowerCase()).toSet();
    expect(doorWalls.contains('west'), isTrue);
    expect(doorWalls.contains('north'), isTrue);

    final mesh = openings.where((o) {
      final t = o['type']?.toString().toLowerCase() ?? '';
      return t.contains('balcony') || t.contains('window');
    }).toList();
    expect(mesh, isNotEmpty);
    expect(mesh.first['wall']?.toString().toLowerCase(), 'east');
    final meshW = mesh.first['width'];
    final mw = meshW is num ? meshW.toDouble() : double.tryParse('$meshW') ?? 0;
    // ~62% of east wall (length 17) ≈ 10.5 ft, capped 12
    expect(mw, greaterThanOrEqualTo(8.0));
  });

  test('+75 deep room: doors avoid west wardrobe wall; mesh north', () {
    final result = FreeVisionScanner.applyInventoryCompletePublic(
      {
        'roomWidth': 12.0,
        'roomLength': 18.0,
        'furniture': <dynamic>[],
        'openings': <dynamic>[],
      },
      'MUST include mesh balcony; about 2 door opening(s)',
    );
    final openings = (result.map['openings'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final doors = openings.where((o) {
      final t = o['type']?.toString().toLowerCase() ?? '';
      return t.contains('door') && !t.contains('wardrobe');
    }).toList();
    expect(doors.length, greaterThanOrEqualTo(2));
    expect(
      doors.every((d) => d['wall']?.toString().toLowerCase() != 'west'),
      isTrue,
      reason: 'deep-room wardrobe is west — no door seed there',
    );
    final mesh = openings.where((o) {
      final t = o['type']?.toString().toLowerCase() ?? '';
      return t.contains('balcony');
    }).toList();
    expect(mesh, isNotEmpty);
    expect(mesh.first['wall']?.toString().toLowerCase(), 'north');
  });
}
