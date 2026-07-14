import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/services/ar_measure_service.dart';

void main() {
  test('ArRoomMeasure.fromMap', () {
    final m = ArRoomMeasure.fromMap({
      'widthFt': 12.5,
      'lengthFt': 10.0,
      'widthM': 3.81,
      'lengthM': 3.05,
      'source': 'arcore',
    });
    expect(m.widthFt, 12.5);
    expect(m.lengthFt, 10.0);
    expect(m.source, 'arcore');
  });

  test('normalized puts larger side first', () {
    final m = const ArRoomMeasure(
      widthFt: 8,
      lengthFt: 14,
      widthM: 1,
      lengthM: 1,
    ).normalized;
    expect(m.widthFt, 14);
    expect(m.lengthFt, 8);
  });
}
