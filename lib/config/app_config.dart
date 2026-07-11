/// App-wide constants for RoomCraft MVP / closed beta.
class AppConfig {
  static const String appName = 'RoomCraft';
  static const String packageId = 'com.logicrequire.room_craft';

  /// Display version (keep in sync with pubspec.yaml).
  static const String appVersion = '1.0.0-beta.1';
  static const int buildNumber = 2;
  static const bool isBeta = true;

  /// Feedback — opens mail client on device.
  static const String feedbackEmail = 'prjoshi0711@gmail.com';
  static const String feedbackSubject = 'RoomCraft beta feedback';

  /// Docs (GitHub raw / tree).
  static const String privacyPolicyUrl =
      'https://raw.githubusercontent.com/tmai-tech/RoomCraft/dev/PRIVACY_POLICY.md';
  static const String knownIssuesUrl =
      'https://github.com/tmai-tech/RoomCraft/blob/dev/docs/KNOWN_ISSUES.md';
  static const String changelogUrl =
      'https://github.com/tmai-tech/RoomCraft/blob/dev/CHANGELOG.md';

  /// Local project storage schema. Bump when [RoomModel] JSON shape changes.
  static const int storageSchemaVersion = 1;

  /// SharedPreferences keys.
  static const String roomsStorageKey = 'saved_rooms_v1';
  static const String roomsLegacyKey = 'saved_rooms';
  static const String apiKeyPrefKey = 'gemini_api_key';
  static const String apiKeyLegacyPrefKey = 'openai_api_key';
  static const String unitsPrefKey = 'unit_system';
  static const String onboardingDoneKey = 'onboarding_done_v1';
  static const String betaBannerDismissedKey = 'beta_banner_dismissed_v1';

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

  /// Furniture rotate snap (degrees).
  static const double rotateSnapDegrees = 45.0;

  static String get versionLabel =>
      isBeta ? '$appVersion+$buildNumber (beta)' : '$appVersion+$buildNumber';
}
