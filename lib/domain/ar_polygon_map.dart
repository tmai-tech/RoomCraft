import 'dart:math' as math;

/// Multi-dot / walk-cloud floor map → room W×L (+123–+128).
///
/// Planner 5D / magicplan-class accuracy uses **metric geometry** from the
/// device (AR/LiDAR), not monocular photos.
///
/// - **+123**: 4 corner dots
/// - **+124**: orthogonal fit + auto diagonal
/// - **+125**: dense walk cloud (N samples / plane extents) for easy scan
/// - **+126**: robust cloud — outlier trim, percentile hull (Open3D-style),
///   angular coverage score (Planner5D walk completeness)
/// - **+128**: fuse **floor hits + camera pose trail** (walk path is interior;
///   expand by standoff like Planner5D 1.5–2 m from walls)
///
/// Python research analogues (server / offline experiments):
/// - Open3D plane segmentation + RANSAC / statistical outlier removal
/// - RTAB-Map / ORB-SLAM3 sparse maps + trajectory envelope
/// - AliceVision Meshroom photogrammetry (offline video)
/// - scipy.spatial ConvexHull + percentile AABB on floor-projected points
class ArPolygonMap {
  ArPolygonMap._();

  /// Typical half-standoff (m) from walk path to wall when user follows
  /// Planner5D guidance (~1.5–2 m from walls while holding phone).
  static const double defaultWalkStandoffM = 0.75;

  /// Result of fitting a rectangular room to floor dots / walk samples.
  static ({
    double widthM,
    double lengthM,
    double oppositeEdgeError,
    double diagonalError,
    double orthogonalScore,
    double coverageScore,
  })? resolveMeters(List<List<double>> dotsXyz) {
    if (dotsXyz.length < 4) return null;

    // +125/+126: dense walk cloud → robust orthogonal rect (PCA + percentiles)
    if (dotsXyz.length > 4) {
      final cloud = _cloudOrthogonalFit(dotsXyz);
      if (cloud != null && cloud.widthM >= 0.5 && cloud.lengthM >= 0.5) {
        return (
          widthM: cloud.widthM,
          lengthM: cloud.lengthM,
          oppositeEdgeError: 0.0,
          diagonalError: 0.0,
          orthogonalScore: cloud.orthogonalScore,
          coverageScore: cloud.coverageScore,
        );
      }
    }

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
      coverageScore: 1.0, // 4 deliberate corners → full coverage
    );
  }

  /// Same as [resolveMeters] but returns feet (ARCore convention × 3.28084).
  static ({
    double widthFt,
    double lengthFt,
    double oppositeEdgeError,
    double diagonalError,
    double orthogonalScore,
    double coverageScore,
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
      coverageScore: m.coverageScore,
    );
  }

  /// +128: fuse floor hits with camera pose trail for Home Scan accuracy.
  ///
  /// Floor hits map the plane mesh; poses map where the user walked (usually
  /// **inside** the room). Incomplete floor coverage under-sizes — expand
  /// toward pose envelope + standoff (magicplan / Planner5D walk class).
  static ({
    double widthM,
    double lengthM,
    double oppositeEdgeError,
    double diagonalError,
    double orthogonalScore,
    double coverageScore,
    String fuseSource,
  })? resolveWalkMeters({
    List<List<double>> floorHits = const [],
    List<List<double>> poses = const [],
    double standoffM = defaultWalkStandoffM,
  }) {
    final floor = floorHits.length >= 4 ? resolveMeters(floorHits) : null;
    final pose = poses.length >= 8 ? resolveMeters(poses) : null;

    if (floor == null && pose == null) return null;

    if (pose == null) {
      return (
        widthM: floor!.widthM,
        lengthM: floor.lengthM,
        oppositeEdgeError: floor.oppositeEdgeError,
        diagonalError: floor.diagonalError,
        orthogonalScore: floor.orthogonalScore,
        coverageScore: floor.coverageScore,
        fuseSource: 'floor',
      );
    }

    // Expand interior path by standoff on both sides → wall-to-wall estimate
    final stand = standoffM.clamp(0.35, 1.25);
    final poseW = pose.widthM + 2 * stand;
    final poseL = pose.lengthM + 2 * stand;
    final poseWNrm = math.max(poseW, poseL);
    final poseLNrm = math.min(poseW, poseL);

    if (floor == null) {
      return (
        widthM: poseWNrm,
        lengthM: poseLNrm,
        oppositeEdgeError: 0.0,
        diagonalError: 0.0,
        orthogonalScore: (pose.orthogonalScore * 0.95).clamp(0.7, 0.97),
        coverageScore: (pose.coverageScore * 0.95).clamp(0.0, 1.0),
        fuseSource: 'pose+standoff',
      );
    }

    // When floor cover is strong, prefer floor but allow soft growth if pose
    // envelope implies a larger room (mesh didn't reach far walls).
    double w;
    double l;
    String src;
    if (floor.coverageScore >= 0.75) {
      w = math.max(floor.widthM, math.min(poseWNrm, floor.widthM * 1.12));
      l = math.max(floor.lengthM, math.min(poseLNrm, floor.lengthM * 1.12));
      src = 'floor+poseSoft';
    } else if (floor.coverageScore >= 0.45) {
      // Incomplete loop: blend toward pose envelope
      w = math.max(floor.widthM, floor.widthM * 0.45 + poseWNrm * 0.55);
      l = math.max(floor.lengthM, floor.lengthM * 0.45 + poseLNrm * 0.55);
      src = 'floor+poseBlend';
    } else {
      // Sparse floor — trust expanded pose more
      w = math.max(floor.widthM, poseWNrm);
      l = math.max(floor.lengthM, poseLNrm);
      src = 'poseDominant';
    }

    // Sanity: never shrink below either raw fit; cap runaway growth
    final rawMaxW = math.max(floor.widthM, pose.widthM);
    final rawMaxL = math.max(floor.lengthM, pose.lengthM);
    w = w.clamp(rawMaxW * 0.95, rawMaxW * 1.55 + 2 * stand);
    l = l.clamp(rawMaxL * 0.95, rawMaxL * 1.55 + 2 * stand);

    final cov = math.max(floor.coverageScore, pose.coverageScore * 0.9);
    final ortho = math.max(floor.orthogonalScore, pose.orthogonalScore * 0.95);

    return (
      widthM: math.max(w, l),
      lengthM: math.min(w, l),
      oppositeEdgeError: floor.oppositeEdgeError,
      diagonalError: floor.diagonalError,
      orthogonalScore: ortho.clamp(0.7, 0.98),
      coverageScore: cov.clamp(0.0, 1.0),
      fuseSource: src,
    );
  }

  /// Feet wrapper for [resolveWalkMeters].
  static ({
    double widthFt,
    double lengthFt,
    double oppositeEdgeError,
    double diagonalError,
    double orthogonalScore,
    double coverageScore,
    String fuseSource,
  })? resolveWalkFeet({
    List<List<double>> floorHits = const [],
    List<List<double>> poses = const [],
    double standoffM = defaultWalkStandoffM,
  }) {
    final m = resolveWalkMeters(
      floorHits: floorHits,
      poses: poses,
      standoffM: standoffM,
    );
    if (m == null) return null;
    const mToFt = 3.28084;
    return (
      widthFt: m.widthM * mToFt,
      lengthFt: m.lengthM * mToFt,
      oppositeEdgeError: m.oppositeEdgeError,
      diagonalError: m.diagonalError,
      orthogonalScore: m.orthogonalScore,
      coverageScore: m.coverageScore,
      fuseSource: m.fuseSource,
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

  /// Dense walk samples along rectangle perimeter (+125 easy scan).
  static List<List<double>> walkCloudRectM({
    required double widthM,
    required double lengthM,
    int samplesPerEdge = 6,
    double noiseM = 0.04,
    int seed = 3,
  }) {
    final rng = math.Random(seed);
    final out = <List<double>>[];
    void edge(double x0, double z0, double x1, double z1) {
      for (var i = 0; i <= samplesPerEdge; i++) {
        final t = i / samplesPerEdge;
        final x = x0 + (x1 - x0) * t + (rng.nextDouble() - 0.5) * 2 * noiseM;
        final z = z0 + (z1 - z0) * t + (rng.nextDouble() - 0.5) * 2 * noiseM;
        out.add([x, 0.0, z]);
      }
    }

    edge(0, 0, widthM, 0);
    edge(widthM, 0, widthM, lengthM);
    edge(widthM, lengthM, 0, lengthM);
    edge(0, lengthM, 0, 0);
    return out;
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

    final rawDot = (uxs.isNotEmpty && vxs.isNotEmpty)
        ? (uxs[0] * vxs[0] + uzs[0] * vzs[0]).abs()
        : 1.0;
    final orthogonalScore = (1.0 - rawDot).clamp(0.0, 1.0);

    final dot = ux * vx + uz * vz;
    vx -= dot * ux;
    vz -= dot * uz;
    vn = math.sqrt(vx * vx + vz * vz);
    if (vn < 1e-6) {
      vx = -uz;
      vz = ux;
    } else {
      vx /= vn;
      vz /= vn;
    }

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

  /// +125/+126: PCA axes + **percentile hull** + outlier trim (Open3D-class).
  ///
  /// Raw min–max AABB on AR hits overestimates when Instant Placement or
  /// depth noise lands far outside the room. Planner5D / magicplan-class maps
  /// use robust extents (percentiles) and completeness (angular coverage).
  static ({
    double widthM,
    double lengthM,
    double orthogonalScore,
    double coverageScore,
  })? _cloudOrthogonalFit(List<List<double>> pts) {
    if (pts.length < 4) return null;

    // Working set: drop gross outliers via iterative statistical filter.
    var work = List<List<double>>.from(pts);
    work = _statisticalOutlierTrim(work, maxIters: 2);

    var cx = 0.0, cz = 0.0;
    for (final p in work) {
      cx += p[0];
      cz += _z(p);
    }
    cx /= work.length;
    cz /= work.length;

    // Covariance on trimmed set
    var sxx = 0.0, sxz = 0.0, szz = 0.0;
    for (final p in work) {
      final dx = p[0] - cx;
      final dz = _z(p) - cz;
      sxx += dx * dx;
      sxz += dx * dz;
      szz += dz * dz;
    }
    sxx /= work.length;
    sxz /= work.length;
    szz /= work.length;

    final trace = sxx + szz;
    final det = sxx * szz - sxz * sxz;
    final disc = math.max(0.0, trace * trace / 4 - det);
    final lambda1 = trace / 2 + math.sqrt(disc);

    var ux = sxz;
    var uz = lambda1 - sxx;
    if (ux.abs() + uz.abs() < 1e-9) {
      ux = 1.0;
      uz = 0.0;
    }
    var un = math.sqrt(ux * ux + uz * uz);
    ux /= un;
    uz /= un;
    final vx = -uz;
    final vz = ux;

    final us = <double>[];
    final vs = <double>[];
    for (final p in work) {
      final dx = p[0] - cx;
      final dz = _z(p) - cz;
      us.add(dx * ux + dz * uz);
      vs.add(dx * vx + dz * vz);
    }

    // Percentile hull (p2–p98) — resists single far hits better than min/max.
    final uLo = _percentile(us, 0.02);
    final uHi = _percentile(us, 0.98);
    final vLo = _percentile(vs, 0.02);
    final vHi = _percentile(vs, 0.98);
    var sideA = (uHi - uLo).abs();
    var sideB = (vHi - vLo).abs();

    // Soft expand toward p0.5–p99.5 if coverage is strong (don't shrink true walls)
    final cov = _angularCoverage(work, cx, cz);
    if (cov >= 0.75) {
      final uLo2 = _percentile(us, 0.005);
      final uHi2 = _percentile(us, 0.995);
      final vLo2 = _percentile(vs, 0.005);
      final vHi2 = _percentile(vs, 0.995);
      // Blend 70% core + 30% outer so wall-edge samples count
      sideA = sideA * 0.70 + (uHi2 - uLo2).abs() * 0.30;
      sideB = sideB * 0.70 + (vHi2 - vLo2).abs() * 0.30;
    }

    if (sideA < 0.5 || sideB < 0.5) return null;

    // Fit quality: high when samples ring the room (Planner5D walk complete)
    final orthogonalScore = (0.78 + 0.20 * cov).clamp(0.70, 0.98);

    return (
      widthM: math.max(sideA, sideB),
      lengthM: math.min(sideA, sideB),
      orthogonalScore: orthogonalScore,
      coverageScore: cov,
    );
  }

  /// Angular coverage in 8 sectors around centroid (0..1). Incomplete walks
  /// leave opposite walls empty → user must keep walking (Planner5D tip).
  static double _angularCoverage(
    List<List<double>> pts,
    double cx,
    double cz,
  ) {
    if (pts.isEmpty) return 0;
    final bins = List<int>.filled(8, 0);
    for (final p in pts) {
      final a = math.atan2(_z(p) - cz, p[0] - cx);
      var i = ((a + math.pi) / (2 * math.pi) * 8).floor();
      if (i < 0) i = 0;
      if (i > 7) i = 7;
      bins[i]++;
    }
    final filled = bins.where((c) => c > 0).length;
    return filled / 8.0;
  }

  /// Remove points farther than [k]×MAD from median in XZ (Open3D SOR-lite).
  static List<List<double>> _statisticalOutlierTrim(
    List<List<double>> pts, {
    int maxIters = 2,
    double k = 3.5,
  }) {
    var work = pts;
    for (var iter = 0; iter < maxIters; iter++) {
      if (work.length < 8) break;
      var mx = 0.0, mz = 0.0;
      for (final p in work) {
        mx += p[0];
        mz += _z(p);
      }
      mx /= work.length;
      mz /= work.length;
      final dists = <double>[
        for (final p in work)
          math.sqrt(
            (p[0] - mx) * (p[0] - mx) + (_z(p) - mz) * (_z(p) - mz),
          ),
      ];
      final med = _percentile(dists, 0.5);
      final absDev = <double>[for (final d in dists) (d - med).abs()];
      final mad = _percentile(absDev, 0.5);
      if (mad < 0.05) break;
      final thr = med + k * mad * 1.4826; // MAD→σ scale
      final kept = <List<double>>[];
      for (var i = 0; i < work.length; i++) {
        if (dists[i] <= thr) kept.add(work[i]);
      }
      if (kept.length < 4 || kept.length == work.length) break;
      work = kept;
    }
    return work;
  }

  static double _percentile(List<double> values, double p) {
    if (values.isEmpty) return 0;
    final s = [...values]..sort();
    if (s.length == 1) return s.first;
    final t = (p.clamp(0.0, 1.0)) * (s.length - 1);
    final i = t.floor();
    final f = t - i;
    if (i >= s.length - 1) return s.last;
    return s[i] * (1 - f) + s[i + 1] * f;
  }

  static ({double ratio, double error}) _diagonalCheck(
    List<List<double>> ordered,
    double width,
    double length,
  ) {
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
