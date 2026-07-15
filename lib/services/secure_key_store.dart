import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// API keys in platform secure storage (with one-time prefs migration).
class SecureKeyStore {
  SecureKeyStore({
    FlutterSecureStorage? storage,
    SharedPreferences? prefs,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _prefsOverride = prefs;

  final FlutterSecureStorage _storage;
  final SharedPreferences? _prefsOverride;

  static const _geminiSecureKey = 'roomcraft_gemini_api_key';
  static const _groqSecureKey = 'roomcraft_groq_api_key';
  static const _hfSecureKey = 'roomcraft_hf_token';
  static const _migratedFlag = 'secure_keys_migrated_v1';

  Future<SharedPreferences> get _prefs async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  /// Move any legacy SharedPreferences keys into secure storage once.
  Future<void> migrateFromPrefsIfNeeded() async {
    final prefs = await _prefs;
    if (prefs.getBool(_migratedFlag) == true) return;

    final gemini = prefs.getString(AppConfig.apiKeyPrefKey)?.trim() ??
        prefs.getString(AppConfig.apiKeyLegacyPrefKey)?.trim();
    if (gemini != null && gemini.isNotEmpty) {
      final existing = await _storage.read(key: _geminiSecureKey);
      if (existing == null || existing.isEmpty) {
        await _storage.write(key: _geminiSecureKey, value: gemini);
      }
      await prefs.remove(AppConfig.apiKeyPrefKey);
      await prefs.remove(AppConfig.apiKeyLegacyPrefKey);
    }

    final groq = prefs.getString(AppConfig.groqApiKeyPrefKey)?.trim();
    if (groq != null && groq.isNotEmpty) {
      final existing = await _storage.read(key: _groqSecureKey);
      if (existing == null || existing.isEmpty) {
        await _storage.write(key: _groqSecureKey, value: groq);
      }
      await prefs.remove(AppConfig.groqApiKeyPrefKey);
    }

    await prefs.setBool(_migratedFlag, true);
  }

  Future<String?> loadGeminiKey() async {
    await migrateFromPrefsIfNeeded();
    final v = await _storage.read(key: _geminiSecureKey);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  Future<void> saveGeminiKey(String key) async {
    final t = key.trim();
    if (t.isEmpty) {
      await _storage.delete(key: _geminiSecureKey);
    } else {
      await _storage.write(key: _geminiSecureKey, value: t);
    }
    // Ensure plain prefs are cleared
    final prefs = await _prefs;
    await prefs.remove(AppConfig.apiKeyPrefKey);
    await prefs.remove(AppConfig.apiKeyLegacyPrefKey);
  }

  Future<String?> loadGroqKey() async {
    await migrateFromPrefsIfNeeded();
    final v = await _storage.read(key: _groqSecureKey);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  Future<void> saveGroqKey(String key) async {
    final t = key.trim();
    if (t.isEmpty) {
      await _storage.delete(key: _groqSecureKey);
    } else {
      await _storage.write(key: _groqSecureKey, value: t);
    }
    final prefs = await _prefs;
    await prefs.remove(AppConfig.groqApiKeyPrefKey);
  }

  Future<String?> loadHfToken() async {
    await migrateFromPrefsIfNeeded();
    final v = await _storage.read(key: _hfSecureKey);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  Future<void> saveHfToken(String key) async {
    final t = key.trim();
    if (t.isEmpty) {
      await _storage.delete(key: _hfSecureKey);
    } else {
      await _storage.write(key: _hfSecureKey, value: t);
    }
    final prefs = await _prefs;
    await prefs.remove(AppConfig.hfTokenPrefKey);
  }
}
