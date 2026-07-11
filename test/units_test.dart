import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/units.dart';

void main() {
  test('feet display identity', () {
    expect(LengthFormat.feetToDisplay(10, UnitSystem.feet), 10);
    expect(LengthFormat.formatFeet(10, UnitSystem.feet), '10.0 ft');
  });

  test('meters conversion round-trip', () {
    final m = LengthFormat.feetToDisplay(10, UnitSystem.meters);
    expect(m, closeTo(3.048, 0.001));
    expect(LengthFormat.displayToFeet(m, UnitSystem.meters), closeTo(10, 0.001));
  });

  test('area format', () {
    expect(LengthFormat.formatAreaSqFt(100, UnitSystem.feet), '100.0 sq ft');
    expect(LengthFormat.formatAreaSqFt(100, UnitSystem.meters), contains('m²'));
  });
}
