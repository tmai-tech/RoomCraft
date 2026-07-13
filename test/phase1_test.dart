import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/catalog/furniture_catalog.dart';
import 'package:room_craft/domain/layout/snap.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/services/export_service.dart';

void main() {
  test('catalog has 30+ entries and search works', () {
    expect(FurnitureCatalog.all.length, greaterThanOrEqualTo(30));
    final beds = FurnitureCatalog.search('bed');
    expect(beds, isNotEmpty);
    expect(beds.every((e) => e.label.toLowerCase().contains('bed') || e.id.contains('bed') || e.description.toLowerCase().contains('bed') || e.type == FurnitureType.bed || e.category == FurnitureCategory.sleep), isTrue);
  });

  test('snap pulls item toward wall', () {
    const pxf = 20.0;
    final room = RoomModel(id: 'r', name: 'T', widthInFeet: 12, lengthInFeet: 12);
    const item = FurnitureItem(
      id: 'a',
      type: FurnitureType.sofa,
      position: Offset(25, 100), // near left wall (halfW of 6ft sofa = 60px)
      widthInFeet: 6,
      lengthInFeet: 3,
    );
    final snapped = FurnitureSnap.snap(
      item: item,
      room: room,
      pixelsPerFoot: pxf,
      others: const [],
      thresholdPx: 40,
    );
    // Should snap center so left edge near 0 → center ~ 60
    expect(snapped.dx, closeTo(60, 5));
  });

  test('pdf bytes start with PDF header', () {
    final room = RoomModel(id: 'r', name: 'Test Plan', widthInFeet: 10, lengthInFeet: 10);
    final bytes = ExportService.buildPlanPdfBytes(room);
    final header = String.fromCharCodes(bytes.take(8));
    expect(header.startsWith('%PDF'), isTrue);
  });
}
