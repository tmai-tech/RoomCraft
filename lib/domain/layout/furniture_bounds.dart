import 'dart:math';
import 'dart:ui';

import '../../models/furniture_item.dart';

/// Geometry helpers for furniture on the canvas (pixel space).
///
/// Uses true OBB (oriented bounding box) corners for hit-test / collision.
/// [itemRect] remains a conservative AABB for clamp / room bounds.
class FurnitureBounds {
  /// Axis-aligned expanded bounds of a (possibly rotated) item.
  static Rect itemRect(FurnitureItem item, double pixelsPerFoot) {
    final w = item.widthInFeet * pixelsPerFoot;
    final h = item.lengthInFeet * pixelsPerFoot;
    final angle = item.rotationAngle;

    final cosA = cos(angle).abs();
    final sinA = sin(angle).abs();
    final bw = w * cosA + h * sinA;
    final bh = w * sinA + h * cosA;

    return Rect.fromCenter(
      center: item.position,
      width: bw,
      height: bh,
    );
  }

  static Rect roomRect(double widthFt, double lengthFt, double pixelsPerFoot) {
    return Rect.fromLTWH(
      0,
      0,
      widthFt * pixelsPerFoot,
      lengthFt * pixelsPerFoot,
    );
  }

  /// Half-extents in feet→pixels (width along local X, length along local Y).
  static (double halfW, double halfH) halfExtents(
    FurnitureItem item,
    double pixelsPerFoot, {
    double padPx = 0,
  }) {
    return (
      item.widthInFeet * pixelsPerFoot / 2 + padPx,
      item.lengthInFeet * pixelsPerFoot / 2 + padPx,
    );
  }

  /// Four corners of the oriented box, clockwise from top-left in local space.
  static List<Offset> corners(
    FurnitureItem item,
    double pixelsPerFoot, {
    double padPx = 0,
  }) {
    final (hw, hh) = halfExtents(item, pixelsPerFoot, padPx: padPx);
    final cosA = cos(item.rotationAngle);
    final sinA = sin(item.rotationAngle);
    final cx = item.position.dx;
    final cy = item.position.dy;

    Offset rot(double lx, double ly) => Offset(
          cx + lx * cosA - ly * sinA,
          cy + lx * sinA + ly * cosA,
        );

    return [
      rot(-hw, -hh),
      rot(hw, -hh),
      rot(hw, hh),
      rot(-hw, hh),
    ];
  }

  /// Point-in-OBB (local axes of [item]). [padPx] expands the hit target.
  static bool containsPoint(
    FurnitureItem item,
    Offset point,
    double pixelsPerFoot, {
    double padPx = 8,
  }) {
    final (hw, hh) = halfExtents(item, pixelsPerFoot, padPx: padPx);
    final dx = point.dx - item.position.dx;
    final dy = point.dy - item.position.dy;
    // Inverse-rotate into local space
    final cosA = cos(-item.rotationAngle);
    final sinA = sin(-item.rotationAngle);
    final localX = dx * cosA - dy * sinA;
    final localY = dx * sinA + dy * cosA;
    return localX.abs() <= hw && localY.abs() <= hh;
  }

  /// Clamp furniture center so its AABB stays inside [room].
  ///
  /// When [floorPolygonPx] is set (L-shape / polygon floors), also pulls the
  /// center into the polygon so pieces do not rest in the cutout.
  static Offset clampCenterInRoom(
    FurnitureItem item,
    double pixelsPerFoot,
    Rect room, {
    double margin = 2,
    List<Offset>? floorPolygonPx,
  }) {
    final r = itemRect(item, pixelsPerFoot);
    final halfW = r.width / 2;
    final halfH = r.height / 2;
    final minX = room.left + halfW + margin;
    final maxX = room.right - halfW - margin;
    final minY = room.top + halfH + margin;
    final maxY = room.bottom - halfH - margin;

    if (minX > maxX || minY > maxY) {
      return room.center;
    }

    var cx = item.position.dx.clamp(minX, maxX);
    var cy = item.position.dy.clamp(minY, maxY);

    final poly = floorPolygonPx;
    if (poly != null && poly.length >= 3) {
      // Local import avoided — ray cast inline for center containment.
      if (!_pointInPolygon(poly, Offset(cx, cy))) {
        final cx0 =
            poly.map((e) => e.dx).reduce((a, b) => a + b) / poly.length;
        final cy0 =
            poly.map((e) => e.dy).reduce((a, b) => a + b) / poly.length;
        for (var t = 0.0; t <= 1.0; t += 0.04) {
          final q = Offset(cx + (cx0 - cx) * t, cy + (cy0 - cy) * t);
          final qx = q.dx.clamp(minX, maxX);
          final qy = q.dy.clamp(minY, maxY);
          if (_pointInPolygon(poly, Offset(qx, qy))) {
            cx = qx;
            cy = qy;
            break;
          }
        }
      }
    }

    return Offset(cx, cy);
  }

  static bool _pointInPolygon(List<Offset> poly, Offset p) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].dx, yi = poly[i].dy;
      final xj = poly[j].dx, yj = poly[j].dy;
      final intersect = ((yi > p.dy) != (yj > p.dy)) &&
          (p.dx <
              (xj - xi) * (p.dy - yi) / ((yj - yi) == 0 ? 1e-9 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
