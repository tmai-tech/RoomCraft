import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/layout/room_geometry.dart';
import 'package:room_craft/domain/layout/sample_plans.dart';
import 'package:room_craft/domain/layout/walkway_heatmap.dart';
import 'package:room_craft/models/room_model.dart';

void main() {
  test('L-shape vertices form closed 6-point polygon inside bounding box', () {
    final poly = RoomGeometry.lShapeVerticesFt(widthFt: 12, lengthFt: 10);
    expect(poly, hasLength(6));
    expect(RoomGeometry.containsPoint(poly, const Offset(1, 1)), isTrue);
    // Cutout NE should be outside (near top-right of cut)
    expect(RoomGeometry.containsPoint(poly, const Offset(11, 9)), isFalse);
    expect(RoomGeometry.polygonAreaFt(poly), lessThan(12 * 10));
    expect(RoomGeometry.polygonAreaFt(poly), greaterThan(12 * 10 * 0.4));
  });

  test('RoomModel round-trips floorPolygonFt', () {
    final poly = RoomGeometry.lShapeVerticesFt(widthFt: 14, lengthFt: 12);
    final room = RoomModel(
      id: 'x',
      name: 'L',
      widthInFeet: 14,
      lengthInFeet: 12,
      floorPolygonFt: poly,
    );
    final back = RoomModel.fromMap(room.toMap());
    expect(back.isPolygonFloor, isTrue);
    expect(back.floorPolygonFt, hasLength(6));
  });

  test('L-shape gallery plan materializes with polygon floor', () {
    final plan = SamplePlans.all.firstWhere((p) => p.id == 'l_living');
    final room = SamplePlans.materialize(plan);
    expect(room.isPolygonFloor, isTrue);
    expect(room.furniture, isNotEmpty);
    final cells = WalkwayHeatmap.compute(room, 20);
    expect(cells, isNotEmpty);
    // Heatmap only covers polygon, not full AABB
    final aabbCells = WalkwayHeatmap.compute(
      RoomModel(
        id: 'r',
        name: 'R',
        widthInFeet: room.widthInFeet,
        lengthInFeet: room.lengthInFeet,
      ),
      20,
    );
    expect(cells.length, lessThan(aabbCells.length));
  });
}
