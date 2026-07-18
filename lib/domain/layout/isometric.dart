import 'dart:math' as math;
import 'dart:ui';

/// Pure isometric projection helpers (no Flutter widgets).
///
/// Standard game-style iso:
///   screenX = (x - y) * cos(30°)
///   screenY = (x + y) * sin(30°) - z
class Iso {
  Iso._();

  static const double cos30 = 0.8660254037844386;
  static const double sin30 = 0.5;

  /// Project model-space (x, y) with height z (all same units) to screen.
  static Offset project(double x, double y, [double z = 0]) {
    return Offset(
      (x - y) * cos30,
      (x + y) * sin30 - z,
    );
  }

  /// Project four top corners of an axis-aligned box centered at [cx],[cy]
  /// with size [w]×[d] and height [h], then expand by rotation around Z.
  /// Returns bottom face (4) then top face (4) in local box coords after rotation.
  static List<Offset> boxCorners({
    required double cx,
    required double cy,
    required double w,
    required double d,
    required double h,
    double rotation = 0,
  }) {
    final hw = w / 2;
    final hd = d / 2;
    final local = <Offset>[
      Offset(-hw, -hd),
      Offset(hw, -hd),
      Offset(hw, hd),
      Offset(-hw, hd),
    ];
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    final bottom = <Offset>[];
    final top = <Offset>[];
    for (final p in local) {
      final rx = p.dx * cos - p.dy * sin;
      final ry = p.dx * sin + p.dy * cos;
      final x = cx + rx;
      final y = cy + ry;
      bottom.add(project(x, y, 0));
      top.add(project(x, y, h));
    }
    return [...bottom, ...top];
  }

  /// Bounding box of projected points (for fit-to-view).
  static Rect boundsOf(Iterable<Offset> pts) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (!minX.isFinite) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}
