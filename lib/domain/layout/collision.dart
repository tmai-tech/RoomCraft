import 'dart:ui';

import '../../models/furniture_item.dart';
import 'furniture_bounds.dart';

class CollisionPair {
  final String aId;
  final String bId;
  const CollisionPair(this.aId, this.bId);
}

class Collision {
  /// Returns set of furniture ids currently overlapping another item.
  static Set<String> overlappingIds(
    List<FurnitureItem> items,
    double pixelsPerFoot, {
    double padding = 2,
  }) {
    final ids = <String>{};
    for (var i = 0; i < items.length; i++) {
      final ri = FurnitureBounds.itemRect(items[i], pixelsPerFoot).inflate(padding);
      for (var j = i + 1; j < items.length; j++) {
        final rj = FurnitureBounds.itemRect(items[j], pixelsPerFoot).inflate(padding);
        if (ri.overlaps(rj)) {
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
    final r = FurnitureBounds.itemRect(item, pixelsPerFoot).inflate(padding);
    for (final o in others) {
      if (o.id == item.id) continue;
      if (r.overlaps(FurnitureBounds.itemRect(o, pixelsPerFoot).inflate(padding))) {
        return true;
      }
    }
    return false;
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
