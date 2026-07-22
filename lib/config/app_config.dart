/// App-wide constants for RoomCraft MVP / closed beta.
class AppConfig {
  static const String appName = 'RoomCraft';
  static const String packageId = 'com.logicrequire.room_craft';

  /// Display version (keep in sync with pubspec.yaml `version: x.y.z+build`).
  static const String appVersion = '1.0.0-beta.1';
  /// Must match pubspec `+NNN` — feedback / Settings use this (not package_info).
  static const int buildNumber = 116;
  static const bool isBeta = true;

  /// Firebase Google Sign-In Web client ID (oauth_client client_type 3).
  /// Pass at build time after adding SHA fingerprints in Firebase Console:
  ///   --dart-define=ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
  static const String googleServerClientId = String.fromEnvironment(
    'ROOMCRAFT_GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

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
  static const String groqApiKeyPrefKey = 'groq_api_key';
  static const String hfTokenPrefKey = 'hf_token';
  static const String unitsPrefKey = 'unit_system';
  static const String onboardingDoneKey = 'onboarding_done_v1';
  static const String betaBannerDismissedKey = 'beta_banner_dismissed_v1';
  static const String themeModePrefKey = 'theme_mode_v1';

  /// Default interior wall height (feet) — Planner-style room property.
  static const double defaultWallHeightFt = 8.0;

  /// Play listing short description (≤80 chars for store form).
  static const String playShortDescription =
      'AR room planner: measure, arrange 10k+ free décor, explore in 3D.';

  /// Play listing full description (paste into Play Console).
  static const String playFullDescription = '''
RoomCraft is a free-first room planner for real homes.

• AR Room Planner — measure real floors with ARCore, place furniture on plan or camera
• 10,000+ free furniture catalogue with marketplace-style collections
• AI Furnisher & Styler on-device (no paid CAD required)
• 2D blueprint with walkway heatmap, layout score, L-shape floors
• 3D perspective walkthrough with day/evening/night lighting
• Multi-floor levels and exterior patio plans
• Export PNG, heatmap, PDF, 2D+3D plan pack, store screenshots

Plans stay on your device. Optional free vision and cloud backup when you enable them.
''';

  /// Gemini models tried in order (404 / not-found → next).
  static const List<String> geminiModelCandidates = [
    'gemini-2.0-flash',
    'gemini-1.5-flash',
    'gemini-1.5-flash-latest',
    'gemini-2.5-flash',
  ];

  /// Free-tier multimodal vision (Groq Llama 4 Scout).
  static const String groqChatCompletionsUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String groqVisionModel =
      'meta-llama/llama-4-scout-17b-16e-instruct';

  /// Hugging Face Inference Providers (OpenAI-compatible router).
  /// Free-tier credits on HF account; open VLMs for room layout JSON.
  static const String hfChatCompletionsUrl =
      'https://router.huggingface.co/v1/chat/completions';
  /// Tried in order when a model/provider is unavailable.
  static const List<String> hfVisionModelCandidates = [
    'Qwen/Qwen2.5-VL-3B-Instruct',
    'Qwen/Qwen2.5-VL-7B-Instruct',
    'Qwen/Qwen3-VL-4B-Instruct',
  ];

  /// Optional app-bundled keys so testers never paste a key.
  /// Pass at build/run time:
  ///   flutter run --dart-define=ROOMCRAFT_GROQ_API_KEY=gsk_...
  ///   flutter build apk --dart-define=ROOMCRAFT_GEMINI_API_KEY=...
  ///   flutter build apk --dart-define=ROOMCRAFT_HF_TOKEN=hf_...
  /// Empty string = not set (offline accurate plan still works).
  static const String bundledGroqApiKey = String.fromEnvironment(
    'ROOMCRAFT_GROQ_API_KEY',
    defaultValue: '',
  );
  static const String bundledGeminiApiKey = String.fromEnvironment(
    'ROOMCRAFT_GEMINI_API_KEY',
    defaultValue: '',
  );
  static const String bundledHfToken = String.fromEnvironment(
    'ROOMCRAFT_HF_TOKEN',
    defaultValue: '',
  );

  static bool get hasBundledFreeVision =>
      bundledGroqApiKey.trim().isNotEmpty ||
      bundledGeminiApiKey.trim().isNotEmpty ||
      bundledHfToken.trim().isNotEmpty;

  static const double defaultPixelsPerFoot = 20.0;
  static const double defaultRoomWidthFt = 10.0;
  static const double defaultRoomLengthFt = 10.0;

  /// Pixel inset so the room outline is not glued to the canvas top-left.
  /// Lets users draw the left/top walls without fighting the screen edge.
  /// +113: larger inset (was 56) — feedback 7be5dbfd left edge stuck.
  static const double canvasOriginPx = 80.0;

  /// Furniture rotate snap (degrees).
  static const double rotateSnapDegrees = 45.0;

  static String get versionLabel =>
      isBeta ? '$appVersion+$buildNumber (beta)' : '$appVersion+$buildNumber';
}
