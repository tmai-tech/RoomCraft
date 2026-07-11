import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:room_craft/config/app_config.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('save and load room with schema v1 envelope', () async {
    final service = StorageService();
    final room = RoomModel(
      id: 'r1',
      name: 'Living',
      lengthInFeet: 12,
      widthInFeet: 10,
      furniture: [
        const FurnitureItem(
          id: 'f1',
          type: FurnitureType.sofa,
          position: Offset(40, 40),
          widthInFeet: 6,
          lengthInFeet: 3,
        ),
      ],
    );

    await service.saveRoom(room);
    final loaded = await service.loadRooms();
    expect(loaded.length, 1);
    expect(loaded.first.id, 'r1');
    expect(loaded.first.name, 'Living');
    expect(loaded.first.furniture.length, 1);
    expect(loaded.first.schemaVersion, AppConfig.storageSchemaVersion);
  });

  test('migrates legacy string-list storage', () async {
    final legacyRoom = RoomModel(
      id: 'legacy1',
      name: 'Old Room',
      lengthInFeet: 15,
      widthInFeet: 12,
    );
    SharedPreferences.setMockInitialValues({
      AppConfig.roomsLegacyKey: [jsonEncode(legacyRoom.toMap())],
    });

    final service = StorageService();
    final loaded = await service.loadRooms();
    expect(loaded.length, 1);
    expect(loaded.first.id, 'legacy1');
  });

  test('skips corrupt entries without throwing', () async {
    SharedPreferences.setMockInitialValues({
      AppConfig.roomsStorageKey: jsonEncode({
        'schemaVersion': 1,
        'rooms': [
          {'id': 'good', 'name': 'Good', 'lengthInFeet': 10, 'widthInFeet': 10},
          {'broken': true},
          'not-a-map',
        ],
      }),
    });

    final service = StorageService();
    final loaded = await service.loadRooms();
    expect(loaded.length, 1);
    expect(loaded.first.id, 'good');
  });

  test('deleteRoom removes by id', () async {
    final service = StorageService();
    await service.saveRoom(
      RoomModel(id: 'a', name: 'A', lengthInFeet: 1, widthInFeet: 1),
    );
    await service.saveRoom(
      RoomModel(id: 'b', name: 'B', lengthInFeet: 1, widthInFeet: 1),
    );
    await service.deleteRoom('a');
    final loaded = await service.loadRooms();
    expect(loaded.map((r) => r.id), ['b']);
  });
}
