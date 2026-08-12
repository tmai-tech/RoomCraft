import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/layout/blueprint_openings.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  const wPx = 400.0; // 20 ft @ 20 px/ft
  const hPx = 340.0; // 17 ft
  const pxf = 20.0;

  StrokeModel doorOnSouth({double fromLeftFt = 1.2, double widthFt = 2.8}) {
    // South wall y=0; facing-from-inside L→R is x high→low, but strokes often
    // use plan left→right. Project by mid y≈0.
    final x0 = fromLeftFt * pxf;
    final x1 = (fromLeftFt + widthFt) * pxf;
    return StrokeModel(
      id: 'd1',
      type: StrokeType.door,
      points: [Offset(x0, 0), Offset(x1, 0)],
    );
  }

  StrokeModel doorOnWest({double fromLeftFt = 1.0, double widthFt = 2.8}) {
    final y0 = fromLeftFt * pxf;
    final y1 = (fromLeftFt + widthFt) * pxf;
    return StrokeModel(
      id: 'd2',
      type: StrokeType.door,
      points: [Offset(0, y0), Offset(0, y1)],
    );
  }

  StrokeModel windowOnNorth({double fromLeftFt = 1.5, double widthFt = 6.0}) {
    final x0 = fromLeftFt * pxf;
    final x1 = (fromLeftFt + widthFt) * pxf;
    return StrokeModel(
      id: 'w1',
      type: StrokeType.window,
      points: [Offset(x0, hPx), Offset(x1, hPx)],
    );
  }

  test('+148 perimeter gaps cut doors/windows (not solid box)', () {
    final strokes = [
      doorOnSouth(),
      doorOnWest(),
      windowOnNorth(),
    ];
    final segs = BlueprintOpenings.perimeterWithGaps(
      wPx: wPx,
      hPx: hPx,
      strokes: strokes,
    );
    expect(segs, isNotEmpty);
    // Full solid perimeter without gaps would be 4 segments; with 3 openings
    // we expect more pieces (split sides).
    expect(segs.length, greaterThanOrEqualTo(5));

    // No segment should fully cover the south door span
    final doorLo = 1.2 * pxf;
    final doorHi = (1.2 + 2.8) * pxf;
    for (final s in segs) {
      final onSouth = s.$1.dy.abs() < 1 && s.$2.dy.abs() < 1;
      if (!onSouth) continue;
      final lo = math.min(s.$1.dx, s.$2.dx);
      final hi = math.max(s.$1.dx, s.$2.dx);
      // Segment must not completely swallow the door interior
      final coversDoor = lo <= doorLo + 2 && hi >= doorHi - 2;
      expect(coversDoor, isFalse,
          reason: 'wall segment $lo–$hi should gap door $doorLo–$doorHi');
    }
  });

  test('+148 empty openings → full closed 4 walls', () {
    final segs = BlueprintOpenings.perimeterWithGaps(
      wPx: wPx,
      hPx: hPx,
      strokes: const [],
    );
    expect(segs.length, 4);
    final totalLen = segs.fold<double>(
      0,
      (a, s) => a + (s.$1 - s.$2).distance,
    );
    expect(totalLen, closeTo(2 * (wPx + hPx), 1.0));
  });

  test('+148 door swing always samples inside room', () {
    // South wall door
    final south = BlueprintOpenings.bestInwardDoorSwing(
      const Offset(40, 0),
      const Offset(96, 0),
      roomWPx: wPx,
      roomHPx: hPx,
    );
    expect(
      BlueprintOpenings.swingSampleInside(
        south.hinge,
        south.radius,
        south.startAngle,
        south.sweep,
        roomWPx: wPx,
        roomHPx: hPx,
      ),
      isTrue,
    );

    // West wall door — outward would go x<0
    final west = BlueprintOpenings.bestInwardDoorSwing(
      const Offset(0, 40),
      const Offset(0, 96),
      roomWPx: wPx,
      roomHPx: hPx,
    );
    expect(
      BlueprintOpenings.swingSampleInside(
        west.hinge,
        west.radius,
        west.startAngle,
        west.sweep,
        roomWPx: wPx,
        roomHPx: hPx,
      ),
      isTrue,
    );

    // East wall
    final east = BlueprintOpenings.bestInwardDoorSwing(
      Offset(wPx, 50),
      Offset(wPx, 110),
      roomWPx: wPx,
      roomHPx: hPx,
    );
    expect(
      BlueprintOpenings.swingSampleInside(
        east.hinge,
        east.radius,
        east.startAngle,
        east.sweep,
        roomWPx: wPx,
        roomHPx: hPx,
      ),
      isTrue,
    );

    // North wall
    final north = BlueprintOpenings.bestInwardDoorSwing(
      Offset(80, hPx),
      Offset(140, hPx),
      roomWPx: wPx,
      roomHPx: hPx,
    );
    expect(
      BlueprintOpenings.swingSampleInside(
        north.hinge,
        north.radius,
        north.startAngle,
        north.sweep,
        roomWPx: wPx,
        roomHPx: hPx,
      ),
      isTrue,
    );
  });

  test('+148 opening labels carry type + width', () {
    expect(BlueprintOpenings.openingLabel(StrokeType.door, 2.8), 'Door 2.8′');
    expect(BlueprintOpenings.openingLabel(StrokeType.window, 6.0), 'Win 6.0′');
    expect(BlueprintOpenings.openingLabel(StrokeType.balcony, 5.5), 'Mesh 5.5′');
  });

  test('+148 wall index detects all four sides', () {
    expect(
      BlueprintOpenings.wallIndexForOpening(
        const Offset(10, 0),
        const Offset(60, 0),
        wPx: wPx,
        hPx: hPx,
      ),
      0,
    );
    expect(
      BlueprintOpenings.wallIndexForOpening(
        Offset(wPx, 10),
        Offset(wPx, 60),
        wPx: wPx,
        hPx: hPx,
      ),
      1,
    );
    expect(
      BlueprintOpenings.wallIndexForOpening(
        Offset(10, hPx),
        Offset(60, hPx),
        wPx: wPx,
        hPx: hPx,
      ),
      2,
    );
    expect(
      BlueprintOpenings.wallIndexForOpening(
        const Offset(0, 10),
        const Offset(0, 60),
        wPx: wPx,
        hPx: hPx,
      ),
      3,
    );
  });
}
