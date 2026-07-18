import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/config/app_config.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/services/export_service.dart';
import 'package:room_craft/services/prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('buildNumber is 103', () {
    expect(AppConfig.buildNumber, 103);
  });

  test('Play short description fits 80 chars', () {
    expect(AppConfig.playShortDescription.length, lessThanOrEqualTo(80));
    expect(AppConfig.playFullDescription, contains('AR'));
    expect(AppConfig.playFullDescription, contains('10,000'));
  });

  test('wallHeightFt round-trips on RoomModel', () {
    final room = RoomModel(
      id: 'w',
      name: 'Tall',
      widthInFeet: 12,
      lengthInFeet: 10,
      wallHeightFt: 9.5,
    );
    final back = RoomModel.fromMap(room.toMap());
    expect(back.wallHeightFt, closeTo(9.5, 0.01));
  });

  test('PDF includes wall height', () {
    final room = RoomModel(
      id: 'p',
      name: 'P',
      widthInFeet: 10,
      lengthInFeet: 10,
      wallHeightFt: 10,
    );
    final text = String.fromCharCodes(ExportService.buildPlanPdfBytes(room));
    expect(text.toLowerCase().contains('wall'), isTrue);
  });

  test('theme mode prefs persist', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PrefsService();
    await prefs.saveThemeMode(ThemeMode.dark);
    expect(await prefs.loadThemeMode(), ThemeMode.dark);
    await prefs.saveThemeMode(ThemeMode.light);
    expect(await prefs.loadThemeMode(), ThemeMode.light);
  });
}
