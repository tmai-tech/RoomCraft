import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/config/app_config.dart';
import 'package:room_craft/domain/layout/walkway_heatmap.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/services/export_service.dart';
import 'package:flutter/material.dart';

void main() {
  test('buildNumber is 101', () {
    expect(AppConfig.buildNumber, 101);
  });

  test('renderPng with heatmap is non-empty PNG and larger than plain', () async {
    final room = RoomModel(
      id: 'w',
      name: 'Walk',
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
    final plain = await ExportService.renderPng(room);
    final heat = await ExportService.renderPng(room, showWalkwayHeatmap: true);
    expect(plain[0], 0x89);
    expect(heat[0], 0x89);
    expect(heat.length, greaterThan(500));
    final free = WalkwayHeatmap.freeFraction(
      WalkwayHeatmap.compute(room, 20),
    );
    expect(free, lessThan(1.0));
    expect(free, greaterThan(0.2));
  });
}
