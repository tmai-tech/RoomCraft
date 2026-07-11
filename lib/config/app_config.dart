/// App-wide constants for RoomCraft MVP.
class AppConfig {
  static const String appName = 'RoomCraft';
  static const String packageId = 'com.logicrequire.room_craft';

  /// Local project storage schema. Bump when [RoomModel] JSON shape changes.
  static const int storageSchemaVersion = 1;

  /// SharedPreferences keys.
  static const String roomsStorageKey = 'saved_rooms_v1';
  static const String roomsLegacyKey = 'saved_rooms';
  static const String apiKeyPrefKey = 'gemini_api_key';
  static const String apiKeyLegacyPrefKey = 'openai_api_key';

  /// Gemini models tried in order (404 / not-found → next).
  static const List<String> geminiModelCandidates = [
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.5-flash-latest',
    'gemini-2.5-flash',
  ];

  static const double defaultPixelsPerFoot = 20.0;
  static const double defaultRoomWidthFt = 20.0;
  static const double defaultRoomLengthFt = 20.0;
}
