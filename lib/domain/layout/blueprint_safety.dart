import 'dart:math' as math;
import 'dart:ui';

import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import '../../models/stroke_model.dart';
import 'clearances.dart';
import 'furniture_bounds.dart';

/// Guards blueprint editor against corrupt scan/manual geometry (+113).
///
/// Feedback 9bbf5b05: red error on manual blueprint + table in front of door.
/// Causes we harden: zero/NaN pixelsPerFoot paint loops, invalid furniture
/// sizes, and scan furniture sitting on door keep-outs when opening editor.
class BlueprintSafety {
  BlueprintSafety._();

  static bool isFinitePositive(double v) =>
      v.isFinite && !v.isNaN && v > 0;

  /// Safe pixels-per-foot for painters (never 0 → infinite grid loop).
  static double safePixelsPerFoot(double pxf, {double fallback = 20.0}) {
    if (!isFinitePositive(pxf)) return fallback;
    return pxf.clamp(4.0, 200.0);
  }

  /// Safe room dimensions (ft).
  static (double w, double l) safeRoomSize(double widthFt, double lengthFt) {
    var w = widthFt;
    var l = lengthFt;
    if (!isFinitePositive(w)) w = 12.0;
    if (!isFinitePositive(l)) l = 14.0;
    w = w.clamp(4.0, 80.0);
    l = l.clamp(4.0, 80.0);
    return (w, l);
  }

  /// Drop/repair invalid strokes and furniture before editor paint.
  static RoomModel sanitizeRoom(RoomModel room) {
    final (w, l) = safeRoomSize(room.widthInFeet, room.lengthInFeet);
    final strokes = <StrokeModel>[];
    for (final s in room.strokes) {
      if (s.points.isEmpty) continue;
      final pts = <Offset>[];
      for (final p in s.points) {
        if (!p.dx.isFinite || !p.dy.isFinite) continue;
        pts.add(Offset(
          p.dx.clamp(-500.0, 5000.0),
          p.dy.clamp(-500.0, 5000.0),
        ));
      }
      if (pts.isEmpty) continue;
      strokes.add(StrokeModel(id: s.id, type: s.type, points: pts));
    }

    // Assume default scale for position clamp when only feet are known
    const pxf = 20.0;
    final roomR = FurnitureBounds.roomRect(w, l, pxf);
    final furniture = <FurnitureItem>[];
    for (final f in room.furniture) {
      var fw = f.widthInFeet;
      var fl = f.lengthInFeet;
      if (!isFinitePositive(fw)) fw = 3.0;
      if (!isFinitePositive(fl)) fl = 3.0;
      fw = fw.clamp(0.5, math.max(w, l));
      fl = fl.clamp(0.5, math.max(w, l));
      var x = f.position.dx;
      var y = f.position.dy;
      if (!x.isFinite || !y.isFinite) {
        x = roomR.center.dx;
        y = roomR.center.dy;
      }
      var rot = f.rotationAngle;
      if (!rot.isFinite) rot = 0;
      var item = FurnitureItem(
        id: f.id,
        type: f.type,
        position: Offset(x, y),
        widthInFeet: fw,
        lengthInFeet: fl,
        rotationAngle: rot,
        catalogId: f.catalogId,
      );
      item = item.copyWith(
        position: FurnitureBounds.clampCenterInRoom(item, pxf, roomR),
      );
      furniture.add(item);
    }

    return room.copyWith(
      widthInFeet: w,
      lengthInFeet: l,
      strokes: strokes,
      furniture: furniture,
      updatedAt: room.updatedAt,
    );
  }

  /// Nudge furniture off door swing keep-outs (fixes table-in-front-of-door).
  ///
  /// Moves along the room center direction in small steps. Pure geometry —
  /// call after [ScanParser.toEditor] / initFromScan.
  static RoomModel resolveDoorFurnitureBlocks(
    RoomModel room,
    double pixelsPerFoot,
  ) {
    final pxf = safePixelsPerFoot(pixelsPerFoot);
    final sanitized = sanitizeRoom(room);
    final (wFt, lFt) = (sanitized.widthInFeet, sanitized.lengthInFeet);
    final roomR = FurnitureBounds.roomRect(wFt, lFt, pxf);
    final doors = Clearances.doorKeepOuts(sanitized, pxf);
    if (doors.isEmpty || sanitized.furniture.isEmpty) return sanitized;

    final center = roomR.center;
    final out = <FurnitureItem>[];
    var moved = 0;

    for (final f in sanitized.furniture) {
      // Rugs/plants can stay; majors must clear doors
      if (f.type == FurnitureType.rug || f.type == FurnitureType.plant) {
        out.add(f);
        continue;
      }
      var item = f;
      var rect = FurnitureBounds.itemRect(item, pxf);
      var hits = doors.any((d) => d.overlaps(rect));
      if (!hits) {
        out.add(item);
        continue;
      }

      // Step toward room center, then radially around if needed
      final dir = center - item.position;
      final len = dir.distance;
      final step = Offset(
        len < 1 ? 0 : dir.dx / len * pxf * 0.35,
        len < 1 ? pxf * 0.35 : dir.dy / len * pxf * 0.35,
      );

      var resolved = false;
      var pos = item.position;
      for (var i = 0; i < 24; i++) {
        pos = pos + step;
        item = item.copyWith(position: pos);
        item = item.copyWith(
          position: FurnitureBounds.clampCenterInRoom(item, pxf, roomR),
        );
        rect = FurnitureBounds.itemRect(item, pxf);
        if (!doors.any((d) => d.overlaps(rect))) {
          resolved = true;
          break;
        }
      }

      // Fallback: push perpendicular along nearest wall inward
      if (!resolved) {
        final candidates = [
          Offset(item.position.dx + pxf * 2, item.position.dy),
          Offset(item.position.dx - pxf * 2, item.position.dy),
          Offset(item.position.dx, item.position.dy + pxf * 2),
          Offset(item.position.dx, item.position.dy - pxf * 2),
          Offset(center.dx, center.dy),
        ];
        for (final c in candidates) {
          var trial = item.copyWith(position: c);
          trial = trial.copyWith(
            position: FurnitureBounds.clampCenterInRoom(trial, pxf, roomR),
          );
          rect = FurnitureBounds.itemRect(trial, pxf);
          if (!doors.any((d) => d.overlaps(rect))) {
            item = trial;
            resolved = true;
            break;
          }
        }
      }

      if (resolved || (item.position - f.position).distance > 1) {
        moved++;
      }
      out.add(item);
    }

    if (moved == 0) return sanitized;
    return sanitized.copyWith(
      furniture: out,
      updatedAt: DateTime.now(),
    );
  }

  /// True when any furniture OBB overlaps a door keep-out.
  static bool furnitureBlocksDoor(RoomModel room, double pixelsPerFoot) {
    final pxf = safePixelsPerFoot(pixelsPerFoot);
    final doors = Clearances.doorKeepOuts(room, pxf);
    if (doors.isEmpty) return false;
    for (final f in room.furniture) {
      if (f.type == FurnitureType.rug || f.type == FurnitureType.plant) {
        continue;
      }
      final r = FurnitureBounds.itemRect(f, pxf);
      if (doors.any((d) => d.overlaps(r))) return true;
    }
    return false;
  }
}
