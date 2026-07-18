import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/layout/clearances.dart';
import 'package:room_craft/domain/layout/furniture_bounds.dart';
import 'package:room_craft/domain/layout/room_geometry.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/services/export_service.dart';

void main() {
  const pxf = 20.0;

  test('clampCenterInRoom pulls cutout placement into L-shape', () {
    final polyFt = RoomGeometry.lShapeVerticesFt(widthFt: 12, lengthFt: 10);
    final polyPx = RoomGeometry.toPixels(polyFt, pxf);
    final roomR = FurnitureBounds.roomRect(12, 10, pxf);
    // Point in NE cutout (~11ft, 9ft)
    final item = FurnitureItem(
      id: 't',
      type: FurnitureType.table,
      position: Offset(11 * pxf, 9 * pxf),
      widthInFeet: 2,
      lengthInFeet: 2,
    );
    final clamped = FurnitureBounds.clampCenterInRoom(
      item,
      pxf,
      roomR,
      floorPolygonPx: polyPx,
    );
    expect(RoomGeometry.containsPoint(polyPx, clamped), isTrue);
  });

  test('clearances flags furniture outside L floor', () {
    final poly = RoomGeometry.lShapeVerticesFt(widthFt: 12, lengthFt: 10);
    final room = RoomModel(
      id: 'r',
      name: 'L',
      widthInFeet: 12,
      lengthInFeet: 10,
      floorPolygonFt: poly,
      furniture: [
        FurnitureItem(
          id: 'bad',
          type: FurnitureType.chair,
          position: Offset(11 * pxf, 9 * pxf),
          widthInFeet: 2,
          lengthInFeet: 2,
        ),
      ],
    );
    final tips = Clearances.analyze(room, pxf);
    expect(
      tips.any((t) => t.message.contains('outside the L-shape')),
      isTrue,
    );
  });

  test('PDF includes shape line for L-shape rooms', () {
    final poly = RoomGeometry.lShapeVerticesFt(widthFt: 14, lengthFt: 12);
    final room = RoomModel(
      id: 'p',
      name: 'L plan',
      widthInFeet: 14,
      lengthInFeet: 12,
      floorPolygonFt: poly,
    );
    final pdf = ExportService.buildPlanPdfBytes(room);
    final text = String.fromCharCodes(pdf);
    expect(text.contains('L-shape') || text.contains('polygon'), isTrue);
    expect(pdf.length, greaterThan(100));
  });
}
