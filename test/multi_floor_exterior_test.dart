import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/layout/sample_plans.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/services/export_service.dart';
import 'package:room_craft/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('RoomModel round-trips floorLevel and isExterior', () {
    final room = RoomModel(
      id: 'a',
      name: 'Patio',
      widthInFeet: 12,
      lengthInFeet: 10,
      floorLevel: 0,
      isExterior: true,
    );
    final back = RoomModel.fromMap(room.toMap());
    expect(back.isExterior, isTrue);
    expect(back.floorLevel, 0);
    expect(back.spaceLabel, 'Exterior');
  });

  test('spaceLabel for upper floor', () {
    final room = RoomModel(
      id: 'b',
      name: 'Loft',
      widthInFeet: 12,
      lengthInFeet: 10,
      floorLevel: 2,
    );
    expect(room.spaceLabel, 'Floor 2');
  });

  test('gallery patio is exterior; upper loft is floor 1', () {
    final patio = SamplePlans.materialize(
      SamplePlans.all.firstWhere((p) => p.id == 'patio_exterior'),
    );
    expect(patio.isExterior, isTrue);
    expect(patio.spaceLabel, 'Exterior');
    expect(patio.furniture, isNotEmpty);

    final loft = SamplePlans.materialize(
      SamplePlans.all.firstWhere((p) => p.id == 'upper_loft'),
    );
    expect(loft.floorLevel, 1);
    expect(loft.spaceLabel, 'Floor 1');
  });

  test('duplicateAsUpperFloor increments level', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    final ground = RoomModel(
      id: 'g1',
      name: 'Living',
      widthInFeet: 14,
      lengthInFeet: 12,
      floorLevel: 0,
    );
    await storage.saveRoom(ground);
    final upper = await storage.duplicateAsUpperFloor(ground);
    expect(upper.floorLevel, 1);
    expect(upper.spaceLabel, 'Floor 1');
    expect(upper.id, isNot(ground.id));
    expect(upper.name, contains('Floor 1'));
  });

  test('PDF includes Level line', () {
    final room = RoomModel(
      id: 'p',
      name: 'Plan',
      widthInFeet: 10,
      lengthInFeet: 10,
      floorLevel: 1,
      isExterior: false,
    );
    final pdf = String.fromCharCodes(ExportService.buildPlanPdfBytes(room));
    expect(pdf.contains('Floor 1') || pdf.contains('Level'), isTrue);
  });
}
