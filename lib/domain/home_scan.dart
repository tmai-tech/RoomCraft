import 'dart:convert';
import 'dart:math' as math;

import '../models/scan_result.dart';
import '../services/ar_measure_service.dart';
import 'accurate_scan.dart';
import 'ar_polygon_map.dart';
import 'plan_accuracy_metrics.dart';

/// Home Scan (Planner 5D / magicplan class) — walk + AR → metric plan (+127).
///
/// Capture happens natively (poses + floor hits while walking). This module:
/// 1) re-fits room size from the walk cloud when possible
/// 2) composes an empty metric [ScanResult] for Review
/// 3) serializes a package for training / future cloud reconstruction
///
/// Furniture/openings are **not** invented here — user adds in Review/editor
/// or optional photos after scale is locked.
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

  /// Prefer re-fit from cloud if we have enough hits; else trust measure.
  ({double widthFt, double lengthFt, double coverage, double ortho}) get resolvedSize {
    if (floorHitsM.length >= 4) {
      final fit = ArPolygonMap.resolveFeet(floorHitsM);
      if (fit != null && fit.widthFt >= 3 && fit.lengthFt >= 3) {
        return (
          widthFt: fit.widthFt,
          lengthFt: fit.lengthFt,
          coverage: fit.coverageScore,
          ortho: fit.orthogonalScore,
        );
      }
    }
    return (
      widthFt: measure.widthFt,
      lengthFt: measure.lengthFt,
      coverage: measure.coverageScore,
      ortho: measure.orthogonalScore,
    );
  }

  /// Empty metric rectangle plan — Home Scan stage 1 output.
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
    return AccurateScan.enforce(
      widthFt: w,
      lengthFt: l,
      openings: const [],
      furniture: const [],
      inventDefaultOpenings: false,
      sourceLabel: 'Home Scan (AR walk → metric plan)',
      accuracyScore: score,
      warnings: [
        'Home Scan (+127): continuous walk + floor hits → room size',
        'Room ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft'
            ' · samples $sampleCount · poses $poseCount'
            '${ortho > 0 ? ' · fit ${(ortho * 100).round()}%' : ''}'
            '${cov > 0 ? ' · wall cover ${(cov * 100).round()}%' : ''}',
        'Scale lock: ${ScaleLockConfidence.sourceLabel(ScaleSource.arPolygon)}',
        if (cov > 0 && cov < 0.75)
          'Incomplete walk loop — re-scan walking all four walls for better size',
        if (sampleCount < 12)
          'Few floor samples — walk slower and keep the phone aimed at the floor',
        'No furniture yet — add doors in Review or place from catalog / AR Place',
        if (score >= 0.99) '100% AR walk measured room geometry (metric size)',
      ],
    );
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
      },
      'floor_hits_m': floorHitsM,
      'poses_m': posesM,
      'sample_count': sampleCount,
      'pose_count': poseCount,
    };
  }

  String toJsonString({bool pretty = true}) =>
      pretty ? const JsonEncoder.withIndent('  ').convert(toJson()) : jsonEncode(toJson());

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
