import 'dart:ui';

import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import '../../models/stroke_model.dart';
import 'collision.dart';
import 'furniture_bounds.dart';
import 'room_geometry.dart';

/// Clearance rules (feet) for layout tips and soft keep-outs.
class ClearanceRules {
  static const double walkwayFt = 2.5;
  static const double bedSideFt = 2.0;
  static const double doorSwingFt = 2.5;
  static const double wallGapFt = 0.25;
}

class LayoutTip {
  final String message;
  final String severity; // info | warn | error
  const LayoutTip(this.message, {this.severity = 'warn'});
}

class Clearances {
  /// Door keep-out rectangles in pixel space.
  static List<Rect> doorKeepOuts(RoomModel room, double pixelsPerFoot) {
    final rects = <Rect>[];
    final radius = ClearanceRules.doorSwingFt * pixelsPerFoot;
    for (final s in room.strokes) {
      if (s.type != StrokeType.door || s.points.length < 2) continue;
      final mid = Offset(
        (s.points.first.dx + s.points.last.dx) / 2,
        (s.points.first.dy + s.points.last.dy) / 2,
      );
      rects.add(Rect.fromCircle(center: mid, radius: radius));
    }
    return rects;
  }

  static List<LayoutTip> analyze(
    RoomModel room,
    double pixelsPerFoot,
  ) {
    final tips = <LayoutTip>[];
    final roomR = FurnitureBounds.roomRect(
      room.widthInFeet,
      room.lengthInFeet,
      pixelsPerFoot,
    );

    // Overlaps (true OBB)
    final ids = Collision.overlappingIds(room.furniture, pixelsPerFoot);
    if (ids.isNotEmpty) {
      tips.add(LayoutTip(
        '${ids.length} items overlap — move or use Auto-arrange',
        severity: 'error',
      ));
    }

    // Out of bounds
    for (final f in room.furniture) {
      final r = FurnitureBounds.itemRect(f, pixelsPerFoot);
      if (!roomR.inflate(1).contains(r.topLeft) ||
          !roomR.inflate(1).contains(r.bottomRight)) {
        tips.add(const LayoutTip(
          'Furniture extends outside the room bounds',
          severity: 'error',
        ));
        break;
      }
    }

    // Door blocked
    final doors = doorKeepOuts(room, pixelsPerFoot);
    for (final d in doors) {
      for (final f in room.furniture) {
        if (FurnitureBounds.itemRect(f, pixelsPerFoot).overlaps(d)) {
          tips.add(const LayoutTip(
            'Furniture may block a door swing/path',
            severity: 'warn',
          ));
          break;
        }
      }
    }

    // Bed side clearance
    final beds = room.furniture.where((f) => f.type == FurnitureType.bed);
    for (final bed in beds) {
      final br = FurnitureBounds.itemRect(bed, pixelsPerFoot);
      final need = ClearanceRules.bedSideFt * pixelsPerFoot;
      // Check left/right free strip roughly
      final left = Rect.fromLTWH(br.left - need, br.top, need, br.height);
      final right = Rect.fromLTWH(br.right, br.top, need, br.height);
      var blocked = 0;
      for (final f in room.furniture) {
        if (f.id == bed.id) continue;
        final fr = FurnitureBounds.itemRect(f, pixelsPerFoot);
        if (fr.overlaps(left)) blocked++;
        if (fr.overlaps(right)) blocked++;
      }
      if (blocked >= 2) {
        tips.add(const LayoutTip(
          'Bed has little side clearance — leave ~2 ft if possible',
        ));
      }
    }

    // L-shape / polygon: furniture centers must stay on the floor plate
    if (room.isPolygonFloor) {
      final poly = room.floorPolygonFt!;
      for (final f in room.furniture) {
        final cFt = Offset(
          f.position.dx / pixelsPerFoot,
          f.position.dy / pixelsPerFoot,
        );
        if (!RoomGeometry.containsPoint(poly, cFt)) {
          tips.add(const LayoutTip(
            'Furniture sits outside the L-shape floor — move onto the plan',
            severity: 'error',
          ));
          break;
        }
      }
    }

    // Walkway heuristic: if filled area > 70% of room
    final total = room.isPolygonFloor
        ? RoomGeometry.polygonAreaFt(room.floorPolygonFt!)
        : room.widthInFeet * room.lengthInFeet;
    final filled = room.furniture.fold<double>(
      0,
      (s, f) => s + f.widthInFeet * f.lengthInFeet,
    );
    if (total > 0 && filled / total > 0.7) {
      tips.add(const LayoutTip(
        'Room is crowded (>70% filled) — remove or scale down items',
        severity: 'warn',
      ));
    }

    if (tips.isEmpty && room.furniture.isNotEmpty) {
      tips.add(const LayoutTip(
        'Layout looks clear — good walkways',
        severity: 'info',
      ));
    }
    if (room.furniture.isEmpty) {
      tips.add(const LayoutTip(
        'Add furniture from the catalog or run Auto-arrange',
        severity: 'info',
      ));
    }

    return tips;
  }
}
