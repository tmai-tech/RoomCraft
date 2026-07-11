import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/models/room_model.dart';

void main() {
  test('tryFromMap returns null for missing id', () {
    expect(RoomModel.tryFromMap({'name': 'x'}), isNull);
  });

  test('round-trip toMap/fromMap', () {
    final room = RoomModel(
      id: '1',
      name: 'Test',
      lengthInFeet: 14,
      widthInFeet: 11,
    );
    final again = RoomModel.fromMap(room.toMap());
    expect(again.id, room.id);
    expect(again.lengthInFeet, 14);
    expect(again.widthInFeet, 11);
  });
}
