import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/ar_polygon_map.dart';
import 'package:room_craft/domain/home_scan.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/models/stroke_model.dart';
import 'package:room_craft/services/ar_measure_service.dart';

void main() {
  test('+133 toPlanWithAiFurniture not empty + closed walls in editor', () {
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
    expect(plan.furniture.where((f) => f.included).length, greaterThanOrEqualTo(4));
    final ed = ScanParser.toEditor(plan, 20);
    expect(ed.strokes.where((s) => s.type == StrokeType.wall).length, 4);
    expect(ed.furniture, isNotEmpty);
    expect(ed.width, greaterThan(10));
  });

  test('+134 rejects weak 10×10 incomplete walk (225fb5de class)', () {
    // Sparse corners → under-sized square map like feedback screenshot
    final measure = const ArRoomMeasure(
      widthFt: 10.0,
      lengthFt: 10.0,
      widthM: 3.05,
      lengthM: 3.05,
      mode: 'auto',
      cornersM: [0, 0, 0, 3, 0, 0, 3, 0, 3, 0, 0, 3],
      sampleCount: 4,
      poseCount: 3,
      coverageScore: 0.35,
      orthogonalScore: 0.7,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    expect(pack.qualityRejectReason(), isNotNull);
    expect(pack.qualityRejectReason()!.toLowerCase(), contains('walk'));
  });

  test('+134 good full walk passes quality gate', () {
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 5.5,
      lengthM: 4.2,
      samplesPerEdge: 8,
    );
    final flat = <double>[];
    for (final p in cloud) {
      flat.addAll(p);
    }
    final measure = ArRoomMeasure(
      widthFt: 18.0,
      lengthFt: 13.8,
      widthM: 5.5,
      lengthM: 4.2,
      mode: 'auto',
      cornersM: flat,
      sampleCount: cloud.length,
      poseCount: 30,
      coverageScore: 0.88,
      orthogonalScore: 0.94,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    expect(pack.qualityRejectReason(), isNull);
  });

  test('+127 package JSON shape', () {
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
    expect((json['poses_m'] as List).length, 3);
  });
}
