import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/scan_result.dart';
import '../models/stroke_model.dart';

/// Estimate room scale for users who don't know measurements.
///
/// Photo-only AI has no absolute meter stick. We lock scale using **object
/// priors** (standard doors, beds, sofas) that most homes share, then
/// re-normalize the plan so it is usable for furniture layout.
///
/// This is *not* LiDAR accuracy — it is best-effort consumer scale.
class AutoScale {
  AutoScale._();

  /// Typical interior door clear width (feet).
  static const double standardDoorFt = 2.75;

  /// Acceptable door width range for a "standard" door prior.
  static const double minDoorFt = 2.2;
  static const double maxDoorFt = 3.6;

  /// Clamp estimated rooms to plausible residential sizes.
  static const double minRoomFt = 6.0;
  static const double maxRoomFt = 40.0;

  /// Default when nothing is detected.
  static const double fallbackWidthFt = 12.0;
  static const double fallbackLengthFt = 14.0;

  /// Furniture catalog priors used as secondary scale anchors (feet).
  /// +38: WARDROBE 6.5 (sliding study units) — prior 4.0 shrank correct long wardrobes.
  static const Map<String, double> furnitureLongSideFt = {
    'BED': 6.5,
    'SOFA': 7.0,
    'TABLE': 4.0,
    'WARDROBE': 6.5,
    'TV_UNIT': 5.0,
  };

  /// Minimum easy-scan room when inventory requires a long wardrobe (multi-wall).
  static const double photoTrueMinWidthFt = 14.0;
  static const double photoTrueMinLengthFt = 12.0;

  /// Denser study (wardrobe + mesh + multi-door) — closer to gold-plan footprint.
  static const double photoTrueDenseWidthFt = 16.0;
  static const double photoTrueDenseLengthFt = 14.0;

  /// Resolve final room size for easy scan.
  ///
  /// Priority:
  /// 1. User-entered size (if both positive)
  /// 2. Vision-estimated size, refined by door/furniture priors
  /// 3. Fallback 12×14
  static ({
    double widthFt,
    double lengthFt,
    double confidence,
    List<String> notes,
    bool usedUserSize,
  }) resolve({
    double? userWidthFt,
    double? userLengthFt,
    double? visionWidthFt,
    double? visionLengthFt,
    double? visionSizeConfidence,
    List<double> doorWidthsFt = const [],
    List<({String type, double widthFt, double lengthFt})> furniture = const [],
  }) {
    final notes = <String>[];

    if (userWidthFt != null &&
        userLengthFt != null &&
        userWidthFt > 0 &&
        userLengthFt > 0) {
      notes.add(
        'Room size from you: ${userWidthFt.toStringAsFixed(1)} × '
        '${userLengthFt.toStringAsFixed(1)} ft',
      );
      return (
        widthFt: userWidthFt,
        lengthFt: userLengthFt,
        confidence: 0.95,
        notes: notes,
        usedUserSize: true,
      );
    }

    var w = visionWidthFt ?? 0;
    var l = visionLengthFt ?? 0;
    var conf = (visionSizeConfidence ?? 0.45).clamp(0.2, 0.9);

    if (w <= 0 || l <= 0) {
      w = fallbackWidthFt;
      l = fallbackLengthFt;
      conf = 0.35;
      notes.add(
        'No size from photos — using typical ${fallbackWidthFt.toStringAsFixed(0)} × '
        '${fallbackLengthFt.toStringAsFixed(0)} ft room (edit in Review)',
      );
    } else {
      notes.add(
        'AI estimated room ≈ ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft',
      );
    }

    // Scale lock from doors: if vision reported a door width that should be
    // standard, rescale the whole plan so that door matches standardDoorFt.
    final scaleFromDoors = _doorScaleFactor(doorWidthsFt);
    if (scaleFromDoors != null) {
      w *= scaleFromDoors.factor;
      l *= scaleFromDoors.factor;
      conf = math.max(conf, 0.55 + 0.15 * scaleFromDoors.strength);
      notes.add(
        'Scale locked using ${scaleFromDoors.count} door(s) '
        '(standard ~${standardDoorFt.toStringAsFixed(2)} ft wide)',
      );
    }

    // Secondary: furniture long-side prior if doors missing
    if (scaleFromDoors == null && furniture.isNotEmpty) {
      final fScale = _furnitureScaleFactor(furniture);
      if (fScale != null) {
        w *= fScale.factor;
        l *= fScale.factor;
        conf = math.max(conf, 0.48);
        notes.add(
          'Scale refined using ${fScale.label} size prior',
        );
      }
    }

    w = w.clamp(minRoomFt, maxRoomFt);
    l = l.clamp(minRoomFt, maxRoomFt);

    // +38: long wardrobe / multi-piece study inventory needs room not under-sized
    // (12×10.5 feedback plans crushed wardrobe depth and door placement).
    final hasLongWardrobe = furniture.any((f) {
      final t = f.type.toUpperCase();
      if (!t.contains('WARDROBE')) return false;
      return math.max(f.widthFt, f.lengthFt) >= 5.5;
    });
    if (hasLongWardrobe) {
      final beforeW = w;
      final beforeL = l;
      w = math.max(w, photoTrueMinWidthFt);
      l = math.max(l, photoTrueMinLengthFt);
      if ((w - beforeW).abs() > 0.2 || (l - beforeL).abs() > 0.2) {
        conf = math.max(conf, 0.52);
        notes.add(
          'Room floor raised for long wardrobe (+38): '
          '${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft '
          '(edit in Review if your tape differs)',
        );
      }
    }

    // Prefer wider aspect ≥ 1 for consistency (swap if needed is optional;
    // keep vision orientation so furniture coords stay consistent).
    notes.add(
      'Easy scan: size is estimated for layout (not a tape survey). '
      'Fix scale in Review if a wall looks wrong.',
    );

    return (
      widthFt: double.parse(w.toStringAsFixed(2)),
      lengthFt: double.parse(l.toStringAsFixed(2)),
      confidence: conf.clamp(0.25, 0.88),
      notes: notes,
      usedUserSize: false,
    );
  }

  /// Expand estimated size when inventory requires wardrobe (and dense cues).
  static ({double widthFt, double lengthFt, List<String> notes}) ensurePhotoTrueMinSize({
    required double widthFt,
    required double lengthFt,
    required String inventoryHint,
    bool usedUserSize = false,
  }) {
    if (usedUserSize) {
      return (widthFt: widthFt, lengthFt: lengthFt, notes: const []);
    }
    if (!inventoryHint.contains('MUST include WARDROBE')) {
      return (widthFt: widthFt, lengthFt: lengthFt, notes: const []);
    }
    final dense = inventoryHint.toLowerCase().contains('mesh') ||
        inventoryHint.toLowerCase().contains('glass') ||
        inventoryHint.contains('balcony') ||
        RegExp(r'about\s+[2-9]\s+door').hasMatch(inventoryHint);

    final minW = dense ? photoTrueDenseWidthFt : photoTrueMinWidthFt;
    final minL = dense ? photoTrueDenseLengthFt : photoTrueMinLengthFt;

    var w = widthFt;
    var l = lengthFt;
    final notes = <String>[];
    if (w < minW || l < minL) {
      w = math.max(w, minW);
      l = math.max(l, minL);
      notes.add(
        'Photo-true min room (+39): ${w.toStringAsFixed(1)} × '
        '${l.toStringAsFixed(1)} ft for wardrobe'
        '${dense ? " + mesh/doors (gold-plan density)" : " inventory"}',
      );
    }
    return (widthFt: w, lengthFt: l, notes: notes);
  }

  /// Extract door segment lengths from parsed walls.
  static List<double> doorWidthsFromWalls(List<ScanWallSegment> walls) {
    return walls
        .where((s) => s.type == StrokeType.door)
        .map((s) => s.lengthFt)
        .where((len) => len > 0.5 && len < 8)
        .toList();
  }

  static ({double factor, int count, double strength})? _doorScaleFactor(
    List<double> doorWidthsFt,
  ) {
    final candidates = doorWidthsFt
        .where((d) => d >= minDoorFt * 0.5 && d <= maxDoorFt * 2.5)
        .toList();
    if (candidates.isEmpty) return null;

    // Prefer doors already near standard size for a mild correction;
    // if far off, still lock to standard (model often mis-scales whole room).
    final median = _median(candidates);
    if (median <= 0.01) return null;
    final factor = standardDoorFt / median;
    // Ignore tiny corrections
    if ((factor - 1.0).abs() < 0.04) {
      return (factor: 1.0, count: candidates.length, strength: 0.9);
    }
    // Cap extreme rescales (bad detections)
    final capped = factor.clamp(0.55, 1.85);
    final strength = (1.0 - (capped - 1.0).abs().clamp(0.0, 0.5)).clamp(0.3, 1.0);
    return (factor: capped, count: candidates.length, strength: strength);
  }

  static ({double factor, String label})? _furnitureScaleFactor(
    List<({String type, double widthFt, double lengthFt})> furniture,
  ) {
    for (final item in furniture) {
      final key = item.type.toUpperCase();
      final prior = furnitureLongSideFt[key];
      if (prior == null) continue;
      final longSide = math.max(item.widthFt, item.lengthFt);
      if (longSide < 1.5 || longSide > 20) continue;
      final factor = (prior / longSide).clamp(0.6, 1.7);
      if ((factor - 1.0).abs() < 0.05) continue;
      return (factor: factor, label: key.toLowerCase());
    }
    return null;
  }

  static double _median(List<double> xs) {
    final s = [...xs]..sort();
    final m = s.length ~/ 2;
    if (s.length.isOdd) return s[m];
    return (s[m - 1] + s[m]) / 2;
  }

  /// Re-scale all geometry when room size changes after auto-scale refine.
  static ScanResult rescaleResult(
    ScanResult input, {
    required double newWidthFt,
    required double newLengthFt,
    List<String> extraNotes = const [],
    double? accuracyScore,
  }) {
    final ox = input.roomWidthFt <= 0 ? 1.0 : input.roomWidthFt;
    final oy = input.roomLengthFt <= 0 ? 1.0 : input.roomLengthFt;
    final sx = newWidthFt / ox;
    final sy = newLengthFt / oy;
    final sAvg = (sx + sy) / 2;

    Offset map(Offset p) => Offset(p.dx * sx, p.dy * sy);

    return ScanResult(
      roomWidthFt: newWidthFt,
      roomLengthFt: newLengthFt,
      walls: [
        for (final w in input.walls)
          ScanWallSegment(
            type: w.type,
            startFt: map(w.startFt),
            endFt: map(w.endFt),
          ),
      ],
      furniture: [
        for (final f in input.furniture)
          ScanFurnitureHint(
            type: f.type,
            posFt: map(f.posFt),
            // Keep footprints realistic; AccurateScan re-applies catalog sizes.
            widthFt: f.widthFt * sAvg,
            lengthFt: f.lengthFt * sAvg,
            rotationRad: f.rotationRad,
            included: f.included,
          ),
      ],
      warnings: [...input.warnings, ...extraNotes],
      accuracyScore: accuracyScore ?? input.accuracyScore,
    );
  }
}
