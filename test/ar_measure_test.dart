import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/services/ar_measure_service.dart';

void main() {
  test('ArRoomMeasure.fromMap quick', () {
    final m = ArRoomMeasure.fromMap({
      'widthFt': 12.5,
      'lengthFt': 10.0,
      'widthM': 3.81,
      'lengthM': 3.05,
      'source': 'arcore',
      'mode': 'quick',
      'wallsFt': [12.5, 10.0],
    });
    expect(m.widthFt, 12.5);
    expect(m.isChain, isFalse);
    expect(m.wallsFt.length, 2);
  });

  test('chain opposite wall error', () {
    final m = ArRoomMeasure.fromMap({
      'widthFt': 12.0,
      'lengthFt': 14.0,
      'widthM': 1,
      'lengthM': 1,
      'mode': 'chain',
      'wallsFt': [12.0, 14.0, 11.0, 14.5], // A,B,C,D
    });
    expect(m.isChain, isTrue);
    expect(m.oppositeWallError, greaterThan(0.05));
    expect(m.summaryLabel, contains('4-wall'));
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
