import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'package:uuid/uuid.dart';

import '../models/room_model.dart';

/// Versioned local project storage with legacy migration and corrupt-entry skip.
class StorageService {
  /// Optional prefs injection for unit tests.
  StorageService({SharedPreferences? prefs}) : _prefsOverride = prefs;

  final SharedPreferences? _prefsOverride;

  Future<SharedPreferences> get _prefs async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  Future<List<RoomModel>> loadRooms() async {
    final prefs = await _prefs;
    await _migrateLegacyIfNeeded(prefs);

    final envelope = prefs.getString(AppConfig.roomsStorageKey);
    if (envelope == null || envelope.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(envelope);
      if (decoded is Map<String, dynamic>) {
        return _roomsFromEnvelope(decoded);
      }
      if (decoded is Map) {
        return _roomsFromEnvelope(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // fall through — try legacy list shape under new key
    }

    // Extremely defensive: string list under v1 key
    final list = prefs.getStringList(AppConfig.roomsStorageKey);
    if (list != null) {
      return _roomsFromStringList(list);
    }
    return [];
  }

  Future<void> saveRoom(RoomModel room) async {
    final rooms = await loadRooms();
    room.updatedAt = DateTime.now();
    room.schemaVersion = AppConfig.storageSchemaVersion;

    final index = rooms.indexWhere((e) => e.id == room.id);
    if (index != -1) {
      rooms[index] = room;
    } else {
      rooms.add(room);
    }
    await _persist(rooms);
  }

  Future<void> deleteRoom(String id) async {
    final rooms = await loadRooms();
    rooms.removeWhere((e) => e.id == id);
    await _persist(rooms);
  }

  Future<void> saveAll(List<RoomModel> rooms) async {
    await _persist(rooms);
  }

  /// Copy a room with a new id and "Copy of …" name.
  Future<RoomModel> duplicateRoom(RoomModel source, {String? newId}) async {
    final room = RoomModel(
      id: newId ?? const Uuid().v4(),
      name: source.name.startsWith('Copy of ')
          ? source.name
          : 'Copy of ${source.name}',
      lengthInFeet: source.lengthInFeet,
      widthInFeet: source.widthInFeet,
      strokes: List.of(source.strokes),
      furniture: List.of(source.furniture),
      userId: source.userId,
      schemaVersion: AppConfig.storageSchemaVersion,
      updatedAt: DateTime.now(),
      floorPolygonFt: source.floorPolygonFt == null
          ? null
          : List.of(source.floorPolygonFt!),
      floorLevel: source.floorLevel,
      isExterior: source.isExterior,
      wallHeightFt: source.wallHeightFt,
    );
    await saveRoom(room);
    return room;
  }

  /// Multi-floor free path: same footprint one storey up.
  Future<RoomModel> duplicateAsUpperFloor(RoomModel source) async {
    final nextLevel = source.floorLevel + 1;
    final baseName = source.name
        .replaceFirst(RegExp(r'\s*[·•]\s*Floor\s+\d+\s*$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*\(Floor\s+\d+\)\s*$', caseSensitive: false), '')
        .trim();
    final room = RoomModel(
      id: const Uuid().v4(),
      name: '$baseName · Floor $nextLevel',
      lengthInFeet: source.lengthInFeet,
      widthInFeet: source.widthInFeet,
      strokes: List.of(source.strokes),
      furniture: List.of(source.furniture),
      userId: source.userId,
      schemaVersion: AppConfig.storageSchemaVersion,
      updatedAt: DateTime.now(),
      floorPolygonFt: source.floorPolygonFt == null
          ? null
          : List.of(source.floorPolygonFt!),
      floorLevel: nextLevel,
      isExterior: false,
      wallHeightFt: source.wallHeightFt,
    );
    await saveRoom(room);
    return room;
  }

  Future<void> _persist(List<RoomModel> rooms) async {
    final prefs = await _prefs;
    final envelope = <String, dynamic>{
      'schemaVersion': AppConfig.storageSchemaVersion,
      'rooms': rooms.map((r) {
        r.schemaVersion = AppConfig.storageSchemaVersion;
        return r.toMap();
      }).toList(),
    };
    await prefs.setString(AppConfig.roomsStorageKey, jsonEncode(envelope));
  }

  Future<void> _migrateLegacyIfNeeded(SharedPreferences prefs) async {
    if (prefs.containsKey(AppConfig.roomsStorageKey)) return;

    final legacyList = prefs.getStringList(AppConfig.roomsLegacyKey);
    if (legacyList == null || legacyList.isEmpty) return;

    final rooms = _roomsFromStringList(legacyList);
    await _persist(rooms);
    // Keep legacy key for one release cycle (read-only fallback already handled).
  }

  List<RoomModel> _roomsFromEnvelope(Map<String, dynamic> envelope) {
    final rawRooms = envelope['rooms'];
    if (rawRooms is! List) return [];
    final out = <RoomModel>[];
    for (final item in rawRooms) {
      if (item is Map<String, dynamic>) {
        final room = RoomModel.tryFromMap(item);
        if (room != null) out.add(room);
      } else if (item is Map) {
        final room = RoomModel.tryFromMap(Map<String, dynamic>.from(item));
        if (room != null) out.add(room);
      }
    }
    // Newest first
    out.sort((a, b) {
      final aT = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bT = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bT.compareTo(aT);
    });
    return out;
  }

  List<RoomModel> _roomsFromStringList(List<String> jsonList) {
    final out = <RoomModel>[];
    for (final e in jsonList) {
      try {
        final decoded = jsonDecode(e);
        if (decoded is Map<String, dynamic>) {
          final room = RoomModel.tryFromMap(decoded);
          if (room != null) out.add(room);
        } else if (decoded is Map) {
          final room = RoomModel.tryFromMap(Map<String, dynamic>.from(decoded));
          if (room != null) out.add(room);
        }
      } catch (_) {
        // skip corrupt entry
      }
    }
    return out;
  }
}
