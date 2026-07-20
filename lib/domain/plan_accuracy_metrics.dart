import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'furniture_position_map.dart';
import 'opening_chain_fidelity.dart';
import 'photo_true_layout.dart';
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

  /// Mean door/window along-wall fromLeft error (ft) when wall matches (+111).
  final double openingFromLeftMaeFt;

  /// Composite 0..1 (higher = better match to reference).
  final double compositeScore;

  const PlanAccuracyReport({
    required this.roomSizeErrorPct,
    required this.doorWidthMaeFt,
    required this.doorCountRecall,
    required this.furnitureTypeRecall,
    required this.furnitureCenterMaeFt,
    this.openingFromLeftMaeFt = 0,
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
    return 'PlanAccuracy (+111): composite ${(compositeScore * 100).round()}% · '
        'size err ${(roomSizeErrorPct * 100).toStringAsFixed(1)}% · '
        'door MAE ${doorWidthMaeFt.toStringAsFixed(2)} ft · '
        'type recall ${(furnitureTypeRecall * 100).round()}% · '
        'furn MAE ${furnitureCenterMaeFt.toStringAsFixed(1)} ft · '
        'open fromLeft MAE ${openingFromLeftMaeFt.toStringAsFixed(1)} ft';
  }

  /// Short Review / snackbar line (+109/+111) — stresses furniture position.
  String reviewLine() {
    return 'Phase B vs template ${(compositeScore * 100).round()}% · '
        'furniture MAE ${furnitureCenterMaeFt.toStringAsFixed(1)} ft · '
        'doors MAE ${doorWidthMaeFt.toStringAsFixed(1)} ft · '
        'types ${(furnitureTypeRecall * 100).round()}%';
  }

  Map<String, dynamic> toJson() => {
        'composite': double.parse(compositeScore.toStringAsFixed(4)),
        'room_size_error_pct':
            double.parse(roomSizeErrorPct.toStringAsFixed(4)),
        'door_width_mae_ft': double.parse(doorWidthMaeFt.toStringAsFixed(3)),
        'door_count_recall': double.parse(doorCountRecall.toStringAsFixed(3)),
        'furniture_type_recall':
            double.parse(furnitureTypeRecall.toStringAsFixed(3)),
        'furniture_center_mae_ft':
            double.parse(furnitureCenterMaeFt.toStringAsFixed(3)),
        'opening_fromleft_mae_ft':
            double.parse(openingFromLeftMaeFt.toStringAsFixed(3)),
        'room_size_score': double.parse(roomSizeScore.toStringAsFixed(3)),
      };
}

class PlanAccuracyMetrics {
  PlanAccuracyMetrics._();

  /// Compare [predicted] to [reference] (gold / corrected plan).
  ///
  /// +111: weights stress **furniture position** (placement 0.35) and opening
  /// fromLeft along walls so blueprint mapping is the primary accuracy bar.
  static PlanAccuracyReport compare(
    ScanResult predicted,
    ScanResult reference,
  ) {
    final roomErr = _roomSizeError(predicted, reference);
    final doors = _doorMetrics(predicted, reference);
    final furn = _furnitureMetrics(predicted, reference);
    final openPos = _openingFromLeftMae(predicted, reference);

    // Weights (+111): size 0.15, doors 0.20, type recall 0.20, furn place 0.35,
    // opening fromLeft 0.10 — furniture position is the stressed bar.
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
    // Tighter furniture MAE curve: ≤1.0 ft full credit; ≥4.5 ft zero (+111)
    final placeScore = furn.centerMae <= 1.0
        ? 1.0
        : furn.centerMae >= 4.5
            ? 0.0
            : 1.0 - (furn.centerMae - 1.0) / 3.5;
    final openPosScore = openPos <= 0.5
        ? 1.0
        : openPos >= 4.0
            ? 0.0
            : 1.0 - (openPos - 0.5) / 3.5;

    final composite = (0.15 * sizeScore +
            0.20 * doorScore +
            0.20 * furn.typeRecall +
            0.35 * placeScore +
            0.10 * openPosScore)
        .clamp(0.0, 1.0);

    return PlanAccuracyReport(
      roomSizeErrorPct: roomErr,
      doorWidthMaeFt: doors.mae,
      doorCountRecall: doors.recall,
      furnitureTypeRecall: furn.typeRecall,
      furnitureCenterMaeFt: furn.centerMae,
      openingFromLeftMaeFt: openPos,
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

  /// Build a gold-class template reference from inventory cues (+109).
  ///
  /// Used when no user-corrected plan exists yet — Phase B baseline against
  /// Planner5D-class dense layout for the same room size / room type.
  static ScanResult syntheticReference(ScanResult predicted) {
    final w = predicted.roomWidthFt > 0
        ? predicted.roomWidthFt
        : PhotoTrueLayout.goldRoomWidthFt;
    final l = predicted.roomLengthFt > 0
        ? predicted.roomLengthFt
        : PhotoTrueLayout.goldRoomLengthFt;
    // Promote visible furniture types into MUST inventory so empty-shell gold
    // matches the room class (study vs bedroom/living).
    final must = <String>[];
    final types = predicted.furniture
        .where((f) => f.included)
        .map((f) => f.type)
        .toSet();
    if (types.contains(FurnitureType.bed) ||
        PhotoTrueLayout.isBedroomLike(predicted)) {
      must.add('MUST include BED');
    }
    if (types.contains(FurnitureType.sofa) ||
        PhotoTrueLayout.isLivingLike(predicted)) {
      must.add('MUST include SOFA');
    }
    if (types.contains(FurnitureType.wardrobe) ||
        predicted.warnings.join(' ').toLowerCase().contains('wardrobe')) {
      must.add('MUST include WARDROBE');
    }
    if (types.contains(FurnitureType.table) ||
        predicted.warnings.join(' ').toLowerCase().contains('table') ||
        predicted.warnings.join(' ').toLowerCase().contains('desk')) {
      must.add('MUST include TABLE');
    }
    if (types.contains(FurnitureType.tvUnit)) {
      must.add('MUST include TV_UNIT');
    }
    final blob = predicted.warnings.join(' ').toLowerCase();
    if (blob.contains('mesh') || blob.contains('balcony')) {
      must.add('MUST include mesh balcony');
    }
    if (blob.contains('2 door') || blob.contains('about 2 door')) {
      must.add('about 2 door opening(s)');
    }
    final shell = ScanResult(
      roomWidthFt: w,
      roomLengthFt: l,
      walls: const [],
      furniture: const [],
      warnings: [
        ...predicted.warnings,
        if (must.isNotEmpty) 'Inventory: ${must.join('; ')}',
        'phase_b synthetic gold template (+109)',
      ],
      accuracyScore: 0.3,
    );
    return PhotoTrueLayout.ensureGoldQuality(shell);
  }

  /// Full diagnostics map for training export + Review (+109).
  ///
  /// [userCorrected]: when set (editor gold), also report predicted vs user (+110).
  static Map<String, dynamic> diagnosticsJson(
    ScanResult predicted, {
    ScanResult? userCorrected,
  }) {
    final ref = syntheticReference(predicted);
    final report = compare(predicted, ref);
    final openingFid = OpeningChainFidelity.score(predicted);
    final placeFid = FurniturePositionMap.score(predicted);
    final geom = PhotoTrueLayout.isStudyLike(predicted)
        ? PhotoTrueLayout.goldGeometryMatchScore(predicted)
        : null;
    final scale = _detectScaleSource(predicted.warnings);
    PlanAccuracyReport? vsUser;
    if (userCorrected != null) {
      vsUser = compare(predicted, userCorrected);
    }
    return {
      'schema': userCorrected != null ? 'phase_b_v2' : 'phase_b_v1',
      'vs_template': report.toJson(),
      if (vsUser != null) 'vs_user_corrected': vsUser.toJson(),
      'opening_fidelity': double.parse(openingFid.toStringAsFixed(3)),
      'furniture_position_fidelity':
          double.parse(placeFid.toStringAsFixed(3)),
      if (geom != null) 'geometry_match': double.parse(geom.toStringAsFixed(3)),
      'scale_source': scale,
      'heuristic_accuracy': predicted.accuracyScore,
      'room_type': PhotoTrueLayout.isBedroomLike(predicted)
          ? 'bedroom'
          : PhotoTrueLayout.isLivingLike(predicted)
              ? 'living'
              : PhotoTrueLayout.isStudyLike(predicted)
                  ? 'study'
                  : 'generic',
      'template': PhotoTrueLayout.isStudyLike(predicted) &&
              !PhotoTrueLayout.isBedroomLike(predicted)
          ? 'study_gold'
          : 'non_study_gold',
      if (userCorrected != null) 'has_user_gold': true,
    };
  }

  /// Compare predicted to template; return report for UI (+109).
  static PlanAccuracyReport vsTemplate(ScanResult predicted) {
    return compare(predicted, syntheticReference(predicted));
  }

  static String _detectScaleSource(List<String> warnings) {
    final blob = warnings.join(' ').toLowerCase();
    if (blob.contains('tape') || blob.contains('field measure')) return 'tape';
    if (blob.contains('4-wall') || blob.contains('ar chain')) return 'ar_chain';
    if (blob.contains('arcore') || blob.contains('ar ')) return 'ar_quick';
    if (blob.contains('scale lock (+108)')) {
      if (blob.contains('tape')) return 'tape';
      if (blob.contains('chain')) return 'ar_chain';
      if (blob.contains('user-typed')) return 'user_typed';
    }
    if (blob.contains('user') && blob.contains('size')) return 'user_typed';
    return 'photo_estimate';
  }

  /// Serialize plan geometry for training JSONL (+109).
  static Map<String, dynamic> planToJson(ScanResult r) {
    return {
      'width_ft': r.roomWidthFt,
      'length_ft': r.roomLengthFt,
      'accuracy': r.accuracyScore,
      'openings': [
        for (final w in r.walls)
          if (w.type != StrokeType.wall)
            {
              'type': w.type.name,
              'x0': double.parse(w.startFt.dx.toStringAsFixed(3)),
              'y0': double.parse(w.startFt.dy.toStringAsFixed(3)),
              'x1': double.parse(w.endFt.dx.toStringAsFixed(3)),
              'y1': double.parse(w.endFt.dy.toStringAsFixed(3)),
              'len_ft': double.parse(w.lengthFt.toStringAsFixed(3)),
            },
      ],
      'furniture': [
        for (final f in r.furniture)
          if (f.included)
            {
              'type': f.type.name,
              'x': double.parse(f.posFt.dx.toStringAsFixed(3)),
              'y': double.parse(f.posFt.dy.toStringAsFixed(3)),
              'w': double.parse(f.widthFt.toStringAsFixed(3)),
              'l': double.parse(f.lengthFt.toStringAsFixed(3)),
              'rot': double.parse(f.rotationRad.toStringAsFixed(4)),
            },
      ],
    };
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

  /// Mean absolute fromLeft error for doors/windows/balcony on matching walls.
  static double _openingFromLeftMae(ScanResult pred, ScanResult ref) {
    final pOp = pred.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .toList();
    final rOp = ref.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .toList();
    if (rOp.isEmpty) return pOp.isEmpty ? 0.0 : 1.0;
    if (pOp.isEmpty) return 3.0;

    final pw = pred.roomWidthFt;
    final pl = pred.roomLengthFt;
    final rw = ref.roomWidthFt;
    final rl = ref.roomLengthFt;
    final used = <int>{};
    var errSum = 0.0;
    var n = 0;
    for (final r in rOp) {
      final rf = WallRelativeComposer.openingToField(r, rw, rl);
      var bestI = -1;
      var best = double.infinity;
      for (var i = 0; i < pOp.length; i++) {
        if (used.contains(i)) continue;
        final pf = WallRelativeComposer.openingToField(pOp[i], pw, pl);
        if (rf == null || pf == null) continue;
        if (rf.wall != pf.wall || r.type != pOp[i].type) continue;
        final d = (pf.fromLeftFt - rf.fromLeftFt).abs();
        if (d < best) {
          best = d;
          bestI = i;
        }
      }
      if (bestI < 0) {
        // Any same type
        for (var i = 0; i < pOp.length; i++) {
          if (used.contains(i) || pOp[i].type != r.type) continue;
          final pf = WallRelativeComposer.openingToField(pOp[i], pw, pl);
          final d = pf == null || rf == null
              ? 4.0
              : (pf.fromLeftFt - rf.fromLeftFt).abs() + 1.5;
          if (d < best) {
            best = d;
            bestI = i;
          }
        }
      }
      if (bestI >= 0) {
        used.add(bestI);
        errSum += best.isFinite ? best : 3.0;
        n++;
      } else {
        errSum += 3.0;
        n++;
      }
    }
    return n == 0 ? 0.0 : errSum / n;
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
