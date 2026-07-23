import 'dart:math' as math;

/// Multi-dot floor polygon → room W×L (+123).
///
/// Planner 5D / magicplan-class accuracy uses **metric geometry** from the
/// device (AR/LiDAR), not monocular photos. RoomCraft's high-accuracy path
/// marks floor **corner dots** (a sparse point map), then reconstructs a
/// rectangle from ordered edges — same spirit as multi-dot / point-cloud
/// wall mapping without needing a full dense cloud on-device.
///
/// Python research analogues (server / offline experiments):
/// - Open3D plane segmentation + RANSAC wall extraction
/// - RTAB-Map / ORB-SLAM3 sparse maps
/// - AliceVision Meshroom photogrammetry (offline video)
/// - scipy.spatial ConvexHull on floor-projected points
class ArPolygonMap {
  ArPolygonMap._();

  /// One floor hit in meters (ARCore world frame; Y up).
  static ({double widthM, double lengthM, double oppositeEdgeError})?
      resolveMeters(List<List<double>> dotsXyz) {
    if (dotsXyz.length < 4) return null;
    final pts = dotsXyz.take(4).toList();
    var cx = 0.0;
    var cz = 0.0;
    for (final p in pts) {
      cx += p[0];
      cz += p.length > 2 ? p[2] : p[1];
    }
    cx /= pts.length;
    cz /= pts.length;

    final ordered = [...pts]..sort((a, b) {
        final az = a.length > 2 ? a[2] : a[1];
        final bz = b.length > 2 ? b[2] : b[1];
        final aa = math.atan2(az - cz, a[0] - cx);
        final bb = math.atan2(bz - cz, b[0] - cx);
        return aa.compareTo(bb);
      });

    final edges = List<double>.filled(4, 0);
    for (var i = 0; i < 4; i++) {
      final a = ordered[i];
      final b = ordered[(i + 1) % 4];
      final az = a.length > 2 ? a[2] : a[1];
      final bz = b.length > 2 ? b[2] : b[1];
      final dx = a[0] - b[0];
      final dz = az - bz;
      edges[i] = math.sqrt(dx * dx + dz * dz);
    }

    final sideA = (edges[0] + edges[2]) / 2.0;
    final sideB = (edges[1] + edges[3]) / 2.0;
    if (sideA < 0.5 || sideB < 0.5) return null;

    final width = math.max(sideA, sideB);
    final length = math.min(sideA, sideB);
    final errA = edges[0] <= 0 ? 0.0 : (edges[0] - edges[2]).abs() / edges[0];
    final errB = edges[1] <= 0 ? 0.0 : (edges[1] - edges[3]).abs() / edges[1];
    final opp = errA > errB ? errA : errB;
    return (widthM: width, lengthM: length, oppositeEdgeError: opp);
  }

  /// Same as [resolveMeters] but returns feet (ARCore convention × 3.28084).
  static ({double widthFt, double lengthFt, double oppositeEdgeError})?
      resolveFeet(List<List<double>> dotsXyz) {
    final m = resolveMeters(dotsXyz);
    if (m == null) return null;
    const mToFt = 3.28084;
    return (
      widthFt: m.widthM * mToFt,
      lengthFt: m.lengthM * mToFt,
      oppositeEdgeError: m.oppositeEdgeError,
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
}
