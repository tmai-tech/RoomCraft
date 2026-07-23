import 'dart:math' as math;

/// Multi-dot floor polygon → room W×L (+123 / +124).
///
/// Planner 5D / magicplan-class accuracy uses **metric geometry** from the
/// device (AR/LiDAR), not monocular photos. RoomCraft's high-accuracy path
/// marks floor **corner dots** (a sparse point map), then reconstructs a
/// rectangle — optionally **orthogonalized** (+124) like field-measure CAD.
///
/// Python research analogues (server / offline experiments):
/// - Open3D plane segmentation + RANSAC wall extraction
/// - RTAB-Map / ORB-SLAM3 sparse maps
/// - AliceVision Meshroom photogrammetry (offline video)
/// - scipy.spatial ConvexHull on floor-projected points
class ArPolygonMap {
  ArPolygonMap._();

  /// Result of fitting a rectangular room to floor dots.
  static ({
    double widthM,
    double lengthM,
    double oppositeEdgeError,
    double diagonalError,
    double orthogonalScore,
  })? resolveMeters(List<List<double>> dotsXyz) {
    if (dotsXyz.length < 4) return null;
    final ordered = _orderByAngle(dotsXyz.take(4).toList());
    if (ordered == null) return null;

    final edgeFit = _oppositeEdgeFit(ordered);
    final ortho = _orthogonalFit(ordered);

    // Prefer orthogonal fit when room is nearly rectangular (score ≥ 0.85).
    final useOrtho = ortho != null && ortho.orthogonalScore >= 0.85;
    final width = useOrtho ? ortho!.widthM : edgeFit.widthM;
    final length = useOrtho ? ortho!.lengthM : edgeFit.lengthM;
    if (width < 0.5 || length < 0.5) return null;

    final diag = _diagonalCheck(ordered, width, length);

    // Soft scale refine from diagonals when error is mild (magicplan-style).
    var w = width;
    var l = length;
    if (diag.ratio > 0.0 &&
        (diag.ratio - 1.0).abs() >= 0.04 &&
        diag.ratio >= 0.70 &&
        diag.ratio <= 1.35) {
      final scale = 1.0 + (diag.ratio - 1.0) * 0.65;
      w *= scale;
      l *= scale;
    }

    return (
      widthM: math.max(w, l),
      lengthM: math.min(w, l),
      oppositeEdgeError: edgeFit.oppositeEdgeError,
      diagonalError: diag.error,
      orthogonalScore: ortho?.orthogonalScore ?? 0.0,
    );
  }

  /// Same as [resolveMeters] but returns feet (ARCore convention × 3.28084).
  static ({
    double widthFt,
    double lengthFt,
    double oppositeEdgeError,
    double diagonalError,
    double orthogonalScore,
  })? resolveFeet(List<List<double>> dotsXyz) {
    final m = resolveMeters(dotsXyz);
    if (m == null) return null;
    const mToFt = 3.28084;
    return (
      widthFt: m.widthM * mToFt,
      lengthFt: m.lengthM * mToFt,
      oppositeEdgeError: m.oppositeEdgeError,
      diagonalError: m.diagonalError,
      orthogonalScore: m.orthogonalScore,
    );
  }

  /// Build 4 corners of an axis-aligned rectangle on XZ (for tests).
  static List<List<double>> rectCornersM({
    required double widthM,
    required double lengthM,
    double originX = 0,
    double originZ = 0,
    double y = 0,
  }) {
    return [
      [originX, y, originZ],
      [originX + widthM, y, originZ],
      [originX + widthM, y, originZ + lengthM],
      [originX, y, originZ + lengthM],
    ];
  }

  /// Noisy rectangle corners (user multi-dot error simulation).
  static List<List<double>> noisyRectCornersM({
    required double widthM,
    required double lengthM,
    double noiseM = 0.08,
    int seed = 7,
  }) {
    final base = rectCornersM(widthM: widthM, lengthM: lengthM);
    final rng = math.Random(seed);
    return [
      for (final p in base)
        [
          p[0] + (rng.nextDouble() - 0.5) * 2 * noiseM,
          p[1],
          p[2] + (rng.nextDouble() - 0.5) * 2 * noiseM,
        ],
    ];
  }

  // --- internals ---

  static List<List<double>>? _orderByAngle(List<List<double>> pts) {
    if (pts.length < 4) return null;
    var cx = 0.0;
    var cz = 0.0;
    for (final p in pts) {
      cx += p[0];
      cz += _z(p);
    }
    cx /= pts.length;
    cz /= pts.length;
    final ordered = [...pts]..sort((a, b) {
        final aa = math.atan2(_z(a) - cz, a[0] - cx);
        final bb = math.atan2(_z(b) - cz, b[0] - cx);
        return aa.compareTo(bb);
      });
    return ordered;
  }

  static double _z(List<double> p) => p.length > 2 ? p[2] : p[1];

  static ({double widthM, double lengthM, double oppositeEdgeError})
      _oppositeEdgeFit(List<List<double>> ordered) {
    final edges = List<double>.filled(4, 0);
    for (var i = 0; i < 4; i++) {
      final a = ordered[i];
      final b = ordered[(i + 1) % 4];
      final dx = a[0] - b[0];
      final dz = _z(a) - _z(b);
      edges[i] = math.sqrt(dx * dx + dz * dz);
    }
    final sideA = (edges[0] + edges[2]) / 2.0;
    final sideB = (edges[1] + edges[3]) / 2.0;
    final errA = edges[0] <= 0 ? 0.0 : (edges[0] - edges[2]).abs() / edges[0];
    final errB = edges[1] <= 0 ? 0.0 : (edges[1] - edges[3]).abs() / edges[1];
    final opp = errA > errB ? errA : errB;
    return (
      widthM: math.max(sideA, sideB),
      lengthM: math.min(sideA, sideB),
      oppositeEdgeError: opp,
    );
  }

  /// Fit orthogonal rectangle via Gram-Schmidt axes from edge directions (+124).
  static ({double widthM, double lengthM, double orthogonalScore})?
      _orthogonalFit(List<List<double>> ordered) {
    // Edge unit vectors
    final uxs = <double>[];
    final uzs = <double>[];
    final vxs = <double>[];
    final vzs = <double>[];
    for (var i = 0; i < 4; i++) {
      final a = ordered[i];
      final b = ordered[(i + 1) % 4];
      var dx = b[0] - a[0];
      var dz = _z(b) - _z(a);
      final len = math.sqrt(dx * dx + dz * dz);
      if (len < 1e-6) continue;
      dx /= len;
      dz /= len;
      if (i.isEven) {
        uxs.add(dx);
        uzs.add(dz);
      } else {
        vxs.add(dx);
        vzs.add(dz);
      }
    }
    if (uxs.isEmpty || vxs.isEmpty) return null;

    // Average raw axes (flip if opposing)
    var ux = 0.0, uz = 0.0;
    for (var i = 0; i < uxs.length; i++) {
      final s = (uxs[i] * uxs[0] + uzs[i] * uzs[0]) < 0 ? -1.0 : 1.0;
      ux += s * uxs[i];
      uz += s * uzs[i];
    }
    var un = math.sqrt(ux * ux + uz * uz);
    if (un < 1e-6) return null;
    ux /= un;
    uz /= un;

    var vx = 0.0, vz = 0.0;
    for (var i = 0; i < vxs.length; i++) {
      final s = (vxs[i] * vxs[0] + vzs[i] * vzs[0]) < 0 ? -1.0 : 1.0;
      vx += s * vxs[i];
      vz += s * vzs[i];
    }
    var vn = math.sqrt(vx * vx + vz * vz);
    if (vn < 1e-6) return null;
    vx /= vn;
    vz /= vn;

    // Gram-Schmidt: make V orthogonal to U
    final dot = ux * vx + uz * vz;
    vx -= dot * ux;
    vz -= dot * uz;
    vn = math.sqrt(vx * vx + vz * vz);
    if (vn < 1e-6) {
      // Degenerate — rotate U by 90°
      vx = -uz;
      vz = ux;
    } else {
      vx /= vn;
      vz /= vn;
    }

    // How orthogonal were raw axes? (score 1 = perfect 90°)
    final rawDot = (uxs.isNotEmpty && vxs.isNotEmpty)
        ? (uxs[0] * vxs[0] + uzs[0] * vzs[0]).abs()
        : 1.0;
    final orthogonalScore = (1.0 - rawDot).clamp(0.0, 1.0);

    // Project corners onto U,V and take extent
    var minU = double.infinity, maxU = -double.infinity;
    var minV = double.infinity, maxV = -double.infinity;
    for (final p in ordered) {
      final pu = p[0] * ux + _z(p) * uz;
      final pv = p[0] * vx + _z(p) * vz;
      if (pu < minU) minU = pu;
      if (pu > maxU) maxU = pu;
      if (pv < minV) minV = pv;
      if (pv > maxV) maxV = pv;
    }
    final sideA = (maxU - minU).abs();
    final sideB = (maxV - minV).abs();
    return (
      widthM: math.max(sideA, sideB),
      lengthM: math.min(sideA, sideB),
      orthogonalScore: orthogonalScore,
    );
  }

  static ({double ratio, double error}) _diagonalCheck(
    List<List<double>> ordered,
    double width,
    double length,
  ) {
    // Diagonals: 0-2 and 1-3
    final d02 = _dist(ordered[0], ordered[2]);
    final d13 = _dist(ordered[1], ordered[3]);
    final measured = (d02 + d13) / 2.0;
    final expected = math.sqrt(width * width + length * length);
    if (expected < 0.5 || measured < 0.5) {
      return (ratio: 1.0, error: 0.0);
    }
    final ratio = measured / expected;
    final error = (ratio - 1.0).abs();
    return (ratio: ratio, error: error);
  }

  static double _dist(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dz = _z(a) - _z(b);
    return math.sqrt(dx * dx + dz * dz);
  }
}
