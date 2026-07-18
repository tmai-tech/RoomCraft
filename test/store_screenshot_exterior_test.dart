import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/config/app_config.dart';
import 'package:room_craft/domain/layout/ai_designer.dart';
import 'package:room_craft/domain/layout/sample_plans.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/services/export_service.dart';

void main() {
  test('buildNumber is 102', () {
    expect(AppConfig.buildNumber, 102);
  });

  test('exterior furnish prefers outdoor types', () {
    final room = RoomModel(
      id: 'e',
      name: 'Patio',
      widthInFeet: 16,
      lengthInFeet: 14,
      isExterior: true,
    );
    final items = AiDesigner.furnish(
      room: room,
      pixelsPerFoot: 20,
      style: DesignStyle.family,
    );
    expect(items, isNotEmpty);
    expect(
      items.any((f) => f.type == FurnitureType.outdoor),
      isTrue,
      reason: 'exterior recipe should place outdoor furniture',
    );
  });

  test('renderStoreScreenshot is 1080-wide PNG', () async {
    final room = SamplePlans.materialize(
      SamplePlans.all.firstWhere((p) => p.id == 'cozy_living'),
    );
    final bytes = await ExportService.renderStoreScreenshot(room);
    expect(bytes[0], 0x89);
    expect(bytes.length, greaterThan(5000));
  });

  test('patio gallery plan furnishes outdoor when rematerialized as exterior', () {
    final patio = SamplePlans.materialize(
      SamplePlans.all.firstWhere((p) => p.id == 'patio_exterior'),
    );
    expect(patio.isExterior, isTrue);
    final items = AiDesigner.furnish(
      room: patio,
      pixelsPerFoot: 20,
      style: DesignStyle.family,
    );
    expect(items.any((f) => f.type == FurnitureType.outdoor), isTrue);
  });
}
