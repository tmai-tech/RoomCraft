import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/layout/auto_arrange.dart';
import 'package:room_craft/domain/layout/collision.dart';
import 'package:room_craft/domain/layout/furniture_bounds.dart';
import 'package:room_craft/domain/layout/layout_score.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  const pxf = 20.0;

  test('detects overlapping furniture', () {
    const a = FurnitureItem(
      id: 'a',
      type: FurnitureType.bed,
      position: Offset(100, 100),
      widthInFeet: 5,
      lengthInFeet: 6,
    );
    const b = FurnitureItem(
      id: 'b',
      type: FurnitureType.sofa,
      position: Offset(110, 100),
      widthInFeet: 6,
      lengthInFeet: 3,
    );
    final ids = Collision.overlappingIds([a, b], pxf);
    expect(ids, containsAll(['a', 'b']));
  });

  test('clamp keeps item in room', () {
    final room = FurnitureBounds.roomRect(10, 10, pxf);
    const item = FurnitureItem(
      id: 'x',
      type: FurnitureType.chair,
      position: Offset(-50, -50),
      widthInFeet: 2,
      lengthInFeet: 2,
    );
    final pos = FurnitureBounds.clampCenterInRoom(item, pxf, room);
    expect(pos.dx, greaterThan(0));
    expect(pos.dy, greaterThan(0));
  });

  test('bedroom auto-arrange produces non-overlapping items', () {
    final room = RoomModel(
      id: 'r',
      name: 'Test',
      widthInFeet: 12,
      lengthInFeet: 14,
    );
    final items = AutoArrange.arrange(
      room: room,
      pixelsPerFoot: pxf,
      type: RoomLayoutType.bedroom,
    );
    expect(items.length, greaterThanOrEqualTo(3));
    final ids = Collision.overlappingIds(items, pxf, padding: 0);
    expect(ids, isEmpty);
  });

  test('layout score penalizes overlaps', () {
    final room = RoomModel(
      id: 'r',
      name: 'T',
      widthInFeet: 12,
      lengthInFeet: 12,
      furniture: const [
        FurnitureItem(
          id: 'a',
          type: FurnitureType.bed,
          position: Offset(100, 100),
          widthInFeet: 5,
          lengthInFeet: 6,
        ),
        FurnitureItem(
          id: 'b',
          type: FurnitureType.sofa,
          position: Offset(105, 100),
          widthInFeet: 6,
          lengthInFeet: 3,
        ),
      ],
    );
    final score = LayoutScore.evaluate(room, pxf);
    expect(score.score, lessThan(100));
    expect(score.collisionIds, isNotEmpty);
    expect(score.tips, isNotEmpty);
  });

  test('door keep-out produces tip when blocked', () {
    final room = RoomModel(
      id: 'r',
      name: 'T',
      widthInFeet: 12,
      lengthInFeet: 12,
      strokes: [
        StrokeModel(
          id: 'd1',
          type: StrokeType.door,
          points: const [Offset(100, 0), Offset(140, 0)],
        ),
      ],
      furniture: const [
        FurnitureItem(
          id: 'a',
          type: FurnitureType.wardrobe,
          position: Offset(120, 30),
          widthInFeet: 4,
          lengthInFeet: 2,
        ),
      ],
    );
    final score = LayoutScore.evaluate(room, pxf);
    expect(
      score.tips.any((t) => t.message.toLowerCase().contains('door')),
      isTrue,
    );
  });

  test('OBB hit-test respects rotation', () {
    // 6×2 ft sofa at 90°: half-width 3ft→60px along world Y; half-depth 1ft→20px along world X
    const item = FurnitureItem(
      id: 'r',
      type: FurnitureType.sofa,
      position: Offset(100, 100),
      widthInFeet: 6,
      lengthInFeet: 2,
      rotationAngle: 1.57079632679, // 90°
    );
    // Along long axis after 90° (world Y), well inside half-width 60px
    final onLongAxis = Offset(100, 100 + 2.5 * pxf); // +50px
    expect(
      FurnitureBounds.containsPoint(item, onLongAxis, pxf, padPx: 0),
      isTrue,
    );
    // Along world X past half-depth 20px
    final outside = Offset(100 + 2 * pxf, 100); // +40px
    expect(
      FurnitureBounds.containsPoint(item, outside, pxf, padPx: 0),
      isFalse,
    );
  });

  test('separated items do not OBB-collide; same center does', () {
    const a = FurnitureItem(
      id: 'a',
      type: FurnitureType.table,
      position: Offset(100, 100),
      widthInFeet: 4,
      lengthInFeet: 1,
      rotationAngle: 0,
    );
    const b = FurnitureItem(
      id: 'b',
      type: FurnitureType.table,
      position: Offset(100, 160),
      widthInFeet: 4,
      lengthInFeet: 1,
      rotationAngle: 0,
    );
    expect(Collision.obbOverlap(a, b, pxf, padding: 0), isFalse);

    const c = FurnitureItem(
      id: 'c',
      type: FurnitureType.sofa,
      position: Offset(100, 100),
      widthInFeet: 3,
      lengthInFeet: 3,
      rotationAngle: 0.785398, // 45°
    );
    const d = FurnitureItem(
      id: 'd',
      type: FurnitureType.chair,
      position: Offset(100, 100),
      widthInFeet: 2,
      lengthInFeet: 2,
      rotationAngle: 0,
    );
    expect(Collision.obbOverlap(c, d, pxf, padding: 0), isTrue);
  });

  test('hit-test false for AABB side when item rotated out', () {
    const item = FurnitureItem(
      id: 't',
      type: FurnitureType.table,
      position: Offset(200, 200),
      widthInFeet: 4,
      lengthInFeet: 1,
      rotationAngle: 1.57079632679, // 90° — thin strip vertical
    );
    final side = Offset(200 + 1.8 * pxf, 200);
    expect(FurnitureBounds.containsPoint(item, side, pxf, padPx: 0), isFalse);
    final along = Offset(200, 200 + 1.5 * pxf);
    expect(FurnitureBounds.containsPoint(item, along, pxf, padPx: 0), isTrue);
  });
}
