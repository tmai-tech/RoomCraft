import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import '../models/room_model.dart';
import '../models/scan_result.dart';
import '../services/ar_measure_service.dart';
import '../models/stroke_model.dart';
import 'accurate_scan.dart';
import 'ar_polygon_map.dart';
import 'furniture_position_map.dart';
import 'home_scan_inventory.dart';
import 'layout/ai_designer.dart';
import 'layout/auto_arrange.dart';
import 'opening_chain_fidelity.dart';
import 'photo_true_layout.dart';
import 'plan_accuracy_metrics.dart';

/// Home Scan (Planner 5D / magicplan class) — walk + AR → metric plan (+127/+128).
///
/// Capture happens natively (poses + floor hits while walking). This module:
/// 1) re-fits room size from **floor hits + pose trail** (+128 fuse)
/// 2) composes a metric [ScanResult] with assist openings for Review
/// 3) serializes a package for training / future cloud reconstruction
///
/// Furniture is not invented — user places from catalog / AR Place / photos.
/// Placeholder door+window keep the plan from looking like a bare rectangle
/// (feedback e7b247fd “just asks floor plan”).
class HomeScanPackage {
  final String id;
  final DateTime createdAt;
  final ArRoomMeasure measure;
  /// Floor hit samples world XYZ meters (from walk cloud).
  final List<List<double>> floorHitsM;
  /// Camera pose samples world XYZ meters (motion trail).
  final List<List<double>> posesM;
  final String appVersion;

  const HomeScanPackage({
    required this.id,
    required this.createdAt,
    required this.measure,
    this.floorHitsM = const [],
    this.posesM = const [],
    this.appVersion = '',
  });

  int get sampleCount => floorHitsM.length;
  int get poseCount => posesM.length;

  /// +134/+136/+145 quality gate — reject incomplete walks (fake 10×10, feedback 225fb5de).
  ///
  /// Returns null when OK, else a user-facing error string.
  /// +138: never reject after user_confirm / tape / one-wall calibrate (truth).
  String? qualityRejectReason() {
    if (measure.source == 'user_confirm' ||
        measure.source == 'confirmed' ||
        measure.source == 'tape' ||
        measure.source == 'one_wall_calibrate') {
      return null;
    }
    final size = resolvedSize;
    final w = size.widthFt;
    final l = size.lengthFt;
    final area = w * l;
    final squareish =
        w > 0 && ((w - l).abs() / math.max(w, l)) < 0.12;
    final weakSamples = sampleCount < 20 && poseCount < 24;
    // +145: coverage-first — incomplete angular cover is a reject, not a soft warn
    final weakCover = size.coverage > 0 && size.coverage < 0.55;
    final weakAgree = size.agreement > 0 && size.agreement < 0.50;
    final pathM = HomeScanGeometry.posePathLengthM(posesM);
    // Expected full-loop path ≈ perimeter at 0.75 m standoff (m)
    final periM = 2 * (w + l) / 3.28084;
    final shortPath = pathM > 0 && periM > 4 && pathM < periM * 0.40;

    if (w < 9 || l < 8) {
      return 'Room size looks too small (${w.toStringAsFixed(0)}×${l.toStringAsFixed(0)} ft). '
          'Walk a full loop near all walls, then Done.';
    }
    // Classic half-walk: ~10×10 square with sparse map
    if (area < 130 && squareish && (weakSamples || weakCover || weakAgree)) {
      return 'Map looks incomplete (${w.toStringAsFixed(0)}×${l.toStringAsFixed(0)} ft, '
          '${sampleCount} pts). Walk all four walls slowly, then Done.';
    }
    // +136/+145: square-ish mid room without wall lock + short walk path
    if (area < 150 &&
        squareish &&
        !measure.hasWallLock &&
        (weakCover || shortPath || size.coverage < 0.65)) {
      return 'Map incomplete (${w.toStringAsFixed(0)}×${l.toStringAsFixed(0)} ft). '
          'Walk all walls looking at them, then Done.';
    }
    if (weakSamples && area < 150) {
      return 'Not enough map points ($sampleCount). '
          'Walk slowly around the whole room, then Done.';
    }
    if (shortPath && !measure.hasWallLock && size.coverage < 0.70) {
      return 'Walk path too short for this room. '
          'Complete a full loop near the walls, then Done.';
    }
    // +145: low cover alone (even non-square) without wall lock
    if (weakCover && !measure.hasWallLock && size.coverage > 0 && size.coverage < 0.50) {
      return 'Wall coverage only ${(size.coverage * 100).round()}% — walk remaining sides, '
          'or measure one wall with a tape on the next screen.';
    }
    // +139: absurd home size without wall lock (tracking drift / over-standoff)
    if (!measure.hasWallLock &&
        (w > HomeScanGeometry.residentialMaxWidthFt + 0.5 ||
            l > HomeScanGeometry.residentialMaxLengthFt + 0.5)) {
      return 'Size looks too large (${w.toStringAsFixed(0)}×${l.toStringAsFixed(0)} ft). '
          'Re-walk slowly near walls, or measure one wall with a tape after Done.';
    }
    return null;
  }

  /// Soft warnings for the confirm-size screen (+145). Never blocks; coaches tape.
  List<String> sizeQualityHints() {
    if (measure.source == 'user_confirm' ||
        measure.source == 'confirmed' ||
        measure.source == 'tape' ||
        measure.source == 'one_wall_calibrate') {
      return const [];
    }
    final size = resolvedSize;
    final w = size.widthFt;
    final l = size.lengthFt;
    final hints = <String>[];
    final reject = qualityRejectReason();
    if (reject != null) {
      hints.add(reject);
    }
    if (size.coverage > 0 && size.coverage < 0.75) {
      hints.add(
        'Wall cover ${(size.coverage * 100).round()}% — for better size, re-scan all walls '
        'or use “I measured one wall” below.',
      );
    }
    if (size.agreement > 0 && size.agreement < 0.55) {
      hints.add(
        'Floor map and walk path disagree — measure one wall with a tape to lock scale.',
      );
    }
    if (!measure.hasWallLock && (w > 24 || l > 24)) {
      hints.add(
        'Size looks large for one room (${w.toStringAsFixed(0)}×${l.toStringAsFixed(0)} ft). '
        'Double-check with a tape on the longer wall.',
      );
    }
    if (measure.consistencyError > 0.12) {
      hints.add(
        'AR edges are inconsistent — one-wall tape calibrate is recommended.',
      );
    }
    // De-dupe while preserving order
    final seen = <String>{};
    return [
      for (final h in hints)
        if (seen.add(h)) h,
    ];
  }

  /// Prefer fused walk re-fit (+128/+130/+135 wall lock); else floor; else native.
  ///
  /// +138: when measure.source is user-confirmed (`user_confirm` / `confirmed`),
  /// trust width/length feet absolutely — never re-fuse over the user's size.
  ({
    double widthFt,
    double lengthFt,
    double coverage,
    double ortho,
    String fuseSource,
    double agreement,
  }) get resolvedSize {
    const mToFt = 3.28084;
    final userLocked = measure.source == 'user_confirm' ||
        measure.source == 'confirmed' ||
        measure.source == 'tape' ||
        measure.source == 'one_wall_calibrate';
    if (userLocked && measure.widthFt >= 6 && measure.lengthFt >= 6) {
      final w = measure.widthFt >= measure.lengthFt
          ? measure.widthFt
          : measure.lengthFt;
      final l = measure.widthFt >= measure.lengthFt
          ? measure.lengthFt
          : measure.widthFt;
      return (
        widthFt: w,
        lengthFt: l,
        coverage: math.max(measure.coverageScore, 0.95),
        ortho: math.max(measure.orthogonalScore, 0.95),
        fuseSource: 'userConfirm',
        agreement: 1.0,
      );
    }

    final fused = ArPolygonMap.resolveWalkFeet(
      floorHits: floorHitsM,
      poses: posesM,
    );
    var w = 0.0;
    var l = 0.0;
    var cov = 0.0;
    var ortho = 0.0;
    var src = 'native';
    var agree = 0.7;

    if (fused != null && fused.widthFt >= 3 && fused.lengthFt >= 3) {
      w = fused.widthFt;
      l = fused.lengthFt;
      cov = fused.coverageScore;
      ortho = fused.orthogonalScore;
      src = fused.fuseSource;
      agree = fused.agreement;
      // +130 soft-max with native measure
      final nw = measure.widthFt;
      final nl = measure.lengthFt;
      if (nw >= 3 && nl >= 3 && fused.agreement >= 0.55) {
        final nW = nw >= nl ? nw : nl;
        final nL = nw >= nl ? nl : nw;
        if (nW > w && nW / w <= 1.18) w = w * 0.55 + nW * 0.45;
        if (nL > l && nL / l <= 1.18) l = l * 0.55 + nL * 0.45;
      }
    } else if (floorHitsM.length >= 4) {
      final fit = ArPolygonMap.resolveFeet(floorHitsM);
      if (fit != null && fit.widthFt >= 3 && fit.lengthFt >= 3) {
        w = fit.widthFt;
        l = fit.lengthFt;
        cov = fit.coverageScore;
        ortho = fit.orthogonalScore;
        src = 'floor';
        agree = 0.85;
      }
    }
    if (w < 3 || l < 3) {
      w = measure.widthFt;
      l = measure.lengthFt;
      cov = measure.coverageScore;
      ortho = measure.orthogonalScore;
      src = 'native';
      agree = 0.7;
    }

    // +135: opposite vertical plane wall-to-wall lock (highest metric trust)
    if (measure.hasWallLock) {
      final ww = measure.wallLockWidthM * mToFt;
      final ll = measure.wallLockLengthM * mToFt;
      final lockW = ww >= ll ? ww : ll;
      final lockL = ww >= ll ? ll : ww;
      if (lockW >= 5 && lockL >= 4) {
        final aW = w > 0 ? (lockW - w).abs() / lockW : 1.0;
        final aL = l > 0 ? (lockL - l).abs() / lockL : 1.0;
        final strongUnder = lockW > w * 1.20 || lockL > l * 1.20;
        if (measure.wallLockPairs >= 2 && (aW < 0.22 && aL < 0.22 || strongUnder)) {
          // Agree OR clear under-size → trust wall-to-wall pairs
          w = lockW;
          l = lockL;
          src = 'wallLock';
          agree = math.max(agree, strongUnder ? 0.85 : 0.92);
          ortho = math.max(ortho, 0.96);
          cov = math.max(cov, 0.88);
        } else {
          // Soft expand toward wall lock (under-size fix)
          if (lockW > w) {
            w = strongUnder ? w * 0.25 + lockW * 0.75 : w * 0.4 + lockW * 0.6;
          }
          if (lockL > l) {
            l = strongUnder ? l * 0.25 + lockL * 0.75 : l * 0.4 + lockL * 0.6;
          }
          src = '$src+wallLock';
          agree = math.max(agree, 0.8);
        }
      }
    }

    // +136: long walk path but tiny map → under-size; expand toward path envelope
    final pathM = HomeScanGeometry.posePathLengthM(posesM);
    if (pathM >= 6.0 && w >= 3 && l >= 3) {
      final wM = w / mToFt;
      final lM = l / mToFt;
      final periM = 2 * (wM + lM);
      // Full-loop walks are typically ≥55% of perimeter at ~0.75 m standoff
      if (pathM >= periM * 0.55 && periM > 0) {
        // Path proves room is large enough; mild expand if cloud still tight
        final scale = (pathM / (periM * 0.70)).clamp(1.0, 1.18);
        if (scale > 1.02 && !src.contains('wallLock')) {
          w *= scale;
          l *= scale;
          src = '$src+pathExpand';
          agree = math.max(agree, 0.72);
        }
      } else if (pathM > 10 && (w * l) < 140 && !measure.hasWallLock) {
        // Long walk, small area — expand ~12% (half-room map class)
        w *= 1.12;
        l *= 1.12;
        src = '$src+pathExpand';
      }
    }

    // +137/+139: pose AABB soft floor — expand incomplete floor, not AR drift.
    // Feedback 7f07625b: 30.6×25.6 ft on a normal living room from hard envelope.
    final aabb = HomeScanGeometry.poseAabbMeters(posesM);
    if (aabb != null && w >= 3 && l >= 3 && !src.contains('wallLock')) {
      const stand = 0.55;
      final envWM = math.min(aabb.widthM + 2 * stand, 8.6);
      final envLM = math.min(aabb.lengthM + 2 * stand, 8.0);
      final envW = math.max(envWM, envLM) * mToFt;
      final envL = math.min(envWM, envLM) * mToFt;
      final ratioW = w > 0 ? envW / w : 1.0;
      final ratioL = l > 0 ? envL / l : 1.0;
      // Modest under-size: trust pose envelope (partial floor mesh)
      if (envW > w * 1.06 && ratioW <= 1.55) {
        w = math.max(w, math.min(envW * 0.95, HomeScanGeometry.residentialMaxWidthFt));
        src = '$src+poseAabb';
        agree = math.max(agree, 0.74);
      } else if (envW > w * 1.55) {
        // Pose >> floor → tracking drift; mild expand only
        w = math.max(w, math.min(w * 1.18, envW * 0.65));
        src = '$src+poseAabbSoft';
      }
      if (envL > l * 1.06 && ratioL <= 1.55) {
        l = math.max(l, math.min(envL * 0.95, HomeScanGeometry.residentialMaxLengthFt));
        if (!src.contains('poseAabb')) src = '$src+poseAabb';
        agree = math.max(agree, 0.74);
      } else if (envL > l * 1.55) {
        l = math.max(l, math.min(l * 1.18, envL * 0.65));
        if (!src.contains('poseAabb')) src = '$src+poseAabbSoft';
      }
    }

    // +139: soft residential clamp for proposed (non user-locked) sizes
    if (!measure.hasWallLock) {
      w = math.min(w, HomeScanGeometry.residentialMaxWidthFt);
      l = math.min(l, HomeScanGeometry.residentialMaxLengthFt);
    } else {
      w = math.min(w, 49.0);
      l = math.min(l, 40.0);
    }

    return (
      widthFt: w >= l ? w : l,
      lengthFt: w >= l ? l : w,
      coverage: cov,
      ortho: ortho,
      fuseSource: src,
      agreement: agree,
    );
  }

  /// Metric plan — Home Scan stage 1 output (+128 fuse + assist openings).
  ScanResult toPlan() {
    final size = resolvedSize;
    final w = size.widthFt;
    final l = size.lengthFt;
    final cov = size.coverage;
    final ortho = size.ortho;
    final oppErr = measure.consistencyError;
    final score = ScaleLockConfidence.blend(
      layoutScore: 1.0,
      source: ScaleSource.arPolygon,
      oppositeWallError: oppErr,
    );
    final agreeNote = size.agreement > 0
        ? ' · agree ${(size.agreement * 100).round()}%'
        : '';
    return AccurateScan.enforce(
      widthFt: w,
      lengthFt: l,
      openings: const [],
      furniture: const [],
      // Assist openings so Review is not a bare box (user edits/deletes).
      inventDefaultOpenings: true,
      sourceLabel: 'Home Scan (AR walk → metric plan)',
      accuracyScore: score,
      warnings: [
        'Home Scan (+139): floor + pose envelope + wall-lock + path expand'
            '${measure.depthEnabled ? ' + depth' : ''}'
            '${size.fuseSource == 'userConfirm' ? ' · user size lock' : ''} → room size',
        'Room ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft'
            ' · samples $sampleCount · poses $poseCount'
            '${ortho > 0 ? ' · fit ${(ortho * 100).round()}%' : ''}'
            '${cov > 0 ? ' · wall cover ${(cov * 100).round()}%' : ''}'
            '$agreeNote · ${size.fuseSource}'
            '${measure.depthEnabled ? ' · depth' : ''}'
            '${measure.hasWallLock ? ' · walls×${measure.wallLockPairs}' : ''}',
        'Scale lock: ${ScaleLockConfidence.sourceLabel(ScaleSource.arPolygon)}',
        if (cov > 0 && cov < 0.75)
          'Incomplete walk loop — re-scan walking all four walls for better size',
        if (size.agreement > 0 && size.agreement < 0.55)
          'Floor vs walk path disagree — walk closer to walls for better size',
        if (sampleCount < 12 && poseCount < 16)
          'Few samples — walk slower; aim at floor near walls (Planner5D tip)',
        if (size.fuseSource.contains('wallLock'))
          'Wall-distance lock applied (opposite vertical planes)',
        if (size.fuseSource.contains('pathExpand'))
          'Size expanded from walk path length (under-size guard)',
        if (size.fuseSource.contains('poseFloor') ||
            size.fuseSource.contains('poseAabb'))
          'Size floored by walk path envelope (under-size guard)',
        'Placeholder door/window — edit or delete in blueprint',
        if (score >= 0.99) '100% AR walk measured room geometry (metric size)',
      ],
    );
  }

  /// Metric room + inventory openings/furniture (+140).
  ///
  /// Walk locks **size**; contents come from [HomeScanInventory] (user report),
  /// not random AI living-room fill (feedback 04919d14).
  ScanResult toPlanWithInventory(
    HomeScanInventory inventory, {
    double pixelsPerFoot = 20,
  }) {
    final size = resolvedSize;
    final plan = HomeScanInventoryComposer.compose(
      widthFt: size.widthFt,
      lengthFt: size.lengthFt,
      inventory: inventory,
      accuracyScore: math.max(size.coverage, 0.88),
    );
    // Merge size diagnostics into warnings
    return plan.copyWith(
      warnings: [
        ...toPlan().warnings.where((w) =>
            !w.contains('Placeholder door') &&
            !w.contains('Placeholder door/window')),
        ...plan.warnings,
      ],
    );
  }

  /// Metric room + on-device AI starter furniture (+128–+137).
  ///
  /// Prefer [toPlanWithInventory] after Home Scan (feedback 04919d14).
  /// Kept for legacy / tests when inventory is not available.
  ScanResult toPlanWithAiFurniture({
    DesignStyle? style,
    double pixelsPerFoot = 20,
    HomeScanInventory? inventory,
  }) {
    // +140: inventory path when UI provides contents (feedback 04919d14)
    if (inventory != null &&
        (inventory.hasAnyFurniture || inventory.hasAnyOpenings)) {
      return toPlanWithInventory(inventory, pixelsPerFoot: pixelsPerFoot);
    }
    final base = toPlan();
    final room = RoomModel(
      id: id,
      name: 'Home Scan',
      widthInFeet: base.roomWidthFt,
      lengthInFeet: base.roomLengthFt,
    );
    final area = base.roomWidthFt * base.roomLengthFt;
    final minPieces = area >= 180
        ? 6
        : area >= 120
            ? 5
            : 4;
    // Prefer wall-anchored living/office when no style given
    var picked = style ??
        (area >= 120
            ? DesignStyle.family
            : area >= 90
                ? DesignStyle.cozy
                : DesignStyle.homeOffice);
    var items = AiDesigner.furnish(
      room: room,
      pixelsPerFoot: pixelsPerFoot,
      style: picked,
      arrangeStyle: ArrangeStyle.wallHug,
    );
    if (items.length < minPieces) {
      for (final retry in [
        DesignStyle.family,
        DesignStyle.cozy,
        DesignStyle.studio,
      ]) {
        if (retry == picked) continue;
        final next = AiDesigner.furnish(
          room: room,
          pixelsPerFoot: pixelsPerFoot,
          style: retry,
          arrangeStyle: ArrangeStyle.wallHug,
        );
        if (next.length > items.length) {
          items = next;
          picked = retry;
        }
        if (items.length >= minPieces) break;
      }
    }
    final furniture = <ScanFurnitureHint>[
      for (final f in items)
        ScanFurnitureHint(
          type: f.type,
          posFt: Offset(
            f.position.dx / pixelsPerFoot,
            f.position.dy / pixelsPerFoot,
          ),
          widthFt: f.widthInFeet,
          lengthFt: f.lengthInFeet,
          rotationRad: f.rotationAngle,
          included: true,
        ),
    ];
    var plan = base.copyWith(
      furniture: furniture,
      warnings: [
        ...base.warnings.where((w) => !w.contains('Placeholder door')),
        'AI starter furniture (${picked.label}) — edit freely; not from photos',
        'Walk map locked size; closed walls + wall-hug pieces (+140)',
      ],
    );
    plan = OpeningChainFidelity.ensure(plan);
    plan = FurniturePositionMap.ensure(plan);
    plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
    if (plan.walls.where((s) => s.type == StrokeType.wall).length < 4) {
      plan = AccurateScan.enforce(
        widthFt: plan.roomWidthFt,
        lengthFt: plan.roomLengthFt,
        openings: plan.walls.where((s) => s.type != StrokeType.wall).toList(),
        furniture: plan.furniture,
        warnings: plan.warnings,
        inventDefaultOpenings: plan.walls
            .where((s) =>
                s.type == StrokeType.door || s.type == StrokeType.window)
            .isEmpty,
        accuracyScore: plan.accuracyScore,
        sourceLabel: plan.warnings.isNotEmpty ? plan.warnings.first : null,
      );
    }
    return plan;
  }

  Map<String, dynamic> toJson() {
    final size = resolvedSize;
    return {
      'schema': 'roomcraft_home_scan_v1',
      'id': id,
      'created_at': createdAt.toUtc().toIso8601String(),
      'app_version': appVersion,
      'measure': {
        'width_ft': measure.widthFt,
        'length_ft': measure.lengthFt,
        'width_m': measure.widthM,
        'length_m': measure.lengthM,
        'mode': measure.mode,
        'orthogonal_score': measure.orthogonalScore,
        'diagonal_error': measure.diagonalError,
        'coverage_score': measure.coverageScore,
        'source': measure.source,
      },
      'resolved': {
        'width_ft': size.widthFt,
        'length_ft': size.lengthFt,
        'coverage': size.coverage,
        'ortho': size.ortho,
        'fuse_source': size.fuseSource,
        'agreement': size.agreement,
      },
      'floor_hits_m': floorHitsM,
      'poses_m': posesM,
      'sample_count': sampleCount,
      'pose_count': poseCount,
    };
  }

  String toJsonString({bool pretty = true}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson()) : jsonEncode(toJson());

  /// Open3D / CloudCompare friendly XYZ (meters). One point per line: `x y z`.
  ///
  /// Offline: `o3d.io.read_point_cloud("scan.xyz", format='xyz')` then plane RANSAC.
  String toOpen3dXyz({bool includePoses = false}) {
    final buf = StringBuffer();
    for (final p in floorHitsM) {
      if (p.length < 3) continue;
      buf.writeln('${p[0]} ${p[1]} ${p[2]}');
    }
    if (includePoses) {
      for (final p in posesM) {
        if (p.length < 3) continue;
        buf.writeln('${p[0]} ${p[1]} ${p[2]}');
      }
    }
    return buf.toString();
  }

  /// Minimal PLY (ASCII vertex-only) for MeshLab / Open3D.
  String toOpen3dPly({bool includePoses = false}) {
    final pts = <List<double>>[
      ...floorHitsM.where((p) => p.length >= 3),
      if (includePoses) ...posesM.where((p) => p.length >= 3),
    ];
    final buf = StringBuffer()
      ..writeln('ply')
      ..writeln('format ascii 1.0')
      ..writeln('element vertex ${pts.length}')
      ..writeln('property float x')
      ..writeln('property float y')
      ..writeln('property float z')
      ..writeln('end_header');
    for (final p in pts) {
      buf.writeln('${p[0]} ${p[1]} ${p[2]}');
    }
    return buf.toString();
  }

  factory HomeScanPackage.fromMeasure(
    ArRoomMeasure m, {
    String? id,
    String appVersion = '',
    List<List<double>>? floorHitsM,
    List<List<double>>? posesM,
  }) {
    final hits = floorHitsM ?? _chunk3(m.cornersM);
    final poses = posesM ?? _chunk3(m.posesM);
    return HomeScanPackage(
      id: id ?? 'hs_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now().toUtc(),
      measure: m,
      floorHitsM: hits,
      posesM: poses,
      appVersion: appVersion,
    );
  }

  static List<List<double>> _chunk3(List<double> flat) {
    final out = <List<double>>[];
    for (var i = 0; i + 2 < flat.length; i += 3) {
      out.add([flat[i], flat[i + 1], flat[i + 2]]);
    }
    return out;
  }
}

/// Helpers for Home Scan package geometry checks (tests / diagnostics).
class HomeScanGeometry {
  HomeScanGeometry._();

  /// Soft max for a single home room without wall-lock proof (feet).
  /// Feedback 7f07625b: 30×26 ft proposals from pose drift.
  static const double residentialMaxWidthFt = 28.0;
  static const double residentialMaxLengthFt = 26.0;

  /// +146: AR **confirm fill** soft cap (feedback b5fa46b8 29.3×15.8 without tape).
  /// Prefer under-size + tape one wall over silent 30 ft living rooms.
  static const double softProposeWidthFt = 24.0;
  static const double softProposeLengthFt = 20.0;

  /// Hard create-plan block without one-wall / tape when above this.
  static const double hardConfirmWidthFt = 26.0;
  static const double hardConfirmLengthFt = 22.0;

  /// Gold study tape size (32ffdc65) — one-tap restore when AR drifts large.
  static const double goldStudyWidthFt = 20.3;
  static const double goldStudyLengthFt = 17.0;

  /// Soft-cap AR resolved size for the confirm form (+146).
  ///
  /// Returns clamped W×L (width ≥ length) and whether we reduced a drifty proposal.
  static ({
    double widthFt,
    double lengthFt,
    bool clamped,
    double rawWidthFt,
    double rawLengthFt,
  }) proposeConfirmSize({
    required double widthFt,
    required double lengthFt,
    bool hasWallLock = false,
  }) {
    var w = widthFt;
    var l = lengthFt;
    if (w < l) {
      final t = w;
      w = l;
      l = t;
    }
    final rawW = w;
    final rawL = l;
    final maxW = hasWallLock ? 26.0 : softProposeWidthFt;
    final maxL = hasWallLock ? 22.0 : softProposeLengthFt;
    var clamped = false;
    if (w > maxW) {
      w = maxW;
      clamped = true;
    }
    if (l > maxL) {
      l = maxL;
      clamped = true;
    }
    // Keep aspect if only one side clipped hard
    if (clamped && rawW > 3 && rawL > 3) {
      final aspect = rawL / rawW;
      if (w == maxW && l > w * aspect * 1.05) {
        l = (w * aspect).clamp(6.0, maxL);
      }
    }
    return (
      widthFt: w,
      lengthFt: l,
      clamped: clamped,
      rawWidthFt: rawW,
      rawLengthFt: rawL,
    );
  }

  /// +145 magicplan-class: scale both axes from one known wall length (tape).
  ///
  /// [axis] `width` or `length` — which side the user measured.
  /// Keeps AR aspect ratio; clamps residential range unless [allowLarge].
  static ({
    double widthFt,
    double lengthFt,
    double scale,
  })? scaleByKnownWall({
    required double proposedWidthFt,
    required double proposedLengthFt,
    required String axis,
    required double knownWallFt,
    bool allowLarge = false,
  }) {
    if (knownWallFt < 6 || knownWallFt > 60) return null;
    var w = proposedWidthFt;
    var l = proposedLengthFt;
    if (w < 3 || l < 3) return null;
    // Normalize long side as width (matches resolvedSize convention)
    if (w < l) {
      final t = w;
      w = l;
      l = t;
    }
    final scaleAxis = axis.toLowerCase();
    final double scale;
    if (scaleAxis == 'length' || scaleAxis == 'short' || scaleAxis == 'l') {
      scale = knownWallFt / l;
      l = knownWallFt;
      w = w * scale;
    } else {
      // default: measured the long / width side
      scale = knownWallFt / w;
      w = knownWallFt;
      l = l * scale;
    }
    if (w < 6 || l < 6) return null;
    if (!allowLarge) {
      w = math.min(w, 49.0);
      l = math.min(l, 40.0);
    }
    // Re-normalize width ≥ length
    if (w < l) {
      return (widthFt: l, lengthFt: w, scale: scale);
    }
    return (widthFt: w, lengthFt: l, scale: scale);
  }

  /// Approximate path length of pose trail in meters.
  static double posePathLengthM(List<List<double>> poses) {
    if (poses.length < 2) return 0;
    var sum = 0.0;
    for (var i = 1; i < poses.length; i++) {
      final a = poses[i - 1];
      final b = poses[i];
      final dx = b[0] - a[0];
      final dy = (a.length > 1 && b.length > 1) ? b[1] - a[1] : 0.0;
      final dz = (a.length > 2 && b.length > 2) ? b[2] - a[2] : 0.0;
      sum += math.sqrt(dx * dx + dy * dy + dz * dz);
    }
    return sum;
  }

  /// Axis-aligned XZ envelope of pose trail (meters). Null if too few poses.
  static ({double widthM, double lengthM})? poseAabbMeters(
    List<List<double>> poses,
  ) {
    if (poses.length < 6) return null;
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minZ = double.infinity;
    var maxZ = -double.infinity;
    var n = 0;
    for (final p in poses) {
      if (p.length < 3) continue;
      final x = p[0];
      final z = p[2];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
      n++;
    }
    if (n < 6) return null;
    final spanX = maxX - minX;
    final spanZ = maxZ - minZ;
    if (spanX < 0.4 && spanZ < 0.4) return null;
    return (
      widthM: math.max(spanX, spanZ),
      lengthM: math.min(spanX, spanZ),
    );
  }
}
