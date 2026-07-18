import 'dart:ui';

import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import 'clearances.dart';
import 'furniture_bounds.dart';

/// One grid cell of free-path walkway analysis (pixel space).
class WalkwayCell {
  final Rect rect;
  /// 0 = clear, 1 = blocked by furniture (or door keep-out).
  final double blockage;

  const WalkwayCell({required this.rect, required this.blockage});

  bool get isBlocked => blockage >= 0.5;
  bool get isTight => blockage > 0 && blockage < 0.5;
}

/// Free-architecture walkway heatmap (Planner “clear path” intelligence).
///
/// Samples a coarse grid over the room; cells under furniture or door swings
/// are blocked. Pure domain — no Flutter UI.
class WalkwayHeatmap {
  /// Cell size in feet (default ~half walkway width for readable overlay).
  static const double defaultCellFt = 1.0;

  /// Build heatmap cells for [room] in canvas pixel space (origin = room TL).
  static List<WalkwayCell> compute(
    RoomModel room,
    double pixelsPerFoot, {
    double cellFt = defaultCellFt,
  }) {
    if (room.widthInFeet <= 0 || room.lengthInFeet <= 0) return const [];
    final cellPx = (cellFt * pixelsPerFoot).clamp(4.0, 200.0);
    final roomR = FurnitureBounds.roomRect(
      room.widthInFeet,
      room.lengthInFeet,
      pixelsPerFoot,
    );
    final furnitureRects = <Rect>[
      for (final f in room.furniture)
        if (f.type != FurnitureType.rug && f.type != FurnitureType.plant)
          FurnitureBounds.itemRect(f, pixelsPerFoot),
    ];
    final doorKeep = Clearances.doorKeepOuts(room, pixelsPerFoot);

    final cells = <WalkwayCell>[];
    for (var y = roomR.top; y < roomR.bottom; y += cellPx) {
      for (var x = roomR.left; x < roomR.right; x += cellPx) {
        final w = (x + cellPx > roomR.right) ? roomR.right - x : cellPx;
        final h = (y + cellPx > roomR.bottom) ? roomR.bottom - y : cellPx;
        if (w < 1 || h < 1) continue;
        final cell = Rect.fromLTWH(x, y, w, h);
        final center = cell.center;
        var blockage = 0.0;
        for (final fr in furnitureRects) {
          if (fr.contains(center) || fr.overlaps(cell)) {
            blockage = 1.0;
            break;
          }
        }
        if (blockage < 1.0) {
          for (final d in doorKeep) {
            if (d.contains(center) || d.overlaps(cell)) {
              blockage = blockage < 0.45 ? 0.45 : blockage;
            }
          }
        }
        cells.add(WalkwayCell(rect: cell, blockage: blockage));
      }
    }
    return cells;
  }

  /// Fraction of cells that are free (not blocked by furniture).
  static double freeFraction(List<WalkwayCell> cells) {
    if (cells.isEmpty) return 1.0;
    final free = cells.where((c) => !c.isBlocked).length;
    return free / cells.length;
  }
}
