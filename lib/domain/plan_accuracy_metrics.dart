import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'wall_relative_scan.dart';

/// Phase B labeled accuracy metrics (+108).
///
/// Compares a **predicted** scan plan to a **reference** (user-corrected gold,
/// tape plan, or manual blueprint). Planner5D-class quality is measured by
/// dimension error and placement fidelity — not only heuristic confidence %.
///
/// Does not invent geometry; pure evaluation for tests, training export, and
/// honest score calibration.
class PlanAccuracyReport {
  /// Relative room size error 0..∞ (0 = perfect). Use [roomSizeScore] for 0..1.
  final double roomSizeErrorPct;

  /// Mean absolute door width error in feet (doors only).
  final double doorWidthMaeFt;

  /// Predicted doors / reference doors, capped at 1.
  final double doorCountRecall;

  /// Fraction of reference furniture types present in predicted.
  final double furnitureTypeRecall;

  /// Mean center distance (ft) for matched types (largest of each type).
  final double furnitureCenterMaeFt;

  /// Composite 0..1 (higher = better match to reference).
  final double compositeScore;

  const PlanAccuracyReport({
    required this.roomSizeErrorPct,
    required this.doorWidthMaeFt,
    required this.doorCountRecall,
    required this.furnitureTypeRecall,
    required this.furnitureCenterMaeFt,
    required this.compositeScore,
  });

  /// Room size component 0..1 (≤5% error ≈ 1.0; ≥30% ≈ 0).
  double get roomSizeScore {
    final e = roomSizeErrorPct;
    if (e <= 0.05) return 1.0;
    if (e >= 0.30) return 0.0;
    return 1.0 - (e - 0.05) / 0.25;
  }

  String summaryLine() {
    return 'PlanAccuracy (+108): composite ${(compositeScore * 100).round()}% · '
        'size err ${(roomSizeErrorPct * 100).toStringAsFixed(1)}% · '
        'door MAE ${doorWidthMaeFt.toStringAsFixed(2)} ft · '
        'type recall ${(furnitureTypeRecall * 100).round()}% · '
        'center MAE ${furnitureCenterMaeFt.toStringAsFixed(1)} ft';
  }
}

class PlanAccuracyMetrics {
  PlanAccuracyMetrics._();

  /// Compare [predicted] to [reference] (gold / corrected plan).
  static PlanAccuracyReport compare(
    ScanResult predicted,
    ScanResult reference,
  ) {
    final roomErr = _roomSizeError(predicted, reference);
    final doors = _doorMetrics(predicted, reference);
    final furn = _furnitureMetrics(predicted, reference);

    // Weights: size 0.25, doors 0.30, type recall 0.25, placement 0.20
    final sizeScore = roomErr <= 0.05
        ? 1.0
        : roomErr >= 0.30
            ? 0.0
            : 1.0 - (roomErr - 0.05) / 0.25;
    final doorWidthScore = doors.mae <= 0.15
        ? 1.0
        : doors.mae >= 1.0
            ? 0.0
            : 1.0 - (doors.mae - 0.15) / 0.85;
    final doorScore = 0.55 * doors.recall + 0.45 * doorWidthScore;
    final placeScore = furn.centerMae <= 1.0
        ? 1.0
        : furn.centerMae >= 6.0
            ? 0.0
            : 1.0 - (furn.centerMae - 1.0) / 5.0;

    final composite = (0.25 * sizeScore +
            0.30 * doorScore +
            0.25 * furn.typeRecall +
            0.20 * placeScore)
        .clamp(0.0, 1.0);

    return PlanAccuracyReport(
      roomSizeErrorPct: roomErr,
      doorWidthMaeFt: doors.mae,
      doorCountRecall: doors.recall,
      furnitureTypeRecall: furn.typeRecall,
      furnitureCenterMaeFt: furn.centerMae,
      compositeScore: composite,
    );
  }

  /// Attach a metrics summary to [predicted] warnings (for training / Review).
  static ScanResult annotate(
    ScanResult predicted,
    ScanResult reference,
  ) {
    final r = compare(predicted, reference);
    return predicted.copyWith(
      warnings: [
        ...predicted.warnings,
        r.summaryLine(),
      ],
      accuracyScore: predicted.accuracyScore == null
          ? r.compositeScore
          : math.max(predicted.accuracyScore!, r.compositeScore * 0.9),
    );
  }

  static double _roomSizeError(ScanResult a, ScanResult b) {
    final aw = a.roomWidthFt;
    final al = a.roomLengthFt;
    final bw = b.roomWidthFt;
    final bl = b.roomLengthFt;
    if (aw <= 0 || al <= 0 || bw <= 0 || bl <= 0) return 1.0;
    // Allow orientation swap
    final e1 = ((aw - bw).abs() / bw + (al - bl).abs() / bl) / 2;
    final e2 = ((aw - bl).abs() / bl + (al - bw).abs() / bw) / 2;
    return math.min(e1, e2);
  }

  static ({double mae, double recall}) _doorMetrics(
    ScanResult pred,
    ScanResult ref,
  ) {
    final pDoors = pred.walls.where((w) => w.type == StrokeType.door).toList();
    final rDoors = ref.walls.where((w) => w.type == StrokeType.door).toList();
    if (rDoors.isEmpty) {
      return (mae: pDoors.isEmpty ? 0.0 : 0.5, recall: 1.0);
    }
    final recall = (pDoors.length / rDoors.length).clamp(0.0, 1.0);
    if (pDoors.isEmpty) return (mae: 2.0, recall: 0.0);

    // Greedy match by wall + nearest width
    final pw = pred.roomWidthFt;
    final pl = pred.roomLengthFt;
    final rw = ref.roomWidthFt;
    final rl = ref.roomLengthFt;
    final used = <int>{};
    var errSum = 0.0;
    var n = 0;
    for (final r in rDoors) {
      final rf = WallRelativeComposer.openingToField(r, rw, rl);
      var bestI = -1;
      var best = double.infinity;
      for (var i = 0; i < pDoors.length; i++) {
        if (used.contains(i)) continue;
        final pf = WallRelativeComposer.openingToField(pDoors[i], pw, pl);
        if (rf != null && pf != null && rf.wall != pf.wall) {
          // Prefer same wall; allow if no same-wall candidate later
          continue;
        }
        final pe = pDoors[i].lengthFt;
        final re = r.lengthFt;
        final d = (pe - re).abs();
        if (d < best) {
          best = d;
          bestI = i;
        }
      }
      // Fallback any unmatched door
      if (bestI < 0) {
        for (var i = 0; i < pDoors.length; i++) {
          if (used.contains(i)) continue;
          final d = (pDoors[i].lengthFt - r.lengthFt).abs();
          if (d < best) {
            best = d;
            bestI = i;
          }
        }
      }
      if (bestI >= 0) {
        used.add(bestI);
        errSum += best;
        n++;
      } else {
        errSum += r.lengthFt; // missing
        n++;
      }
    }
    return (mae: n == 0 ? 0.0 : errSum / n, recall: recall.toDouble());
  }

  static ({double typeRecall, double centerMae}) _furnitureMetrics(
    ScanResult pred,
    ScanResult ref,
  ) {
    final pMap = <FurnitureType, ScanFurnitureHint>{};
    for (final f in pred.furniture.where((x) => x.included)) {
      final cur = pMap[f.type];
      if (cur == null ||
          f.widthFt * f.lengthFt > cur.widthFt * cur.lengthFt) {
        pMap[f.type] = f;
      }
    }
    final rList = <ScanFurnitureHint>[];
    final rSeen = <FurnitureType>{};
    for (final f in ref.furniture.where((x) => x.included)) {
      if (rSeen.contains(f.type)) continue;
      // Keep largest of type as reference
      final same = ref.furniture
          .where((x) => x.included && x.type == f.type)
          .toList()
        ..sort((a, b) =>
            (b.widthFt * b.lengthFt).compareTo(a.widthFt * a.lengthFt));
      rList.add(same.first);
      rSeen.add(f.type);
    }
    if (rList.isEmpty) {
      return (typeRecall: 1.0, centerMae: 0.0);
    }
    var hits = 0;
    var distSum = 0.0;
    var distN = 0;
    // Scale pred positions into ref room for fair distance
    final sx = ref.roomWidthFt / (pred.roomWidthFt <= 0 ? 1 : pred.roomWidthFt);
    final sy =
        ref.roomLengthFt / (pred.roomLengthFt <= 0 ? 1 : pred.roomLengthFt);
    for (final r in rList) {
      final p = pMap[r.type];
      if (p == null) continue;
      hits++;
      final pp = Offset(p.posFt.dx * sx, p.posFt.dy * sy);
      distSum += (pp - r.posFt).distance;
      distN++;
    }
    final recall = hits / rList.length;
    final mae = distN == 0 ? 8.0 : distSum / distN;
    return (typeRecall: recall, centerMae: mae);
  }
}

/// How room scale was measured (+108).
enum ScaleSource {
  /// ARCore 4-wall chain (highest phone-grade without LiDAR).
  arChain,

  /// ARCore quick two-segment measure.
  arQuick,

  /// User tape / field measure.
  tape,

  /// User typed size in Review.
  userTyped,

  /// Photo auto-scale priors only.
  photoEstimate,
}

/// Measured-scale lock confidence (Planner5D-class) (+108).
///
/// Photos alone cannot certify meters. When the user locks W×L from AR or tape,
/// confidence should rise to survey-assistive levels and stay there through refine.
class ScaleLockConfidence {
  ScaleLockConfidence._();

  /// Floor confidence by measurement source (before layout quality blend).
  static double sourceFloor(
    ScaleSource source, {
    double oppositeWallError = 0,
  }) {
    switch (source) {
      case ScaleSource.arChain:
        if (oppositeWallError > 0.12) return 0.84;
        if (oppositeWallError > 0.08) return 0.90;
        return 0.94;
      case ScaleSource.arQuick:
        return 0.88;
      case ScaleSource.tape:
        return 0.96;
      case ScaleSource.userTyped:
        return 0.92;
      case ScaleSource.photoEstimate:
        return 0.45;
    }
  }

  static String sourceLabel(ScaleSource source) {
    switch (source) {
      case ScaleSource.arChain:
        return 'AR 4-wall chain';
      case ScaleSource.arQuick:
        return 'AR quick measure';
      case ScaleSource.tape:
        return 'tape / field measure';
      case ScaleSource.userTyped:
        return 'user-typed size';
      case ScaleSource.photoEstimate:
        return 'photo estimate';
    }
  }

  /// Blend layout confidence with measured-scale floor.
  static double blend({
    required double? layoutScore,
    required ScaleSource source,
    double oppositeWallError = 0,
  }) {
    final floor = sourceFloor(source, oppositeWallError: oppositeWallError);
    final layout = (layoutScore ?? 0.55).clamp(0.2, 0.98);
    if (source == ScaleSource.photoEstimate) {
      return layout.clamp(0.25, 0.90);
    }
    // Measured scale dominates: 65% floor + 35% layout quality
    final blended = floor * 0.65 + layout * 0.35;
    return blended.clamp(floor, 0.98);
  }
}
