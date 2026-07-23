import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/ar_polygon_map.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/services/ar_measure_service.dart';

/// +123 multi-dot floor polygon → room size (Planner5D-class AR path).
void main() {
  test('+123 rect corners resolve exact W×L meters', () {
    final dots = ArPolygonMap.rectCornersM(widthM: 6.0, lengthM: 4.0);
    final r = ArPolygonMap.resolveMeters(dots);
    expect(r, isNotNull);
    expect(r!.widthM, closeTo(6.0, 0.02));
    expect(r.lengthM, closeTo(4.0, 0.02));
    expect(r.oppositeEdgeError, lessThan(0.02));
  });

  test('+123 feet conversion for typical study-size room', () {
    // 20.3 × 17.0 ft ≈ 6.187 × 5.182 m
    final wM = 20.3 / 3.28084;
    final lM = 17.0 / 3.28084;
    final dots = ArPolygonMap.rectCornersM(widthM: wM, lengthM: lM, originX: 1.2, originZ: -0.5);
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
        'Room size from AR 4-corner multi-dot map (15.5 × 11.0 ft)',
        'Scale lock (+108/+119/+123): AR 4-corner multi-dot map floor 96%',
        '100% AR measured room geometry (+123 multi-dot)',
      ],
      accuracyScore: 1.0,
    );
    expect(PhotoTrueLayout.hasMeasuredScaleLock(ar), isTrue);
    final out = PhotoTrueLayout.resolveForReview(ar);
    expect(out.roomWidthFt, closeTo(15.5, 0.01));
    expect(out.roomLengthFt, closeTo(11.0, 0.01));
    expect(out.accuracyScore, closeTo(1.0, 0.001));
    expect(
      out.furniture.where((f) => f.included),
      isEmpty,
    );
  });

  test('+123 ArRoomMeasure polygon summary + isPolygon', () {
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
      'source': 'arcore',
    });
    expect(m.isPolygon, isTrue);
    expect(m.summaryLabel, contains('multi-dot'));
    expect(m.oppositeWallError, lessThan(0.01));
  });
}
