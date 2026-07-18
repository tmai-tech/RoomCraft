import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/layout/walkway_heatmap.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';

void main() {
  const pxf = 20.0;

  test('empty room is fully free walkway', () {
    final room = RoomModel(
      id: 'r1',
      name: 'Empty',
      widthInFeet: 12,
      lengthInFeet: 10,
    );
    final cells = WalkwayHeatmap.compute(room, pxf);
    expect(cells, isNotEmpty);
    expect(WalkwayHeatmap.freeFraction(cells), 1.0);
  });

  test('furniture blocks walkway cells under it', () {
    final room = RoomModel(
      id: 'r2',
      name: 'Blocked',
      widthInFeet: 12,
      lengthInFeet: 10,
      furniture: [
        FurnitureItem(
          id: 'sofa1',
          type: FurnitureType.sofa,
          position: const Offset(6 * pxf, 5 * pxf),
          widthInFeet: 7,
          lengthInFeet: 3,
        ),
      ],
    );
    final cells = WalkwayHeatmap.compute(room, pxf);
    expect(cells.any((c) => c.isBlocked), isTrue);
    expect(WalkwayHeatmap.freeFraction(cells), lessThan(1.0));
    expect(WalkwayHeatmap.freeFraction(cells), greaterThan(0.2));
  });
}
