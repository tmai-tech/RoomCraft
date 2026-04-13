import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/room_model.dart';

class StorageService {
  static const String _storageKey = 'saved_rooms';

  Future<List<RoomModel>> loadRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_storageKey) ?? [];
    return jsonList
        .map((e) => RoomModel.fromMap(jsonDecode(e)))
        .toList();
  }

  Future<void> saveRoom(RoomModel room) async {
    final prefs = await SharedPreferences.getInstance();
    final rooms = await loadRooms();
    
    // Replace if exists, otherwise add
    final index = rooms.indexWhere((e) => e.id == room.id);
    if (index != -1) {
      rooms[index] = room;
    } else {
      rooms.add(room);
    }

    final jsonList = rooms.map((e) => jsonEncode(e.toMap())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }

  Future<void> deleteRoom(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final rooms = await loadRooms();
    rooms.removeWhere((e) => e.id == id);
    
    final jsonList = rooms.map((e) => jsonEncode(e.toMap())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }
}
