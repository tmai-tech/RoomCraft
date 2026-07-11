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
}
