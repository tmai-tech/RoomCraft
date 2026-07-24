import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/ar_polygon_map.dart';
import 'package:room_craft/domain/home_scan.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/models/stroke_model.dart';
import 'package:room_craft/services/ar_measure_service.dart';

void main() {
  test('+127 HomeScanPackage toPlan from walk cloud is metric empty plan', () {
    final cloud = ArPolygonMap.walkCloudRectM(widthM: 5.0, lengthM: 4.0);
    final flat = <double>[];
    for (final p in cloud) {
      flat.addAll(p);
    }
    final measure = ArRoomMeasure(
      widthFt: 16.4,
      lengthFt: 13.1,
      widthM: 5.0,
      lengthM: 4.0,
      mode: 'auto',
      cornersM: flat,
      sampleCount: cloud.length,
      coverageScore: 0.9,
      orthogonalScore: 0.95,
    );
    final pack = HomeScanPackage.fromMeasure(measure, appVersion: 'test+127');
    expect(pack.sampleCount, greaterThanOrEqualTo(20));
    final plan = pack.toPlan();
    expect(plan.roomWidthFt, greaterThan(10));
    expect(plan.roomLengthFt, greaterThan(8));
    expect(plan.furniture, isEmpty);
    expect(plan.accuracyScore, greaterThanOrEqualTo(0.90));
    expect(plan.warnings.any((w) => w.contains('Home Scan')), isTrue);
    // Must not force study gold (measured scale lock)
    final review = PhotoTrueLayout.resolveForReview(plan);
    expect(review.roomWidthFt, closeTo(plan.roomWidthFt, 0.5));
    expect(review.furniture.where((f) => f.included), isEmpty);
  });

  test('+127 HomeScanPackage JSON round-trip shape', () {
    final measure = const ArRoomMeasure(
      widthFt: 12,
      lengthFt: 10,
      widthM: 3.66,
      lengthM: 3.05,
      mode: 'auto',
      cornersM: [0, 0, 0, 3, 0, 0, 3, 0, 4, 0, 0, 4],
      posesM: [0, 1.5, 0, 1, 1.5, 0, 2, 1.5, 1],
      sampleCount: 4,
      poseCount: 3,
      coverageScore: 0.8,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final json = pack.toJson();
    expect(json['schema'], 'roomcraft_home_scan_v1');
    expect(json['floor_hits_m'], isA<List>());
    expect(json['poses_m'], isA<List>());
    expect((json['poses_m'] as List).length, 3);
    expect(HomeScanGeometry.posePathLengthM(pack.posesM), greaterThan(0));
  });

  test('+127 ArRoomMeasure parses posesM from map', () {
    final m = ArRoomMeasure.fromMap({
      'widthFt': 14.0,
      'lengthFt': 11.0,
      'widthM': 4.27,
      'lengthM': 3.35,
      'mode': 'auto',
      'cornersM': [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0],
      'posesM': [0.0, 1.0, 0.0, 0.5, 1.0, 0.2],
      'sampleCount': 4,
      'poseCount': 2,
      'coverageScore': 0.85,
      'orthogonalScore': 0.9,
      'source': 'arcore',
    });
    expect(m.isAuto, isTrue);
    expect(m.poseCount, 2);
    expect(m.posesM.length, 6);
    expect(m.summaryLabel, contains('walk'));
  });

  test('+128 pose+floor fuse expands incomplete floor toward true size', () {
    // Floor hits only cover a 3×2 patch; poses walk a 4×3 interior path
    final floor = ArPolygonMap.walkCloudRectM(
      widthM: 3.0,
      lengthM: 2.0,
      samplesPerEdge: 5,
      noiseM: 0.03,
    );
    // Interior path ~0.75m inset from 5×3.5 walls → path ~3.5×2.0
    final poses = ArPolygonMap.walkCloudRectM(
      widthM: 3.5,
      lengthM: 2.0,
      samplesPerEdge: 8,
      noiseM: 0.02,
      seed: 11,
    );
    final fused = ArPolygonMap.resolveWalkMeters(
      floorHits: floor,
      poses: poses,
      standoffM: 0.75,
    );
    expect(fused, isNotNull);
    // Should be larger than bare incomplete floor
    final floorOnly = ArPolygonMap.resolveMeters(floor)!;
    expect(fused!.widthM, greaterThan(floorOnly.widthM - 0.01));
    // Pose+standoff pushes toward ~5m class room
    expect(fused.widthM, greaterThan(3.2));
    expect(fused.fuseSource, isNot(equals('')));
  });

  test('+128 HomeScanPackage toPlan has assist openings + fuse note', () {
    final floor = ArPolygonMap.walkCloudRectM(widthM: 5.0, lengthM: 3.5);
    final poses = ArPolygonMap.walkCloudRectM(
      widthM: 3.5,
      lengthM: 2.0,
      samplesPerEdge: 6,
      seed: 2,
    );
    final flatF = <double>[];
    for (final p in floor) {
      flatF.addAll(p);
    }
    final flatP = <double>[];
    for (final p in poses) {
      flatP.addAll(p);
    }
    final measure = ArRoomMeasure(
      widthFt: 16.4,
      lengthFt: 11.5,
      widthM: 5.0,
      lengthM: 3.5,
      mode: 'auto',
      cornersM: flatF,
      posesM: flatP,
      sampleCount: floor.length,
      poseCount: poses.length,
      coverageScore: 0.6,
      orthogonalScore: 0.9,
    );
    final pack = HomeScanPackage.fromMeasure(measure, appVersion: 'test+128');
    final plan = pack.toPlan();
    expect(plan.warnings.any((w) => w.contains('+128') || w.contains('fuse')), isTrue);
    // Assist door/window so plan is not bare box
    expect(plan.walls.any((s) => s.type == StrokeType.door), isTrue);
    expect(plan.furniture, isEmpty);
    expect(pack.resolvedSize.fuseSource, isNotEmpty);
  });
}
