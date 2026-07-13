import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/scan_keyframes.dart';

void main() {
  test('pickSharpest returns all when under limit', () async {
    // Empty list edge
    final r = await ScanKeyframes.pickSharpest([]);
    expect(r, isEmpty);
  });
}
