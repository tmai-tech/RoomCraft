import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/ar_polygon_map.dart';
import 'package:room_craft/domain/home_scan.dart';
import 'package:room_craft/domain/home_scan_inventory.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/models/furniture_item.dart';
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

  test('+137 pose envelope hard floor expands partial floor mesh', () {
    // Tiny floor cloud (~2.8×2.4 m) but interior pose trail of ~4.2×3.2 m
    // (user walked more of the room than AR floor mesh covered)
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 2.8,
      lengthM: 2.4,
      samplesPerEdge: 5,
    );
    final flat = <double>[for (final p in cloud) ...p];
    // Pose loop inset ~0.7 m in a ~5.6×4.6 room → path span ~4.2×3.2
    final poses = <double>[];
    for (var i = 0; i < 18; i++) {
      final t = i / 18.0;
      poses.addAll([0.7 + t * 4.2, 1.5, 0.7]);
    }
    for (var i = 0; i < 14; i++) {
      final t = i / 14.0;
      poses.addAll([4.9, 1.5, 0.7 + t * 3.2]);
    }
    for (var i = 0; i < 18; i++) {
      final t = i / 18.0;
      poses.addAll([4.9 - t * 4.2, 1.5, 3.9]);
    }
    for (var i = 0; i < 14; i++) {
      final t = i / 14.0;
      poses.addAll([0.7, 1.5, 3.9 - t * 3.2]);
    }
    final measure = ArRoomMeasure(
      widthFt: 9.2,
      lengthFt: 7.9,
      widthM: 2.8,
      lengthM: 2.4,
      mode: 'auto',
      cornersM: flat,
      posesM: poses,
      sampleCount: cloud.length,
      poseCount: poses.length ~/ 3,
      coverageScore: 0.40,
      orthogonalScore: 0.85,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final size = pack.resolvedSize;
    // Pose span ~4.2×3.2 + 1.5 standoff ≈ 5.7×4.7 m → ≥15×12 ft
    expect(size.widthFt, greaterThan(12.5));
    expect(size.lengthFt, greaterThan(10.0));
    expect(
      size.fuseSource.contains('poseFloor') ||
          size.fuseSource.contains('poseAabb') ||
          size.fuseSource.contains('pathExpand') ||
          size.fuseSource.contains('pose'),
      isTrue,
    );
    final plan = pack.toPlanWithAiFurniture();
    expect(plan.furniture.where((f) => f.included).length, greaterThanOrEqualTo(4));
    expect(plan.walls.where((s) => s.type == StrokeType.wall).length, greaterThanOrEqualTo(4));
    final ed = ScanParser.toEditor(plan, 20);
    expect(ed.strokes.where((s) => s.type == StrokeType.wall).length, 4);
  });

  test('+137 poseAabbMeters recovers walk envelope', () {
    final poses = <List<double>>[
      for (var i = 0; i < 10; i++) [i * 0.4, 1.5, 0.0],
      for (var i = 0; i < 8; i++) [4.0, 1.5, i * 0.35],
    ];
    final aabb = HomeScanGeometry.poseAabbMeters(poses);
    expect(aabb, isNotNull);
    expect(aabb!.widthM, closeTo(4.0, 0.05));
    expect(aabb.lengthM, closeTo(2.45, 0.15));
  });

  test('+140 inventory plan: 2 doors, French window, desk, table, bean bag', () {
    final measure = ArRoomMeasure(
      widthFt: 16.0,
      lengthFt: 12.0,
      widthM: 16.0 / 3.28084,
      lengthM: 12.0 / 3.28084,
      mode: 'auto',
      source: 'user_confirm',
      sampleCount: 40,
      poseCount: 30,
      coverageScore: 0.9,
      orthogonalScore: 0.95,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final plan = pack.toPlanWithInventory(HomeScanInventory.loungeOffice);
    final doors =
        plan.walls.where((s) => s.type == StrokeType.door).length;
    final windows =
        plan.walls.where((s) => s.type == StrokeType.window).length;
    expect(doors, greaterThanOrEqualTo(2));
    expect(windows, greaterThanOrEqualTo(1));
    // French window is wide
    final maxWin = plan.walls
        .where((s) => s.type == StrokeType.window)
        .map((s) => s.lengthFt)
        .fold<double>(0, (a, b) => a > b ? a : b);
    expect(maxWin, greaterThanOrEqualTo(5.0));
    final types =
        plan.furniture.where((f) => f.included).map((f) => f.type).toSet();
    expect(types.contains(FurnitureType.desk), isTrue);
    expect(types.contains(FurnitureType.table), isTrue);
    expect(types.contains(FurnitureType.chair), isTrue); // bean bag
    expect(types.contains(FurnitureType.bed), isFalse);
    final ed = ScanParser.toEditor(plan, 20);
    expect(ed.strokes.where((s) => s.type == StrokeType.wall).length, 4);
  });

  test('+143 study gold inventory = wardrobe + dual doors + desk (not sparse)', () {
    final measure = ArRoomMeasure(
      widthFt: 20.3,
      lengthFt: 17.0,
      widthM: 20.3 / 3.28084,
      lengthM: 17.0 / 3.28084,
      mode: 'auto',
      source: 'user_confirm',
      sampleCount: 50,
      poseCount: 40,
      coverageScore: 0.92,
      orthogonalScore: 0.95,
    );
    final plan = HomeScanPackage.fromMeasure(measure)
        .toPlanWithInventory(HomeScanInventory.studyGold);
    final types =
        plan.furniture.where((f) => f.included).map((f) => f.type).toSet();
    expect(types.contains(FurnitureType.wardrobe), isTrue);
    expect(types.contains(FurnitureType.table), isTrue); // desk as table type
    expect(plan.walls.where((s) => s.type == StrokeType.door).length,
        greaterThanOrEqualTo(2));
    // Mesh / french-style opening present
    final opens = plan.walls
        .where((s) =>
            s.type == StrokeType.window ||
            s.type == StrokeType.balcony ||
            s.type == StrokeType.door)
        .length;
    expect(opens, greaterThanOrEqualTo(3));
    // Dense — not sparse 1–2 pieces (be325971 “worse than +36”)
    expect(plan.furniture.where((f) => f.included).length,
        greaterThanOrEqualTo(3));
    final resolved = PhotoTrueLayout.resolveForReview(plan);
    expect(
      resolved.furniture
          .where((f) => f.included && f.type == FurnitureType.wardrobe)
          .isNotEmpty,
      isTrue,
    );
    expect(HomeScanInventory.studyGold.usesStudyGoldLayout, isTrue);
    expect(HomeScanInventory.loungeOffice.usesStudyGoldLayout, isFalse);
  });

  test('+142 resolveForReview must not wall-hug inventory coffee table', () {
    final measure = ArRoomMeasure(
      widthFt: 20.0,
      lengthFt: 9.0,
      widthM: 20.0 / 3.28084,
      lengthM: 9.0 / 3.28084,
      mode: 'auto',
      source: 'user_confirm',
      sampleCount: 50,
      poseCount: 40,
      coverageScore: 0.92,
      orthogonalScore: 0.95,
    );
    final plan = HomeScanPackage.fromMeasure(measure)
        .toPlanWithInventory(HomeScanInventory.loungeOffice);
    expect(PhotoTrueLayout.isStudyLike(plan), isFalse);
    expect(PhotoTrueLayout.hasStudyGoldInventory(plan), isFalse);

    final resolved = PhotoTrueLayout.resolveForReview(plan);
    final furn = resolved.furniture.where((f) => f.included).toList();
    expect(furn.length, 3);
    expect(furn.any((f) => f.type == FurnitureType.wardrobe), isFalse);
    expect(furn.any((f) => f.catalogId == 'bean_bag'), isTrue);

    final table = furn.firstWhere((f) => f.type == FurnitureType.table);
    final minWall = [
      table.posFt.dx,
      table.posFt.dy,
      resolved.roomWidthFt - table.posFt.dx,
      resolved.roomLengthFt - table.posFt.dy,
    ].reduce((a, b) => a < b ? a : b);
    // Must stay mid-room after review (FPM used to pin ≤2 ft from wall)
    expect(minWall, greaterThan(2.2));
    expect(resolved.walls.where((s) => s.type == StrokeType.door).length,
        greaterThanOrEqualTo(2));
  });

  test('+141 inventory: mid-room table, bean bag label, no invented sofa', () {
    // Feedback 04919d14 room shape (~20×9) — FPM used to wall-hug coffee table
    final measure = ArRoomMeasure(
      widthFt: 20.0,
      lengthFt: 9.0,
      widthM: 20.0 / 3.28084,
      lengthM: 9.0 / 3.28084,
      mode: 'auto',
      source: 'user_confirm',
      sampleCount: 50,
      poseCount: 40,
      coverageScore: 0.92,
      orthogonalScore: 0.95,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final plan = pack.toPlanWithInventory(HomeScanInventory.loungeOffice);

    expect(plan.walls.where((s) => s.type == StrokeType.door).length,
        greaterThanOrEqualTo(2));
    expect(plan.walls.where((s) => s.type == StrokeType.window).length,
        greaterThanOrEqualTo(1));

    final furn = plan.furniture.where((f) => f.included).toList();
    expect(furn.length, 3); // desk + table + bean bag only
    expect(furn.any((f) => f.type == FurnitureType.sofa), isFalse);
    expect(furn.any((f) => f.type == FurnitureType.bed), isFalse);

    final table = furn.firstWhere((f) => f.type == FurnitureType.table);
    // Coffee table stays mid-room (not wall-hugged ≤2 ft)
    final minWall = [
      table.posFt.dx,
      table.posFt.dy,
      plan.roomWidthFt - table.posFt.dx,
      plan.roomLengthFt - table.posFt.dy,
    ].reduce((a, b) => a < b ? a : b);
    expect(minWall, greaterThan(2.2));
    expect(table.catalogId, 'coffee_table');

    final bag = furn.firstWhere((f) => f.catalogId == 'bean_bag');
    expect(bag.type, FurnitureType.chair);

    // Clear of door swing
    for (final f in furn) {
      expect(
        PhotoTrueLayout.furnitureBlocksDoorKeepOut(f, plan),
        isFalse,
        reason: '${f.type} must not block door',
      );
    }

    final ed = ScanParser.toEditor(plan, 20);
    expect(ed.furniture.length, 3);
    expect(ed.furniture.any((f) => f.catalogId == 'bean_bag'), isTrue);
    expect(ed.furniture.any((f) => f.catalogId == 'desk'), isTrue);
    expect(ed.furniture.any((f) => f.catalogId == 'coffee_table'), isTrue);
    expect(ed.strokes.where((s) => s.type == StrokeType.door).length,
        greaterThanOrEqualTo(2));
    expect(plan.accuracyScore, greaterThanOrEqualTo(0.95));
  });

  test('+139 pose drift does not invent 30×26 ft home rooms (7f07625b)', () {
    // Small floor (~3.5×3.0 m) but drifted pose trail spanning ~10×8 m
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 3.5,
      lengthM: 3.0,
      samplesPerEdge: 6,
    );
    final flat = <double>[for (final p in cloud) ...p];
    final poses = <double>[];
    for (var i = 0; i < 20; i++) {
      poses.addAll([i * 0.5, 1.5, 0.0]); // 10 m path
    }
    for (var i = 0; i < 16; i++) {
      poses.addAll([10.0, 1.5, i * 0.5]); // +8 m
    }
    final measure = ArRoomMeasure(
      widthFt: 11.5,
      lengthFt: 9.8,
      widthM: 3.5,
      lengthM: 3.0,
      mode: 'auto',
      cornersM: flat,
      posesM: poses,
      sampleCount: cloud.length,
      poseCount: poses.length ~/ 3,
      coverageScore: 0.55,
      orthogonalScore: 0.85,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final size = pack.resolvedSize;
    expect(size.widthFt, lessThanOrEqualTo(HomeScanGeometry.residentialMaxWidthFt));
    expect(size.lengthFt, lessThanOrEqualTo(HomeScanGeometry.residentialMaxLengthFt));
    // Must not balloon to feedback-class 30+ ft
    expect(size.widthFt, lessThan(30.0));
    expect(size.lengthFt, lessThan(26.0));
  });

  test('+146 soft-cap proposeConfirmSize clips 29×16 drift (b5fa46b8)', () {
    final p = HomeScanGeometry.proposeConfirmSize(
      widthFt: 29.3,
      lengthFt: 15.8,
      hasWallLock: false,
    );
    expect(p.clamped, isTrue);
    expect(p.undersized, isFalse);
    expect(p.rawWidthFt, closeTo(29.3, 0.05));
    expect(p.widthFt, lessThanOrEqualTo(HomeScanGeometry.softProposeWidthFt));
    expect(p.lengthFt, lessThanOrEqualTo(HomeScanGeometry.softProposeLengthFt));
    expect(p.widthFt, greaterThanOrEqualTo(p.lengthFt));
  });

  test('+147 under-size 7×5 (c643ffe0) proposes gold study floor', () {
    final p = HomeScanGeometry.proposeConfirmSize(
      widthFt: 7.0,
      lengthFt: 5.1,
      hasWallLock: false,
    );
    expect(p.undersized, isTrue);
    expect(p.clamped, isTrue);
    expect(p.rawWidthFt, closeTo(7.0, 0.05));
    expect(p.rawLengthFt, closeTo(5.1, 0.05));
    expect(p.widthFt, closeTo(HomeScanGeometry.goldStudyWidthFt, 0.05));
    expect(p.lengthFt, closeTo(HomeScanGeometry.goldStudyLengthFt, 0.05));
  });

  test('+146 study gold only when wardrobe — lounge never gets wardrobe wall', () {
    expect(HomeScanInventory.studyGold.usesStudyGoldLayout, isTrue);
    expect(HomeScanInventory.loungeOffice.usesStudyGoldLayout, isFalse);
    // desk+table+doors without wardrobe must NOT force study gold
    const chips = HomeScanInventory(
      doors: 2,
      frenchWindow: true,
      desk: true,
      table: true,
      chair: true,
    );
    expect(chips.usesStudyGoldLayout, isFalse);

    final measure = ArRoomMeasure(
      widthFt: 16,
      lengthFt: 12,
      widthM: 16 / 3.28084,
      lengthM: 12 / 3.28084,
      mode: 'auto',
      source: 'user_confirm',
      coverageScore: 0.9,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final lounge = pack.toPlanWithInventory(HomeScanInventory.loungeOffice);
    expect(
      lounge.furniture.any((f) => f.included && f.type == FurnitureType.wardrobe),
      isFalse,
    );
    final report =
        HomeScanInventoryComposer.matchReport(lounge, HomeScanInventory.loungeOffice);
    expect(report.fullMatch, isTrue);
    expect(report.doors, greaterThanOrEqualTo(2));
    expect(report.furniture, greaterThanOrEqualTo(3));
  });

  test('+146 match checklist requires selection', () {
    expect(const HomeScanInventory().isReadyToPlace, isFalse);
    expect(HomeScanInventory.loungeOffice.isReadyToPlace, isTrue);
    expect(
      HomeScanInventory.loungeOffice.matchChecklistLines(),
      isNotEmpty,
    );
  });

  test('+145 one-wall calibrate scales both axes proportionally', () {
    final scaled = HomeScanGeometry.scaleByKnownWall(
      proposedWidthFt: 20.0,
      proposedLengthFt: 15.0,
      axis: 'width',
      knownWallFt: 18.0,
    );
    expect(scaled, isNotNull);
    expect(scaled!.widthFt, closeTo(18.0, 0.01));
    // 15 * (18/20) = 13.5
    expect(scaled.lengthFt, closeTo(13.5, 0.01));
    expect(scaled.scale, closeTo(0.9, 0.001));

    final short = HomeScanGeometry.scaleByKnownWall(
      proposedWidthFt: 20.0,
      proposedLengthFt: 15.0,
      axis: 'length',
      knownWallFt: 12.0,
    );
    expect(short, isNotNull);
    // scale = 12/15 = 0.8 → width 16, length 12
    expect(short!.lengthFt, closeTo(12.0, 0.01));
    expect(short.widthFt, closeTo(16.0, 0.01));
  });

  test('+145 one-wall rejects absurd tape values', () {
    expect(
      HomeScanGeometry.scaleByKnownWall(
        proposedWidthFt: 16,
        proposedLengthFt: 12,
        axis: 'width',
        knownWallFt: 3,
      ),
      isNull,
    );
    expect(
      HomeScanGeometry.scaleByKnownWall(
        proposedWidthFt: 16,
        proposedLengthFt: 12,
        axis: 'width',
        knownWallFt: 80,
      ),
      isNull,
    );
  });

  test('+145 one_wall_calibrate source locks size like user_confirm', () {
    final cloud = ArPolygonMap.walkCloudRectM(widthM: 4.0, lengthM: 3.0);
    final flat = <double>[for (final p in cloud) ...p];
    final measure = ArRoomMeasure(
      widthFt: 18.0,
      lengthFt: 13.5,
      widthM: 5.49,
      lengthM: 4.11,
      mode: 'auto',
      source: 'one_wall_calibrate',
      cornersM: flat,
      sampleCount: cloud.length,
      poseCount: 20,
      coverageScore: 0.4,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    expect(pack.qualityRejectReason(), isNull);
    final size = pack.resolvedSize;
    expect(size.widthFt, closeTo(18.0, 0.05));
    expect(size.lengthFt, closeTo(13.5, 0.05));
    expect(size.fuseSource, 'userConfirm');
  });

  test('+145 sizeQualityHints coach incomplete cover', () {
    final measure = const ArRoomMeasure(
      widthFt: 14.0,
      lengthFt: 12.0,
      widthM: 4.27,
      lengthM: 3.66,
      mode: 'auto',
      cornersM: [0, 0, 0, 4, 0, 0, 4, 0, 3, 0, 0, 3],
      sampleCount: 8,
      poseCount: 8,
      coverageScore: 0.40,
      orthogonalScore: 0.7,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final hints = pack.sizeQualityHints();
    expect(hints, isNotEmpty);
    expect(
      hints.any((h) =>
          h.toLowerCase().contains('cover') ||
          h.toLowerCase().contains('walk') ||
          h.toLowerCase().contains('tape') ||
          h.toLowerCase().contains('incomplete')),
      isTrue,
    );
  });

  test('+145 coverage-first rejects very weak cover without wall lock', () {
    final measure = const ArRoomMeasure(
      widthFt: 16.0,
      lengthFt: 12.0,
      widthM: 4.88,
      lengthM: 3.66,
      mode: 'auto',
      cornersM: [0, 0, 0, 3, 0, 0, 3, 0, 2.5, 0, 0, 2.5],
      sampleCount: 6,
      poseCount: 6,
      coverageScore: 0.35,
      orthogonalScore: 0.6,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final reason = pack.qualityRejectReason();
    expect(reason, isNotNull);
  });

  test('+138 user_confirm size is absolute (no re-fuse overwrite)', () {
    // Tiny cloud that would fuse small — user taped 18×14
    final cloud = ArPolygonMap.walkCloudRectM(
      widthM: 2.5,
      lengthM: 2.2,
      samplesPerEdge: 4,
    );
    final flat = <double>[for (final p in cloud) ...p];
    final measure = ArRoomMeasure(
      widthFt: 18.0,
      lengthFt: 14.0,
      widthM: 18.0 / 3.28084,
      lengthM: 14.0 / 3.28084,
      mode: 'auto',
      source: 'user_confirm',
      cornersM: flat,
      posesM: const [0, 1.5, 0, 1, 1.5, 1, 2, 1.5, 2],
      sampleCount: cloud.length,
      poseCount: 3,
      coverageScore: 0.3,
    );
    final pack = HomeScanPackage.fromMeasure(measure);
    final size = pack.resolvedSize;
    expect(size.fuseSource, 'userConfirm');
    expect(size.widthFt, closeTo(18.0, 0.05));
    expect(size.lengthFt, closeTo(14.0, 0.05));
    final plan = pack.toPlanWithAiFurniture();
    expect(plan.roomWidthFt, closeTo(18.0, 0.05));
    expect(plan.roomLengthFt, closeTo(14.0, 0.05));
    expect(plan.furniture.where((f) => f.included).length, greaterThanOrEqualTo(4));
    final ed = ScanParser.toEditor(plan, 20);
    expect(ed.strokes.where((s) => s.type == StrokeType.wall).length, 4);
    expect(ed.width, closeTo(18.0, 0.05));
  });
}
