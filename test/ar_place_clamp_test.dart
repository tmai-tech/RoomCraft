import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/services/ar_measure_service.dart';

void main() {
  test('ArPlacedItem.clampedToRoom keeps points inside measured room', () {
    const outside = ArPlacedItem(
      type: 'sofa',
      fromLeftFt: 99,
      fromBottomFt: -3,
    );
    final c = outside.clampedToRoom(12, 14);
    expect(c.fromLeftFt, 12);
    expect(c.fromBottomFt, 3); // abs then clamp
    expect(c.type, 'sofa');
  });

  test('ArPlacedItem.clampedToRoom leaves interior points alone', () {
    const inside = ArPlacedItem(
      type: 'chair',
      fromLeftFt: 4.5,
      fromBottomFt: 6.0,
    );
    final c = inside.clampedToRoom(12, 14);
    expect(c.fromLeftFt, 4.5);
    expect(c.fromBottomFt, 6.0);
  });
}
