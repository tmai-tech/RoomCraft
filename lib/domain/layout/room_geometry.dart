import 'dart:math' as math;
import 'dart:ui';

/// Floor plan geometry in feet (origin = SW/top-left plan corner as used elsewhere).
///
/// Rect rooms have no polygon. L-shape uses an outer bounding box [widthFt]×[lengthFt]
/// with a rectangular cutout from the NE corner.
class RoomGeometry {
  /// Classic L: full width along bottom, full length along left, cutout top-right.
  ///
  /// ```
  /// 0──W
  /// │  ┌── cutW from right removed
  /// │  │
  /// └──┘ L
  /// ```
  static List<Offset> lShapeVerticesFt({
    required double widthFt,
    required double lengthFt,
    double cutWidthFt = 0,
    double cutLengthFt = 0,
  }) {
    final w = widthFt.clamp(4.0, 200.0);
    final l = lengthFt.clamp(4.0, 200.0);
    final cw = (cutWidthFt > 0 ? cutWidthFt : w * 0.4).clamp(1.0, w - 2.0);
    final cl = (cutLengthFt > 0 ? cutLengthFt : l * 0.4).clamp(1.0, l - 2.0);
    // Clockwise from (0,0) plan top-left:
    // full top edge, right edge down to cut, left into cut, down, left, up.
    return [
      const Offset(0, 0),
      Offset(w, 0),
      Offset(w, l - cl),
      Offset(w - cw, l - cl),
      Offset(w - cw, l),
      Offset(0, l),
    ];
  }

  static bool isLShape(List<Offset>? poly) => poly != null && poly.length >= 6;

  /// Point-in-polygon (ray cast). [poly] in same units as [p].
  static bool containsPoint(List<Offset> poly, Offset p) {
    if (poly.length < 3) return false;
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

  /// Pixel-space polygon from feet vertices.
  static List<Offset> toPixels(List<Offset> polyFt, double pixelsPerFoot) {
    return [
      for (final p in polyFt) Offset(p.dx * pixelsPerFoot, p.dy * pixelsPerFoot),
    ];
  }

  static Path pathFromFt(List<Offset> polyFt, double pixelsPerFoot) {
    final pts = toPixels(polyFt, pixelsPerFoot);
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    return path;
  }

  /// Pull a point into the polygon (or rect AABB if no poly).
  static Offset clampPointFt(
    Offset p,
    double widthFt,
    double lengthFt,
    List<Offset>? polyFt,
  ) {
    var x = p.dx.clamp(0.0, widthFt);
    var y = p.dy.clamp(0.0, lengthFt);
    if (polyFt == null || polyFt.length < 3) {
      return Offset(x, y);
    }
    if (containsPoint(polyFt, Offset(x, y))) return Offset(x, y);
    // Walk toward room center of mass of polygon
    final cx = polyFt.map((e) => e.dx).reduce((a, b) => a + b) / polyFt.length;
    final cy = polyFt.map((e) => e.dy).reduce((a, b) => a + b) / polyFt.length;
    var best = Offset(cx, cy);
    for (var t = 0.0; t <= 1.0; t += 0.05) {
      final q = Offset(
        x + (cx - x) * t,
        y + (cy - y) * t,
      );
      if (containsPoint(polyFt, q)) {
        best = q;
        break;
      }
    }
    return best;
  }

  static double polygonAreaFt(List<Offset> poly) {
    if (poly.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0; i < poly.length; i++) {
      final j = (i + 1) % poly.length;
      sum += poly[i].dx * poly[j].dy - poly[j].dx * poly[i].dy;
    }
    return sum.abs() / 2;
  }

  static String shapeLabel(List<Offset>? poly) {
    if (poly == null || poly.length < 3) return 'Rectangle';
    if (poly.length == 6) return 'L-shape';
    return 'Polygon (${poly.length} pts)';
  }
}
