import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/wall_relative_scan.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('compose places door on south wall from facing fractions', () {
    // Facing south: left = east (x=w). t0=0.3 t1=0.5 → x from 7 to 5 on 10ft wall
    final result = WallRelativeComposer.compose(
      widthFt: 10,
      lengthFt: 12,
      openings: const [
        WallOpeningHint(
          wall: WallSide.south,
          type: StrokeType.door,
          t0: 0.3,
          t1: 0.5,
          confidence: 0.95,
        ),
      ],
      wallPhotos: 1,
    );
    expect(result.roomWidthFt, 10);
    expect(result.roomLengthFt, 12);
    final doors = result.walls.where((w) => w.type == StrokeType.door);
    expect(doors, isNotEmpty);
    final d = doors.first;
    expect(d.startFt.dy, 0);
    expect(d.endFt.dy, 0);
    // mid of door ~ x=6 (between 5 and 7)
    final midX = (d.startFt.dx + d.endFt.dx) / 2;
    expect(midX, closeTo(6.0, 0.5));
    expect(d.lengthFt, closeTo(2.0, 0.5));
  });

  test('fromLeft tape measure places door correctly on south wall', () {
    // 10 ft wall, door starts 2 ft from left (east), 3 ft wide → x from 8 to 5
    final result = WallRelativeComposer.compose(
      widthFt: 10,
      lengthFt: 12,
      openings: [
        WallOpeningHint.fromLeft(
          wall: WallSide.south,
          type: StrokeType.door,
          fromLeftFt: 2,
          widthFt: 3,
          wallLengthFt: 10,
        ),
      ],
      fromTapeMeasure: true,
    );
    final doors = result.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors, hasLength(1));
    final d = doors.first;
    expect(d.startFt.dy, 0);
    final midX = (d.startFt.dx + d.endFt.dx) / 2;
    // left edge x=8, right edge x=5, mid=6.5
    expect(midX, closeTo(6.5, 0.3));
    expect(d.lengthFt, closeTo(3.0, 0.2));
  });

  test('fromLeft places door on north wall (left = west)', () {
    final result = WallRelativeComposer.compose(
      widthFt: 10,
      lengthFt: 12,
      openings: [
        WallOpeningHint.fromLeft(
          wall: WallSide.north,
          type: StrokeType.window,
          fromLeftFt: 1,
          widthFt: 4,
          wallLengthFt: 10,
        ),
      ],
      fromTapeMeasure: true,
    );
    final wins = result.walls.where((w) => w.type == StrokeType.window).toList();
    expect(wins, hasLength(1));
    final w = wins.first;
    expect(w.startFt.dy, 12);
    expect(w.endFt.dy, 12);
    final midX = (w.startFt.dx + w.endFt.dx) / 2;
    // from left 1, width 4 → x 1..5, mid 3
    expect(midX, closeTo(3.0, 0.3));
  });

  test('compose places sofa against east wall', () {
    final result = WallRelativeComposer.compose(
      widthFt: 12,
      lengthFt: 14,
      furniture: const [
        WallFurnitureHint(
          type: FurnitureType.sofa,
          wall: WallSide.east,
          t: 0.5,
          depthFt: 1.5,
          widthFt: 7,
          lengthFt: 3,
          confidence: 0.9,
        ),
      ],
      wallPhotos: 4,
    );
    expect(result.furniture, isNotEmpty);
    final sofa = result.furniture.first;
    expect(sofa.posFt.dx, greaterThan(8));
    expect(result.accuracyScore, greaterThan(0.5));
  });

  test('tape measure has high accuracy score', () {
    final result = WallRelativeComposer.compose(
      widthFt: 10,
      lengthFt: 10,
      openings: [
        WallOpeningHint.fromLeft(
          wall: WallSide.west,
          type: StrokeType.door,
          fromLeftFt: 3,
          widthFt: 3,
          wallLengthFt: 10,
        ),
      ],
      fromTapeMeasure: true,
    );
    expect(result.accuracyScore, greaterThanOrEqualTo(0.82));
  });

  test('openingToField round-trips south door', () {
    final result = WallRelativeComposer.compose(
      widthFt: 10,
      lengthFt: 12,
      openings: [
        WallOpeningHint.fromLeft(
          wall: WallSide.south,
          type: StrokeType.door,
          fromLeftFt: 2.5,
          widthFt: 3,
          wallLengthFt: 10,
        ),
      ],
      fromTapeMeasure: true,
    );
    final door = result.walls.firstWhere((w) => w.type == StrokeType.door);
    final field = WallRelativeComposer.openingToField(door, 10, 12);
    expect(field, isNotNull);
    expect(field!.wall, WallSide.south);
    expect(field.fromLeftFt, closeTo(2.5, 0.4));
    expect(field.widthFt, closeTo(3.0, 0.3));
  });

  test('no invent openings when none provided', () {
    final result = WallRelativeComposer.compose(
      widthFt: 10,
      lengthFt: 10,
      wallPhotos: 4,
    );
    final doors = result.walls.where((w) => w.type == StrokeType.door);
    expect(doors, isEmpty);
  });

  test('OpeningPriors clamps door width', () {
    expect(OpeningPriors.clampWidth(StrokeType.door, 0.5, 12), greaterThanOrEqualTo(2.0));
    expect(OpeningPriors.clampWidth(StrokeType.door, 20, 12), lessThanOrEqualTo(4.0));
  });
}
