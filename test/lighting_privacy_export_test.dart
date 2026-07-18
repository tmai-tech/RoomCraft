import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/config/app_config.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/painters/isometric_painter.dart';
import 'package:room_craft/screens/privacy_data_safety_screen.dart';
import 'package:room_craft/services/export_service.dart';

void main() {
  test('AppConfig buildNumber is current beta ship', () {
    expect(AppConfig.buildNumber, greaterThanOrEqualTo(100));
    expect(AppConfig.versionLabel, contains('${AppConfig.buildNumber}'));
  });

  test('SceneLighting day/evening/night paint without throw', () {
    final room = RoomModel(
      id: 'r',
      name: 'Lit',
      widthInFeet: 12,
      lengthInFeet: 10,
      furniture: [
        FurnitureItem(
          id: 's',
          type: FurnitureType.sofa,
          position: const Offset(120, 100),
          widthInFeet: 7,
          lengthInFeet: 3,
        ),
      ],
    );
    for (final light in SceneLighting.values) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      IsometricPainter(
        room: room,
        pixelsPerFoot: 20,
        lighting: light,
      ).paint(canvas, const Size(400, 300));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    }
  });

  testWidgets('PrivacyDataSafetyScreen shows data safety sections', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PrivacyDataSafetyScreen()),
    );
    expect(find.text('Privacy & data safety'), findsOneWidget);
    expect(find.textContaining('Camera & photos'), findsOneWidget);
    expect(find.textContaining('on your device'), findsOneWidget);
    // Button is below fold on short test surfaces — scroll into view
    await tester.scrollUntilVisible(
      find.byKey(const Key('privacy_open_full_policy')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('privacy_open_full_policy')), findsOneWidget);
  });

  test('render3dPng with evening lighting produces non-empty PNG', () async {
    final room = RoomModel(
      id: 'e',
      name: 'Eve',
      widthInFeet: 10,
      lengthInFeet: 10,
      furniture: [
        FurnitureItem(
          id: 't',
          type: FurnitureType.table,
          position: const Offset(100, 100),
          widthInFeet: 3,
          lengthInFeet: 3,
        ),
      ],
    );
    final bytes = await ExportService.render3dPng(
      room,
      lighting: SceneLighting.evening,
    );
    expect(bytes.length, greaterThan(1000));
    // PNG magic
    expect(bytes[0], 0x89);
    expect(bytes[1], 0x50);
  });
}
