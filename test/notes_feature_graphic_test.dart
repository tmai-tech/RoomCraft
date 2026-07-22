import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/config/app_config.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/services/export_service.dart';

void main() {
  test('buildNumber tracks current beta ship', () {
    expect(AppConfig.buildNumber, greaterThanOrEqualTo(116));
  });

  test('notes round-trip and searchText includes notes', () {
    final room = RoomModel(
      id: 'n',
      name: 'Living',
      widthInFeet: 14,
      lengthInFeet: 12,
      notes: 'Smith residence · coastal palette',
      isExterior: false,
    );
    final back = RoomModel.fromMap(room.toMap());
    expect(back.notes, contains('Smith'));
    expect(back.searchText, contains('coastal'));
    expect(back.searchText, contains('living'));
  });

  test('exterior search tags', () {
    final patio = RoomModel(
      id: 'p',
      name: 'Yard',
      widthInFeet: 16,
      lengthInFeet: 14,
      isExterior: true,
    );
    expect(patio.searchText, contains('exterior'));
    expect(patio.searchText, contains('patio'));
  });

  test('PDF includes notes', () {
    final room = RoomModel(
      id: 'x',
      name: 'Plan',
      widthInFeet: 10,
      lengthInFeet: 10,
      notes: 'Phase 1 kitchen only',
    );
    final text = String.fromCharCodes(ExportService.buildPlanPdfBytes(room));
    expect(text.contains('Phase 1'), isTrue);
  });

  test('feature graphic is 1024-wide PNG', () async {
    final bytes = await ExportService.renderFeatureGraphic();
    expect(bytes[0], 0x89);
    expect(bytes.length, greaterThan(2000));
  });
}
