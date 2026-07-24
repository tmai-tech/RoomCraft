import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import '../models/room_model.dart';
import '../models/scan_result.dart';
import '../services/ar_measure_service.dart';
import 'accurate_scan.dart';
import 'ar_polygon_map.dart';
import 'furniture_position_map.dart';
import 'layout/ai_designer.dart';
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

  /// +134 quality gate — reject incomplete walks that produce fake 10×10 plans
  /// (feedback 225fb5de).
  ///
  /// Returns null when OK, else a user-facing error string.
  String? qualityRejectReason() {
    final size = resolvedSize;
    final w = size.widthFt;
    final l = size.lengthFt;
    final area = w * l;
    final squareish =
        w > 0 && ((w - l).abs() / math.max(w, l)) < 0.12;
    final weakSamples = sampleCount < 20 && poseCount < 24;
    final weakCover = size.coverage > 0 && size.coverage < 0.50;
    final weakAgree = size.agreement > 0 && size.agreement < 0.50;

    if (w < 9 || l < 8) {
      return 'Room size looks too small (${w.toStringAsFixed(0)}×${l.toStringAsFixed(0)} ft). '
          'Walk a full loop near all walls, then Done.';
    }
    // Classic half-walk: ~10×10 square with sparse map
    if (area < 130 && squareish && (weakSamples || weakCover || weakAgree)) {
      return 'Map looks incomplete (${w.toStringAsFixed(0)}×${l.toStringAsFixed(0)} ft, '
          '${sampleCount} pts). Walk all four walls slowly, then Done.';
    }
    if (weakSamples && area < 150) {
      return 'Not enough map points ($sampleCount). '
          'Walk slowly around the whole room, then Done.';
    }
    return null;
  }

  /// Prefer fused walk re-fit (+128/+130/+135 wall lock); else floor; else native.
  ({
    double widthFt,
    double lengthFt,
    double coverage,
    double ortho,
    String fuseSource,
    double agreement,
  }) get resolvedSize {
    const mToFt = 3.28084;
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
      if (lockW >= 6 && lockL >= 5) {
        final aW = w > 0 ? (lockW - w).abs() / lockW : 1.0;
        final aL = l > 0 ? (lockL - l).abs() / lockL : 1.0;
        if (measure.wallLockPairs >= 2 && aW < 0.22 && aL < 0.22) {
          w = lockW;
          l = lockL;
          src = 'wallLock';
          agree = math.max(agree, 0.92);
          ortho = math.max(ortho, 0.96);
          cov = math.max(cov, 0.88);
        } else {
          // Soft expand toward wall lock (under-size fix)
          if (lockW > w) w = w * 0.4 + lockW * 0.6;
          if (lockL > l) l = l * 0.4 + lockL * 0.6;
          src = '$src+wallLock';
          agree = math.max(agree, 0.8);
        }
      }
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
        'Home Scan (+135): floor + pose + wall-distance lock'
            '${measure.depthEnabled ? ' + depth' : ''}'
            '${measure.hasWallLock ? ' + wall-lock' : ''} → room size',
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
        'Placeholder door/window — edit or delete in Review',
        if (score >= 0.99) '100% AR walk measured room geometry (metric size)',
      ],
    );
  }

  /// Metric room + on-device AI starter furniture (+128/+130/+133).
  ///
  /// Walk locks **size**; furniture is a catalog layout seed (not photo-true).
  /// +133: denser default style (not sparse modern-minimal on 10×10).
  ScanResult toPlanWithAiFurniture({
    DesignStyle? style,
    double pixelsPerFoot = 20,
  }) {
    final base = toPlan();
    final room = RoomModel(
      id: id,
      name: 'Home Scan',
      widthInFeet: base.roomWidthFt,
      lengthInFeet: base.roomLengthFt,
    );
    // +133/+134: denser living/family fill so plan is not empty-looking after scan
    final area = base.roomWidthFt * base.roomLengthFt;
    var picked = style ??
        (area >= 160
            ? DesignStyle.family
            : area >= 110
                ? DesignStyle.cozy
                : DesignStyle.homeOffice);
    var items = AiDesigner.furnish(
      room: room,
      pixelsPerFoot: pixelsPerFoot,
      style: picked,
    );
    // +134: if layout is still sparse, force denser family recipe
    if (items.length < 4 && style == null) {
      picked = DesignStyle.family;
      items = AiDesigner.furnish(
        room: room,
        pixelsPerFoot: pixelsPerFoot,
        style: picked,
      );
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
        'Walk map locked size; closed walls + wall-anchored pieces (+135)',
      ],
    );
    // +130/+134/+135 accuracy: openings chain + wall positions + door clearances
    plan = OpeningChainFidelity.ensure(plan);
    plan = FurniturePositionMap.ensure(plan);
    plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
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
}
