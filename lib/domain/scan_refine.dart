import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog/furniture_catalog.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'accurate_scan.dart';
import 'wall_relative_scan.dart';

/// Post-process scan geometry for higher layout accuracy.
///
/// Does **not** invent walls. Improves:
/// - opening widths (standard door/window priors)
/// - furniture against walls (common placement)
/// - de-overlap of stacked AI guesses
/// - confidence score from geometric consistency
class ScanRefine {
  ScanRefine._();

  /// Apply all refinements. Safe to call multiple times.
  static ScanResult refine(ScanResult input) {
    final w = input.roomWidthFt;
    final l = input.roomLengthFt;
    if (w <= 0 || l <= 0) return input;

    final notes = <String>[...input.warnings];
    var openings = _refineOpenings(input.walls, w, l, notes);
    var furniture = _refineFurniture(input.furniture, w, l, notes);
    furniture = _nudgeOverlaps(furniture, notes);

    final score = _score(
      widthFt: w,
      lengthFt: l,
      openings: openings,
      furniture: furniture,
      prior: input.accuracyScore,
    );

    // Re-enforce rectangle + catalog sizes after nudges
    final enforced = AccurateScan.enforce(
      widthFt: w,
      lengthFt: l,
      openings: openings,
      furniture: furniture,
      warnings: notes
          .where((n) =>
              !n.startsWith('Accurate plan:') &&
              !n.startsWith('Field measure') &&
              !n.startsWith('Wall-relative') &&
              !n.startsWith('Size locked:'))
          .toList(),
      sourceLabel: 'Geometry refine (priors + wall snap)',
      inventDefaultOpenings: false,
      accuracyScore: score,
    );
    return enforced.copyWith(
      warnings: [
        ...enforced.warnings,
        if (score != null)
          'Refined plan confidence ~${(score * 100).round()}%',
      ],
      accuracyScore: score,
    );
  }

  /// Rescale an existing plan to new AR/tape size (keeps relative layout).
  static ScanResult lockSize(
    ScanResult input, {
    required double widthFt,
    required double lengthFt,
    String reason = 'Size locked from AR refine',
  }) {
    final ox = input.roomWidthFt <= 0 ? 1.0 : input.roomWidthFt;
    final oy = input.roomLengthFt <= 0 ? 1.0 : input.roomLengthFt;
    final sx = widthFt / ox;
    final sy = lengthFt / oy;
    final sAvg = (sx + sy) / 2;

    Offset map(Offset p) => Offset(p.dx * sx, p.dy * sy);

    final scaled = ScanResult(
      roomWidthFt: widthFt,
      roomLengthFt: lengthFt,
      walls: [
        for (final wall in input.walls)
          ScanWallSegment(
            type: wall.type,
            startFt: map(wall.startFt),
            endFt: map(wall.endFt),
          ),
      ],
      furniture: [
        for (final f in input.furniture)
          ScanFurnitureHint(
            type: f.type,
            posFt: map(f.posFt),
            widthFt: f.widthFt * sAvg,
            lengthFt: f.lengthFt * sAvg,
            rotationRad: f.rotationRad,
            included: f.included,
          ),
      ],
      warnings: [...input.warnings, reason],
      accuracyScore: ((input.accuracyScore ?? 0.55) + 0.2).clamp(0.5, 0.95),
    );
    return refine(scaled);
  }

  static List<ScanWallSegment> _refineOpenings(
    List<ScanWallSegment> walls,
    double w,
    double l,
    List<String> notes,
  ) {
    final openings = walls
        .where((s) =>
            s.type == StrokeType.door ||
            s.type == StrokeType.window ||
            s.type == StrokeType.balcony)
        .toList();
    if (openings.isEmpty) return openings;

    final hints = <WallOpeningHint>[];
    var priorFixes = 0;

    for (final o in openings) {
      final field = WallRelativeComposer.openingToField(o, w, l);
      if (field == null) continue;
      final wallLen = field.wall.lengthFt(w, l);
      final clamped = OpeningPriors.clampWidth(o.type, field.widthFt, wallLen);
      if ((clamped - field.widthFt).abs() > 0.35) priorFixes++;
      final fromLeft = field.fromLeftFt
          .clamp(0.0, math.max(0.0, wallLen - clamped))
          .toDouble();
      hints.add(WallOpeningHint.fromLeft(
        wall: field.wall,
        type: o.type,
        fromLeftFt: fromLeft,
        widthFt: clamped,
        wallLengthFt: wallLen,
        confidence: 1,
        evidence: 'scan_refine',
      ));
    }

    // Compose rebuilds facing-correct segments on the perimeter
    final composed = WallRelativeComposer.compose(
      widthFt: w,
      lengthFt: l,
      openings: hints,
      fromTapeMeasure: true,
    );
    var refined = composed.walls
        .where((s) =>
            s.type == StrokeType.door ||
            s.type == StrokeType.window ||
            s.type == StrokeType.balcony)
        .toList();

    // Drop near-duplicate openings (centers within 1.5 ft)
    final deduped = <ScanWallSegment>[];
    for (final o in refined) {
      final mid = Offset(
        (o.startFt.dx + o.endFt.dx) / 2,
        (o.startFt.dy + o.endFt.dy) / 2,
      );
      final dup = deduped.any((e) {
        if (e.type != o.type) return false;
        final em = Offset(
          (e.startFt.dx + e.endFt.dx) / 2,
          (e.startFt.dy + e.endFt.dy) / 2,
        );
        return (em - mid).distance < 1.5;
      });
      if (!dup) deduped.add(o);
    }
    if (deduped.length < refined.length) {
      notes.add(
        'Merged ${refined.length - deduped.length} duplicate opening(s)',
      );
    }
    if (priorFixes > 0) {
      notes.add(
        'Adjusted $priorFixes opening width(s) toward standard sizes (doors ~2.5–3.5 ft)',
      );
    }
    return deduped;
  }

  static List<ScanFurnitureHint> _refineFurniture(
    List<ScanFurnitureHint> items,
    double w,
    double l,
    List<String> notes,
  ) {
    var wallSnaps = 0;
    final out = <ScanFurnitureHint>[];

    for (final raw in items) {
      if (!raw.included) continue;
      final catalog = FurnitureCatalog.entryFor(raw.type);
      var fw = raw.widthFt;
      var fl = raw.lengthFt;
      if (fw < 0.8 || fl < 0.8) {
        fw = catalog.defaultWidthFt;
        fl = catalog.defaultLengthFt;
      }

      var pos = raw.posFt;
      // Distance to each wall (center to wall)
      final dS = pos.dy; // south y=0
      final dN = l - pos.dy;
      final dW = pos.dx;
      final dE = w - pos.dx;
      final minD = [dS, dN, dW, dE].reduce(math.min);
      final halfDeep = math.min(fw, fl) / 2;

      // Snap against wall if roughly near it (typical placement)
      const near = 2.2; // ft
      if (minD < near) {
        if (minD == dS) {
          pos = Offset(pos.dx, halfDeep + 0.15);
        } else if (minD == dN) {
          pos = Offset(pos.dx, l - halfDeep - 0.15);
        } else if (minD == dW) {
          pos = Offset(halfDeep + 0.15, pos.dy);
        } else {
          pos = Offset(w - halfDeep - 0.15, pos.dy);
        }
        wallSnaps++;
      }

      // Keep fully inside
      final hx = fw / 2;
      final hy = fl / 2;
      pos = Offset(
        pos.dx.clamp(hx + 0.05, w - hx - 0.05),
        pos.dy.clamp(hy + 0.05, l - hy - 0.05),
      );

      // Rotation snap 90° for wall-aligned pieces when near wall
      var rot = raw.rotationRad;
      if (minD < near) {
        final deg = (rot * 180 / math.pi);
        rot = ((deg / 90).round() * 90) * math.pi / 180;
      }

      out.add(ScanFurnitureHint(
        type: raw.type,
        posFt: pos,
        widthFt: fw,
        lengthFt: fl,
        rotationRad: rot,
        included: true,
      ));
    }

    if (wallSnaps > 0) {
      notes.add('Snapped $wallSnaps piece(s) to nearest wall (layout refine)');
    }
    return out;
  }

  static List<ScanFurnitureHint> _nudgeOverlaps(
    List<ScanFurnitureHint> items,
    List<String> notes,
  ) {
    if (items.length < 2) return items;
    final list = List<ScanFurnitureHint>.from(items);
    var moves = 0;
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i];
        final b = list[j];
        final dx = b.posFt.dx - a.posFt.dx;
        final dy = b.posFt.dy - a.posFt.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        final minSep =
            (math.max(a.widthFt, a.lengthFt) + math.max(b.widthFt, b.lengthFt)) /
                2 *
                0.55;
        if (dist < minSep && dist > 0.01) {
          final push = (minSep - dist) / 2 + 0.15;
          final nx = dx / dist;
          final ny = dy / dist;
          list[j] = ScanFurnitureHint(
            type: b.type,
            posFt: Offset(b.posFt.dx + nx * push, b.posFt.dy + ny * push),
            widthFt: b.widthFt,
            lengthFt: b.lengthFt,
            rotationRad: b.rotationRad,
            included: b.included,
          );
          moves++;
        }
      }
    }
    if (moves > 0) {
      notes.add('Separated $moves overlapping furniture guess(es)');
    }
    return list;
  }

  static double? _score({
    required double widthFt,
    required double lengthFt,
    required List<ScanWallSegment> openings,
    required List<ScanFurnitureHint> furniture,
    double? prior,
  }) {
    var s = prior ?? 0.5;
    // Plausible room size
    if (widthFt >= 7 && widthFt <= 30 && lengthFt >= 7 && lengthFt <= 30) {
      s += 0.05;
    }
    final doors =
        openings.where((o) => o.type == StrokeType.door).length;
    if (doors >= 1) s += 0.08;
    if (doors > 3) s -= 0.05; // too many doors often hallucination
    if (furniture.isNotEmpty && furniture.length <= 12) s += 0.05;
    if (furniture.length > 15) s -= 0.08;
    // Aspect not extreme
    final aspect = widthFt / lengthFt;
    if (aspect > 0.4 && aspect < 2.5) s += 0.03;
    return s.clamp(0.35, 0.94);
  }
}
