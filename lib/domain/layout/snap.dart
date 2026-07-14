import 'dart:math' as math;
import 'dart:ui';

import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import '../../models/stroke_model.dart';
import 'furniture_bounds.dart';

/// Snap furniture center to grid, room walls, and neighbor edges.
class FurnitureSnap {
  /// Soft snap distance in pixels (~0.35 ft at 20 px/ft).
  /// Lower = freer placement; snap only when close to guides.
  static const double defaultThresholdPx = 7;

  static Offset snap({
    required FurnitureItem item,
    required RoomModel room,
    required double pixelsPerFoot,
    required List<FurnitureItem> others,
    double thresholdPx = defaultThresholdPx,
    /// When false, only snap to walls/neighbors (no grid) for freer layout.
    bool useGrid = true,
  }) {
    var pos = item.position;

    // 1) Fine grid (¼ ft) — less "stuck" than 1 ft snaps
    if (useGrid) {
      final grid = pixelsPerFoot * 0.25;
      pos = Offset(
        (pos.dx / grid).roundToDouble() * grid,
        (pos.dy / grid).roundToDouble() * grid,
      );
    }

    final roomR = FurnitureBounds.roomRect(
      room.widthInFeet,
      room.lengthInFeet,
      pixelsPerFoot,
    );
    final half = FurnitureBounds.halfExtents(item, pixelsPerFoot);
    final halfW = half.$1;
    final halfH = half.$2;

    // 2) Outer wall edges (center so AABB kisses wall)
    final wallTargetsX = <double>[
      roomR.left + halfW,
      roomR.right - halfW,
      roomR.center.dx,
    ];
    final wallTargetsY = <double>[
      roomR.top + halfH,
      roomR.bottom - halfH,
      roomR.center.dy,
    ];

    pos = Offset(
      _snapToNearest(pos.dx, wallTargetsX, thresholdPx),
      _snapToNearest(pos.dy, wallTargetsY, thresholdPx),
    );

    // 3) Align to other furniture edges / centers
    final myRect = FurnitureBounds.itemRect(
      item.copyWith(position: pos),
      pixelsPerFoot,
    );
    final xTargets = <double>[...wallTargetsX];
    final yTargets = <double>[...wallTargetsY];

    for (final o in others) {
      if (o.id == item.id) continue;
      final or = FurnitureBounds.itemRect(o, pixelsPerFoot);
      // Align centers
      xTargets.add(o.position.dx);
      yTargets.add(o.position.dy);
      // Align left/right edges → our center
      xTargets.add(or.left + myRect.width / 2);
      xTargets.add(or.right - myRect.width / 2);
      yTargets.add(or.top + myRect.height / 2);
      yTargets.add(or.bottom - myRect.height / 2);
      // Flush sides (our left to their right)
      xTargets.add(or.right + myRect.width / 2);
      xTargets.add(or.left - myRect.width / 2);
      yTargets.add(or.bottom + myRect.height / 2);
      yTargets.add(or.top - myRect.height / 2);
    }

    // Door midpoints — soft snap away is handled by clearances; optional align
    for (final s in room.strokes) {
      if (s.type != StrokeType.door || s.points.length < 2) continue;
      final mid = Offset(
        (s.points.first.dx + s.points.last.dx) / 2,
        (s.points.first.dy + s.points.last.dy) / 2,
      );
      xTargets.add(mid.dx);
      yTargets.add(mid.dy);
    }

    pos = Offset(
      _snapToNearest(pos.dx, xTargets, thresholdPx),
      _snapToNearest(pos.dy, yTargets, thresholdPx),
    );

    return FurnitureBounds.clampCenterInRoom(
      item.copyWith(position: pos),
      pixelsPerFoot,
      roomR,
    );
  }

  static double _snapToNearest(double v, List<double> targets, double thr) {
    var best = v;
    var bestD = thr;
    for (final t in targets) {
      final d = (v - t).abs();
      if (d <= bestD) {
        bestD = d;
        best = t;
      }
    }
    return best;
  }

  /// Distance helper (tests).
  static double dist(Offset a, Offset b) =>
      math.sqrt(math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2));
}
