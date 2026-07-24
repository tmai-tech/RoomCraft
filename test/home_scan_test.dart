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
    expect(plan.accuracyScore, greaterThanOrEqualTo(0.90));
    expect(plan.warnings.any((w) => w.contains('Home Scan')), isTrue);
    final review = PhotoTrueLayout.resolveForReview(plan);
    expect(review.roomWidthFt, closeTo(plan.roomWidthFt, 0.5));
  });

  test('+127 HomeScanPackage JSON round-trip shape', () {
    const measure = ArRoomMeasure(
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

  test('+128 toPlanWithAiFurniture seeds layout (not empty square)', () {
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
    final pack = HomeScanPackage.fromMeasure(measure);
    final plan = pack.toPlanWithAiFurniture();
    expect(plan.furniture.where((f) => f.included), isNotEmpty);
    expect(plan.roomWidthFt, greaterThan(10));
    expect(
      plan.warnings.any((w) => w.contains('AI starter furniture')),
      isTrue,
    );
  });

  test('+130 fuse reports agreement and adaptive standoff', () {
    final floor = ArPolygonMap.walkCloudRectM(
      widthM: 5.0,
      lengthM: 3.5,
      samplesPerEdge: 8,
      noiseM: 0.02,
    );
    final poses = ArPolygonMap.walkCloudRectM(
      widthM: 3.5,
      lengthM: 2.0,
      samplesPerEdge: 8,
      noiseM: 0.02,
      seed: 5,
    );
    final r = ArPolygonMap.resolveWalkMeters(
      floorHits: floor,
      poses: poses,
      standoffM: 0.75,
    );
    expect(r, isNotNull);
    expect(r!.agreement, greaterThan(0.0));
    expect(r.standoffUsedM, greaterThanOrEqualTo(0.35));
    expect(r.standoffUsedM, lessThanOrEqualTo(1.25));
    expect(r.fuseSource, isNotEmpty);
  });

  test('+130 AI furniture wall-anchored + openings present', () {
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
    final pack = HomeScanPackage.fromMeasure(measure);
    final plan = pack.toPlanWithAiFurniture();
    expect(plan.furniture.where((f) => f.included), isNotEmpty);
    expect(plan.walls.any((s) => s.type == StrokeType.door), isTrue);
    final w = plan.roomWidthFt;
    final l = plan.roomLengthFt;
    var nearWall = 0;
    for (final f in plan.furniture.where((x) => x.included)) {
      final cx = f.posFt.dx;
      final cy = f.posFt.dy;
      final d = [cx, w - cx, cy, l - cy].reduce((a, b) => a < b ? a : b);
      if (d < 3.5) nearWall++;
    }
    expect(nearWall, greaterThan(0));
    expect(
      plan.warnings.any((w) => w.contains('+130') || w.contains('wall-anchored')),
      isTrue,
    );
  });
}
