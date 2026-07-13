import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/wall_relative_scan.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('compose places door on south wall from fractions', () {
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
    expect(d.startFt.dx, closeTo(3.0, 0.2));
    expect(d.endFt.dx, closeTo(5.0, 0.2));
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
    // Near east wall x≈12 - depth
    expect(sofa.posFt.dx, greaterThan(8));
    expect(result.accuracyScore, greaterThan(0.5));
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
}
