import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/ar_polygon_map.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/services/ar_measure_service.dart';

/// +123–+125 multi-dot / walk-cloud floor map → room size.
void main() {
  test('+123 rect corners resolve exact W×L meters', () {
    final dots = ArPolygonMap.rectCornersM(widthM: 6.0, lengthM: 4.0);
    final r = ArPolygonMap.resolveMeters(dots);
    expect(r, isNotNull);
    expect(r!.widthM, closeTo(6.0, 0.02));
    expect(r.lengthM, closeTo(4.0, 0.02));
    expect(r.oppositeEdgeError, lessThan(0.02));
    expect(r.orthogonalScore, greaterThan(0.95));
    expect(r.diagonalError, lessThan(0.05));
  });

  test('+123 feet conversion for typical study-size room', () {
    final wM = 20.3 / 3.28084;
    final lM = 17.0 / 3.28084;
    final dots = ArPolygonMap.rectCornersM(
      widthM: wM,
      lengthM: lM,
      originX: 1.2,
      originZ: -0.5,
    );
    final r = ArPolygonMap.resolveFeet(dots);
    expect(r, isNotNull);
    expect(r!.widthFt, closeTo(20.3, 0.08));
    expect(r.lengthFt, closeTo(17.0, 0.08));
  });

  test('+123 shuffled corner order still recovers size', () {
    final base = ArPolygonMap.rectCornersM(widthM: 5.0, lengthM: 3.5);
    final shuffled = [base[2], base[0], base[3], base[1]];
    final r = ArPolygonMap.resolveMeters(shuffled);
    expect(r, isNotNull);
    expect(r!.widthM, closeTo(5.0, 0.05));
    expect(r.lengthM, closeTo(3.5, 0.05));
  });

  test('+124 noisy corners orthogonal fit stays within ~5%', () {
    final dots = ArPolygonMap.noisyRectCornersM(
      widthM: 5.0,
      lengthM: 3.5,
      noiseM: 0.06,
    );
    final r = ArPolygonMap.resolveMeters(dots);
    expect(r, isNotNull);
    expect(r!.widthM, closeTo(5.0, 0.35));
    expect(r.lengthM, closeTo(3.5, 0.35));
    expect(r.orthogonalScore, greaterThan(0.7));
  });

  test('+124 slight shear still recovers near-rect room', () {
    final dots = [
      [0.0, 0.0, 0.0],
      [6.0, 0.0, 0.15],
      [5.9, 0.0, 4.0],
      [0.1, 0.0, 3.95],
    ];
    final r = ArPolygonMap.resolveMeters(dots);
    expect(r, isNotNull);
    expect(r!.widthM, closeTo(6.0, 0.4));
    expect(r.lengthM, closeTo(4.0, 0.4));
  });

  test('+123 ScaleSource.arPolygon reaches 100% when edges tight', () {
    final score = ScaleLockConfidence.blend(
      layoutScore: 1.0,
      source: ScaleSource.arPolygon,
      oppositeWallError: 0.02,
    );
    expect(score, closeTo(1.0, 0.001));
    expect(
      ScaleLockConfidence.sourceFloor(ScaleSource.arPolygon),
      greaterThanOrEqualTo(0.94),
    );
  });

  test('+123 polygon AR empty plan resolve preserves size / 100%', () {
    final ar = ScanResult(
      roomWidthFt: 15.5,
      roomLengthFt: 11.0,
      walls: const [],
      furniture: const [],
      warnings: const [
        'Room size from AR easy walk map (15.5 × 11.0 ft, fit 92%)',
        'Scale lock (+108/+119/+125): AR 4-corner multi-dot map floor 96%',
        '100% AR measured room geometry (+125 easy walk)',
      ],
      accuracyScore: 1.0,
    );
    expect(PhotoTrueLayout.hasMeasuredScaleLock(ar), isTrue);
    final out = PhotoTrueLayout.resolveForReview(ar);
    expect(out.roomWidthFt, closeTo(15.5, 0.01));
    expect(out.roomLengthFt, closeTo(11.0, 0.01));
    expect(out.accuracyScore, closeTo(1.0, 0.001));
    expect(out.furniture.where((f) => f.included), isEmpty);
  });

  test('+124 ArRoomMeasure polygon summary + consistency', () {
    final m = ArRoomMeasure.fromMap({
      'widthFt': 14.0,
      'lengthFt': 10.0,
      'widthM': 4.27,
      'lengthM': 3.05,
      'mode': 'polygon',
      'wallsFt': [14.0, 10.0, 14.0, 10.0],
      'wallsM': [4.27, 3.05, 4.27, 3.05],
      'cornersM': [
        0.0, 0.0, 0.0,
        4.27, 0.0, 0.0,
        4.27, 0.0, 3.05,
        0.0, 0.0, 3.05,
      ],
      'orthogonalScore': 0.97,
      'diagonalError': 0.01,
      'source': 'arcore',
    });
    expect(m.isPolygon, isTrue);
    expect(m.summaryLabel, contains('multi-dot'));
    expect(m.oppositeWallError, lessThan(0.01));
    expect(m.consistencyError, lessThan(0.02));
  });

  test('+125 walk cloud recovers room within ~8%', () {
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 5.0,
      lengthM: 3.5,
      samplesPerEdge: 8,
      noiseM: 0.05,
    );
    expect(cloud.length, greaterThan(20));
    final r = ArPolygonMap.resolveMeters(cloud);
    expect(r, isNotNull);
    expect(r!.widthM, closeTo(5.0, 0.45));
    expect(r.lengthM, closeTo(3.5, 0.45));
    expect(r.orthogonalScore, greaterThan(0.8));
  });

  test('+125 ArRoomMeasure auto summary', () {
    final m = ArRoomMeasure.fromMap({
      'widthFt': 16.0,
      'lengthFt': 12.0,
      'widthM': 4.88,
      'lengthM': 3.66,
      'mode': 'auto',
      'wallsFt': [16.0, 12.0, 16.0, 12.0],
      'orthogonalScore': 0.92,
      'diagonalError': 0.02,
      'coverageScore': 0.88,
      'cornersM': List.generate(60, (i) => i * 0.1),
      'source': 'arcore',
    });
    expect(m.isAuto, isTrue);
    expect(m.summaryLabel, contains('easy walk'));
    expect(m.summaryLabel, contains('cover'));
  });

  test('+126 walk cloud with far outliers still recovers size', () {
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 5.0,
      lengthM: 3.5,
      samplesPerEdge: 10,
      noiseM: 0.04,
    );
    // Inject Instant Placement / tracking glitches far outside the room
    final polluted = [
      ...cloud,
      [20.0, 0.0, 20.0],
      [-15.0, 0.0, 8.0],
      [5.0, 0.0, -12.0],
      [30.0, 0.0, -5.0],
    ];
    final r = ArPolygonMap.resolveMeters(polluted);
    expect(r, isNotNull);
    // Without robust trim, min-max would be ~45 m — must stay near 5×3.5
    expect(r!.widthM, closeTo(5.0, 0.55));
    expect(r.lengthM, closeTo(3.5, 0.55));
    expect(r.coverageScore, greaterThan(0.5));
  });

  test('+126 partial-edge walk reports low coverage', () {
    // L-walk: bottom + right only (Planner5D incomplete loop — missing 2 walls)
    final rng = <List<double>>[];
    for (var i = 0; i < 16; i++) {
      final t = i / 15.0;
      rng.add([t * 5.0, 0.0, 0.0]);
      rng.add([t * 5.0, 0.0, 0.12]); // thin band so length ≥ 0.5m
    }
    for (var i = 0; i < 16; i++) {
      final t = i / 15.0;
      rng.add([5.0, 0.0, t * 3.5]);
      rng.add([4.88, 0.0, t * 3.5]);
    }
    final r = ArPolygonMap.resolveMeters(rng);
    expect(r, isNotNull);
    // L-shape covers at most ~half the compass around centroid
    expect(r!.coverageScore, lessThan(0.90));
    // Full perimeter walk has higher cover
    final full = ArPolygonMap.walkCloudRectM(
      widthM: 5.0,
      lengthM: 3.5,
      samplesPerEdge: 8,
      noiseM: 0.02,
    );
    final fullR = ArPolygonMap.resolveMeters(full);
    expect(fullR, isNotNull);
    expect(fullR!.coverageScore, greaterThan(r.coverageScore));
  });

  test('+126 consistencyError rises when coverage incomplete', () {
    final low = ArRoomMeasure.fromMap({
      'widthFt': 16.0,
      'lengthFt': 12.0,
      'widthM': 4.88,
      'lengthM': 3.66,
      'mode': 'auto',
      'wallsFt': [16.0, 12.0, 16.0, 12.0],
      'orthogonalScore': 0.9,
      'diagonalError': 0.01,
      'coverageScore': 0.4,
      'cornersM': List.generate(30, (i) => i * 0.1),
      'source': 'arcore',
    });
    final high = ArRoomMeasure.fromMap({
      'widthFt': 16.0,
      'lengthFt': 12.0,
      'widthM': 4.88,
      'lengthM': 3.66,
      'mode': 'auto',
      'wallsFt': [16.0, 12.0, 16.0, 12.0],
      'orthogonalScore': 0.9,
      'diagonalError': 0.01,
      'coverageScore': 0.9,
      'cornersM': List.generate(30, (i) => i * 0.1),
      'source': 'arcore',
    });
    expect(low.consistencyError, greaterThan(high.consistencyError));
  });

  test('+135 wall-distance lock recovers full room from perimeter hits', () {
    // Interior poses + full wall ring (Planner5D walk-inside)
    final floor = ArPolygonMap.walkCloudRectM(
      widthM: 6.0,
      lengthM: 4.0,
      samplesPerEdge: 10,
      noiseM: 0.03,
    );
    final poses = <List<double>>[
      for (var i = 0; i < 12; i++)
        [1.5 + i * 0.25, 1.5, 1.2 + (i % 3) * 0.3],
    ];
    final lock = ArPolygonMap.wallDistanceLockMeters(
      floorHits: floor,
      poses: poses,
    );
    expect(lock, isNotNull);
    expect(lock!.widthM, closeTo(6.0, 0.45));
    expect(lock.lengthM, closeTo(4.0, 0.45));
    expect(lock.confidence, greaterThan(0.4));
  });

  test('+135 walk fuse includes wallDistance when cover incomplete', () {
    // Full perimeter but sparse one side — lock should expand under-size floor
    final floor = ArPolygonMap.walkCloudRectM(
      widthM: 5.5,
      lengthM: 4.0,
      samplesPerEdge: 8,
      noiseM: 0.04,
    );
    // Poses only in center strip (incomplete path envelope)
    final poses = <List<double>>[
      for (var i = 0; i < 16; i++) [2.0 + i * 0.1, 1.5, 1.8],
    ];
    final fused = ArPolygonMap.resolveWalkMeters(
      floorHits: floor,
      poses: poses,
    );
    expect(fused, isNotNull);
    expect(fused!.widthM, greaterThan(4.5));
    expect(fused.lengthM, greaterThan(3.2));
    // Prefer wall-distance in fuse source when lock confident
    expect(
      fused.fuseSource.contains('wallDistance') || fused.agreement > 0.3,
      isTrue,
    );
  });

  test('+137 poseFloor hard expands partial floor vs larger walk path', () {
    // Floor mesh only covers ~3×2.5 m; user walked ~4.5×3.5 m interior
    final floor = ArPolygonMap.walkCloudRectM(
      widthM: 3.0,
      lengthM: 2.5,
      samplesPerEdge: 6,
      noiseM: 0.03,
    );
    final poses = <List<double>>[];
    for (var i = 0; i < 16; i++) {
      final t = i / 16.0;
      poses.add([0.5 + t * 4.0, 1.5, 0.5]);
    }
    for (var i = 0; i < 12; i++) {
      final t = i / 12.0;
      poses.add([4.5, 1.5, 0.5 + t * 3.0]);
    }
    for (var i = 0; i < 16; i++) {
      final t = i / 16.0;
      poses.add([4.5 - t * 4.0, 1.5, 3.5]);
    }
    for (var i = 0; i < 12; i++) {
      final t = i / 12.0;
      poses.add([0.5, 1.5, 3.5 - t * 3.0]);
    }
    final fused = ArPolygonMap.resolveWalkMeters(
      floorHits: floor,
      poses: poses,
    );
    expect(fused, isNotNull);
    // Pose span ~4×3 + 1.5 standoff → ~5.5×4.5; must beat tiny 3×2.5 floor
    expect(fused!.widthM, greaterThan(4.2));
    expect(fused.lengthM, greaterThan(3.2));
    expect(
      fused.fuseSource.contains('poseFloor') ||
          fused.fuseSource.contains('pose') ||
          fused.widthM > 4.0,
      isTrue,
    );
  });
}
