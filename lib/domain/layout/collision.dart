import 'dart:math';
import 'dart:ui';

import '../../models/furniture_item.dart';
import 'furniture_bounds.dart';

class CollisionPair {
  final String aId;
  final String bId;
  const CollisionPair(this.aId, this.bId);
}

/// Oriented-box collision (SAT) for rotated furniture.
class Collision {
  /// Returns set of furniture ids currently overlapping another item.
  static Set<String> overlappingIds(
    List<FurnitureItem> items,
    double pixelsPerFoot, {
    double padding = 2,
  }) {
    final ids = <String>{};
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        if (obbOverlap(items[i], items[j], pixelsPerFoot, padding: padding)) {
          ids.add(items[i].id);
          ids.add(items[j].id);
        }
      }
    }
    return ids;
  }

  static bool overlapsAny(
    FurnitureItem item,
    List<FurnitureItem> others,
    double pixelsPerFoot, {
    double padding = 2,
  }) {
    for (final o in others) {
      if (o.id == item.id) continue;
      if (obbOverlap(item, o, pixelsPerFoot, padding: padding)) {
        return true;
      }
    }
    return false;
  }

  /// True OBB–OBB overlap via Separating Axis Theorem.
  ///
  /// [padding] expands each half-extent in pixels (soft collision / tips).
  static bool obbOverlap(
    FurnitureItem a,
    FurnitureItem b,
    double pixelsPerFoot, {
    double padding = 0,
  }) {
    // Fast reject with AABB
    final ra = FurnitureBounds.itemRect(a, pixelsPerFoot).inflate(padding);
    final rb = FurnitureBounds.itemRect(b, pixelsPerFoot).inflate(padding);
    if (!ra.overlaps(rb)) return false;

    final (ahw, ahh) = FurnitureBounds.halfExtents(
      a,
      pixelsPerFoot,
      padPx: padding,
    );
    final (bhw, bhh) = FurnitureBounds.halfExtents(
      b,
      pixelsPerFoot,
      padPx: padding,
    );

    final aCos = cos(a.rotationAngle);
    final aSin = sin(a.rotationAngle);
    final bCos = cos(b.rotationAngle);
    final bSin = sin(b.rotationAngle);

    // Axes: local X/Y of A and of B
    final axes = <Offset>[
      Offset(aCos, aSin), // A local X
      Offset(-aSin, aCos), // A local Y
      Offset(bCos, bSin), // B local X
      Offset(-bSin, bCos), // B local Y
    ];

    final dx = b.position.dx - a.position.dx;
    final dy = b.position.dy - a.position.dy;

    for (final axis in axes) {
      // Project half-extents of A onto axis
      final aProj = ahw * (axis.dx * aCos + axis.dy * aSin).abs() +
          ahh * (axis.dx * (-aSin) + axis.dy * aCos).abs();
      final bProj = bhw * (axis.dx * bCos + axis.dy * bSin).abs() +
          bhh * (axis.dx * (-bSin) + axis.dy * bCos).abs();
      final dist = (dx * axis.dx + dy * axis.dy).abs();
      if (dist > aProj + bProj) {
        return false; // separating axis found
      }
    }
    return true;
  }

  /// Push [item] out of collisions by sampling offsets (simple separation).
  static FurnitureItem resolveOverlaps(
    FurnitureItem item,
    List<FurnitureItem> others,
    double pixelsPerFoot,
    Rect room, {
    int maxAttempts = 24,
  }) {
    if (!overlapsAny(item, others, pixelsPerFoot)) {
      return item.copyWith(
        position: FurnitureBounds.clampCenterInRoom(item, pixelsPerFoot, room),
      );
    }

    const steps = [
      Offset(20, 0),
      Offset(-20, 0),
      Offset(0, 20),
      Offset(0, -20),
      Offset(20, 20),
      Offset(-20, 20),
      Offset(20, -20),
      Offset(-20, -20),
      Offset(40, 0),
      Offset(-40, 0),
      Offset(0, 40),
      Offset(0, -40),
    ];

    var current = item;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final delta = steps[attempt % steps.length] * (1.0 + attempt ~/ steps.length);
      final next = current.copyWith(position: current.position + delta);
      final clamped = next.copyWith(
        position: FurnitureBounds.clampCenterInRoom(next, pixelsPerFoot, room),
      );
      if (!overlapsAny(clamped, others, pixelsPerFoot)) {
        return clamped;
      }
      current = clamped;
    }
    return current.copyWith(
      position: FurnitureBounds.clampCenterInRoom(current, pixelsPerFoot, room),
    );
  }
}
