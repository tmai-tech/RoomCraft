import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/units.dart';

class PrefsService {
  PrefsService({SharedPreferences? prefs}) : _override = prefs;
  final SharedPreferences? _override;

  Future<SharedPreferences> get _prefs async =>
      _override ?? await SharedPreferences.getInstance();

  Future<UnitSystem> loadUnitSystem() async {
    final prefs = await _prefs;
    final raw = prefs.getString(AppConfig.unitsPrefKey);
    if (raw == 'meters') return UnitSystem.meters;
    return UnitSystem.feet;
  }

  Future<void> saveUnitSystem(UnitSystem unit) async {
    final prefs = await _prefs;
    await prefs.setString(
      AppConfig.unitsPrefKey,
      unit == UnitSystem.meters ? 'meters' : 'feet',
    );
  }

  Future<bool> isOnboardingDone() async {
    final prefs = await _prefs;
    return prefs.getBool(AppConfig.onboardingDoneKey) ?? false;
  }

  Future<void> setOnboardingDone(bool done) async {
    final prefs = await _prefs;
    await prefs.setBool(AppConfig.onboardingDoneKey, done);
  }


  Future<bool> isBetaBannerDismissed() async {
    final prefs = await _prefs;
    return prefs.getBool(AppConfig.betaBannerDismissedKey) ?? false;
  }

  Future<void> setBetaBannerDismissed(bool dismissed) async {
    final prefs = await _prefs;
    await prefs.setBool(AppConfig.betaBannerDismissedKey, dismissed);
  }

  /// system | light | dark
  Future<ThemeMode> loadThemeMode() async {
    final prefs = await _prefs;
    switch (prefs.getString(AppConfig.themeModePrefKey)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await _prefs;
    final raw = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(AppConfig.themeModePrefKey, raw);
  }
}
