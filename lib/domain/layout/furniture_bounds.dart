import 'dart:math';
import 'dart:ui';

import '../../models/furniture_item.dart';

/// Axis-aligned bounds for furniture on the canvas (pixel space).
/// Rotation is accounted for via a conservative expanded AABB.
class FurnitureBounds {
  static Rect itemRect(FurnitureItem item, double pixelsPerFoot) {
    final w = item.widthInFeet * pixelsPerFoot;
    final h = item.lengthInFeet * pixelsPerFoot;
    final angle = item.rotationAngle;

    // Expanded AABB for rotated rectangle
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

  /// Clamp furniture center so its AABB stays inside [room].
  static Offset clampCenterInRoom(
    FurnitureItem item,
    double pixelsPerFoot,
    Rect room, {
    double margin = 2,
  }) {
    final r = itemRect(item, pixelsPerFoot);
    final halfW = r.width / 2;
    final halfH = r.height / 2;
    final minX = room.left + halfW + margin;
    final maxX = room.right - halfW - margin;
    final minY = room.top + halfH + margin;
    final maxY = room.bottom - halfH - margin;

    if (minX > maxX || minY > maxY) {
      // Item larger than room — pin to center
      return room.center;
    }

    return Offset(
      item.position.dx.clamp(minX, maxX),
      item.position.dy.clamp(minY, maxY),
    );
  }
}
