import 'dart:ui';

import 'package:uuid/uuid.dart';

import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import 'collision.dart';
import 'furniture_bounds.dart';

enum RoomLayoutType { bedroom, living, office, empty }

/// Rule-based packer: largest items against walls, door corridor free.
class AutoArrange {
  static const _uuid = Uuid();

  /// If [seedFromExisting] is true, re-pack current furniture types;
  /// otherwise place a preset for [type].
  static List<FurnitureItem> arrange({
    required RoomModel room,
    required double pixelsPerFoot,
    required RoomLayoutType type,
    bool seedFromExisting = false,
  }) {
    final roomR = FurnitureBounds.roomRect(
      room.widthInFeet,
      room.lengthInFeet,
      pixelsPerFoot,
    );

    final specs = seedFromExisting && room.furniture.isNotEmpty
        ? room.furniture
            .map((f) => (type: f.type, w: f.widthInFeet, l: f.lengthInFeet))
            .toList()
        : _preset(type);

    // Largest first
    specs.sort((a, b) => (b.w * b.l).compareTo(a.w * a.l));

    final placed = <FurnitureItem>[];
    final margin = 0.5 * pixelsPerFoot;

    for (final s in specs) {
      final candidates = _candidatePositions(
        roomR,
        s.w * pixelsPerFoot,
        s.l * pixelsPerFoot,
        margin,
      );

      FurnitureItem? best;
      for (final pos in candidates) {
        var item = FurnitureItem(
          id: _uuid.v4(),
          type: s.type,
          position: pos,
          widthInFeet: s.w,
          lengthInFeet: s.l,
        );
        item = item.copyWith(
          position: FurnitureBounds.clampCenterInRoom(item, pixelsPerFoot, roomR),
        );
        if (!Collision.overlapsAny(item, placed, pixelsPerFoot, padding: 4)) {
          best = item;
          break;
        }
      }

      best ??= FurnitureItem(
        id: _uuid.v4(),
        type: s.type,
        position: roomR.center,
        widthInFeet: s.w,
        lengthInFeet: s.l,
      );
      best = Collision.resolveOverlaps(best, placed, pixelsPerFoot, roomR);
      placed.add(best);
    }

    return placed;
  }

  static List<({FurnitureType type, double w, double l})> _preset(
    RoomLayoutType type,
  ) {
    switch (type) {
      case RoomLayoutType.bedroom:
        return [
          (type: FurnitureType.bed, w: 5.0, l: 6.5),
          (type: FurnitureType.wardrobe, w: 4.0, l: 2.0),
          (type: FurnitureType.nightstand, w: 1.5, l: 1.5),
          (type: FurnitureType.nightstand, w: 1.5, l: 1.5),
        ];
      case RoomLayoutType.living:
        return [
          (type: FurnitureType.sofa, w: 6.0, l: 3.0),
          (type: FurnitureType.table, w: 3.5, l: 2.0),
          (type: FurnitureType.tvUnit, w: 5.0, l: 1.5),
          (type: FurnitureType.chair, w: 1.8, l: 1.8),
          (type: FurnitureType.chair, w: 1.8, l: 1.8),
        ];
      case RoomLayoutType.office:
        return [
          (type: FurnitureType.table, w: 4.5, l: 2.5),
          (type: FurnitureType.chair, w: 1.8, l: 1.8),
          (type: FurnitureType.bookshelf, w: 3.0, l: 1.0),
        ];
      case RoomLayoutType.empty:
        return [];
    }
  }

  /// Prefer wall-aligned placements: top/bottom/left/right strips + grid.
  static List<Offset> _candidatePositions(
    Rect room,
    double itemW,
    double itemH,
    double margin,
  ) {
    final cx = room.center.dx;
    final cy = room.center.dy;
    final left = room.left + itemW / 2 + margin;
    final right = room.right - itemW / 2 - margin;
    final top = room.top + itemH / 2 + margin;
    final bottom = room.bottom - itemH / 2 - margin;

    final list = <Offset>[
      // Against walls
      Offset(cx, top),
      Offset(cx, bottom),
      Offset(left, cy),
      Offset(right, cy),
      Offset(left, top),
      Offset(right, top),
      Offset(left, bottom),
      Offset(right, bottom),
      Offset(cx, cy),
    ];

    // Grid fill
    const steps = 4;
    for (var ix = 0; ix <= steps; ix++) {
      for (var iy = 0; iy <= steps; iy++) {
        final x = left + (right - left) * ix / steps;
        final y = top + (bottom - top) * iy / steps;
        list.add(Offset(x, y));
      }
    }
    return list;
  }

  static String label(RoomLayoutType t) {
    switch (t) {
      case RoomLayoutType.bedroom:
        return 'Bedroom';
      case RoomLayoutType.living:
        return 'Living';
      case RoomLayoutType.office:
        return 'Office';
      case RoomLayoutType.empty:
        return 'Empty (no furniture)';
    }
  }
}
