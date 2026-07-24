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

  test('+135 wall-lock measure expands under-sized cloud', () {
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 3.0,
      lengthM: 2.5,
      samplesPerEdge: 6,
    );
    final flat = <double>[];
    for (final p in cloud) {
      flat.addAll(p);
    }
    // Floor cloud under-sizes; vertical wall lock has true 5×4 m
    final measure = ArRoomMeasure(
      widthFt: 9.8,
      lengthFt: 8.2,
      widthM: 3.0,
      lengthM: 2.5,
      mode: 'auto',
      cornersM: flat,
      sampleCount: cloud.length,
      poseCount: 20,
      coverageScore: 0.55,
      orthogonalScore: 0.9,
      wallLockWidthM: 5.0,
      wallLockLengthM: 4.0,
      wallLockPairs: 2,
    );
    expect(measure.hasWallLock, isTrue);
    final pack = HomeScanPackage.fromMeasure(measure);
    final size = pack.resolvedSize;
    // Wall lock ~5×4 m → ≥16×13 ft; under-sized 3m cloud must expand
    expect(size.widthFt, greaterThan(13.5));
    expect(size.lengthFt, greaterThan(11.0));
    expect(
      size.fuseSource.contains('wallLock') || size.widthFt > 12,
      isTrue,
    );
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

  test('+135 wall-distance fuse yields usable furniture plan', () {
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 6.0,
      lengthM: 4.5,
      samplesPerEdge: 10,
    );
    final flat = <double>[for (final p in cloud) ...p];
    // Interior pose trail
    final poses = <double>[
      for (var i = 0; i < 20; i++) ...[1.2 + i * 0.15, 1.5, 1.5 + (i % 4) * 0.2],
    ];
    final measure = ArRoomMeasure(
      widthFt: 19.7,
      lengthFt: 14.8,
      widthM: 6.0,
      lengthM: 4.5,
      mode: 'auto',
      cornersM: flat,
      posesM: poses,
      sampleCount: cloud.length,
      poseCount: 20,
      coverageScore: 0.7,
      orthogonalScore: 0.9,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    expect(pack.qualityRejectReason(), isNull);
    final plan = pack.toPlanWithAiFurniture();
    expect(plan.roomWidthFt, greaterThan(14));
    expect(plan.roomLengthFt, greaterThan(10));
    expect(plan.furniture.where((f) => f.included).length, greaterThanOrEqualTo(4));
    // Closed perimeter walls present
    final walls = plan.walls.where((s) => s.type == StrokeType.wall).length;
    expect(walls, greaterThanOrEqualTo(4));
    final ed = ScanParser.toEditor(plan, 20);
    expect(ed.strokes.where((s) => s.type == StrokeType.wall).length, 4);
  });

  test('+136 pathExpand grows under-sized map after long walk', () {
    // Small cloud (~3×2.5 m) but long interior pose loop (~full perimeter)
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 3.0,
      lengthM: 2.5,
      samplesPerEdge: 6,
    );
    final flat = <double>[for (final p in cloud) ...p];
    // Loop path around interior (~0.6 m inset) — long walk
    final poses = <double>[];
    for (var i = 0; i < 20; i++) {
      final t = i / 20.0;
      poses.addAll([0.5 + t * 2.0, 1.5, 0.5]); // bottom
    }
    for (var i = 0; i < 16; i++) {
      final t = i / 16.0;
      poses.addAll([2.5, 1.5, 0.5 + t * 1.5]); // right
    }
    for (var i = 0; i < 20; i++) {
      final t = i / 20.0;
      poses.addAll([2.5 - t * 2.0, 1.5, 2.0]); // top
    }
    for (var i = 0; i < 16; i++) {
      final t = i / 16.0;
      poses.addAll([0.5, 1.5, 2.0 - t * 1.5]); // left
    }
    final measure = ArRoomMeasure(
      widthFt: 9.8,
      lengthFt: 8.2,
      widthM: 3.0,
      lengthM: 2.5,
      mode: 'auto',
      cornersM: flat,
      posesM: poses,
      sampleCount: cloud.length,
      poseCount: poses.length ~/ 3,
      coverageScore: 0.55,
      orthogonalScore: 0.88,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final size = pack.resolvedSize;
    // Path expand should enlarge beyond raw ~9.8×8.2 when path is long
    expect(size.fuseSource.contains('pathExpand') || size.widthFt > 9.8, isTrue);
    final plan = pack.toPlanWithAiFurniture();
    expect(plan.furniture.where((f) => f.included).length, greaterThanOrEqualTo(4));
    final ed = ScanParser.toEditor(plan, 20);
    expect(ed.strokes.where((s) => s.type == StrokeType.wall).length, 4);
  });
}
