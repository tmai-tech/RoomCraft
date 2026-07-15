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
    openings = _capOpenings(openings, notes);
    var furniture = _refineFurniture(input.furniture, w, l, notes);
    furniture = _nudgeOverlaps(furniture, notes);
    furniture = _capFurniture(furniture, notes);

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
    var kept = 0;
    final out = <ScanFurnitureHint>[];

    // Feedback 5244fa22: nearest-wall re-snap scrambled correct wall-anchored
    // layouts into "random" plans. Only snap pieces floating in open floor.
    const floatThresholdFt = 2.2;

    for (final raw in items) {
      if (!raw.included) continue;
      final catalog = FurnitureCatalog.entryFor(raw.type);
      var fw = raw.widthFt;
      var fl = raw.lengthFt;
      final cw = catalog.defaultWidthFt;
      final cl = catalog.defaultLengthFt;
      // Soft size fix only for absurd values — keep vision sizes when plausible
      // (wardrobe spans and desk depths matter for matching photos).
      if (fw < 0.6 || fl < 0.6 || fw > w * 0.95 || fl > l * 0.95) {
        fw = cw;
        fl = cl;
      } else if (fw > cw * 3.0 || fl > cl * 3.0 || fw < cw * 0.25 || fl < cl * 0.25) {
        fw = cw;
        fl = cl;
      }

      var pos = raw.posFt;
      var rot = raw.rotationRad;
      final dS = pos.dy;
      final dN = l - pos.dy;
      final dW = pos.dx;
      final dE = w - pos.dx;
      final minD = [dS, dN, dW, dE].reduce(math.min);
      final halfDeep = math.min(fw, fl) / 2;
      final halfAlong = math.max(fw, fl) / 2;

      final floating = minD > floatThresholdFt + halfDeep;
      if (floating) {
        // Truly free-floating XY from monocular guess — pin to nearest wall.
        late Offset snappedPos;
        if (minD == dS || (dS <= dN && dS <= dW && dS <= dE)) {
          snappedPos = Offset(
            pos.dx.clamp(halfAlong + 0.1, w - halfAlong - 0.1),
            halfDeep + 0.15,
          );
          rot = 0;
        } else if (minD == dN) {
          snappedPos = Offset(
            pos.dx.clamp(halfAlong + 0.1, w - halfAlong - 0.1),
            l - halfDeep - 0.15,
          );
          rot = math.pi;
        } else if (minD == dW) {
          snappedPos = Offset(
            halfDeep + 0.15,
            pos.dy.clamp(halfAlong + 0.1, l - halfAlong - 0.1),
          );
          rot = math.pi / 2;
        } else {
          snappedPos = Offset(
            w - halfDeep - 0.15,
            pos.dy.clamp(halfAlong + 0.1, l - halfAlong - 0.1),
          );
          rot = -math.pi / 2;
        }
        wallSnaps++;
        pos = snappedPos;
      } else {
        kept++;
        // Already near a wall (wall-anchored scan) — keep placement/rotation.
      }

      final hx = fw / 2;
      final hy = fl / 2;
      pos = Offset(
        pos.dx.clamp(hx + 0.05, w - hx - 0.05),
        pos.dy.clamp(hy + 0.05, l - hy - 0.05),
      );

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
      notes.add(
        'Pinned $wallSnaps floating piece(s) to nearest wall '
        '($kept already wall-placed kept as-is)',
      );
    }
    return out;
  }

  /// Prefer doors > windows > balconies; drop excess / near-duplicates.
  static List<ScanWallSegment> _capOpenings(
    List<ScanWallSegment> openings,
    List<String> notes,
  ) {
    if (openings.isEmpty) return openings;

    int rank(StrokeType t) {
      switch (t) {
        case StrokeType.door:
          return 0;
        case StrokeType.window:
          return 1;
        case StrokeType.balcony:
          return 2;
        default:
          return 3;
      }
    }

    final sorted = List<ScanWallSegment>.from(openings)
      ..sort((a, b) {
        final r = rank(a.type).compareTo(rank(b.type));
        if (r != 0) return r;
        return b.lengthFt.compareTo(a.lengthFt);
      });

    final doors = sorted.where((o) => o.type == StrokeType.door).take(2);
    final windows = sorted.where((o) => o.type == StrokeType.window).take(4);
    final balconies = sorted.where((o) => o.type == StrokeType.balcony).take(1);
    final kept = [...doors, ...windows, ...balconies];
    if (kept.length < openings.length) {
      notes.add(
        'Kept ${kept.length} of ${openings.length} openings '
        '(dropped extra guesses for a cleaner plan)',
      );
    }
    return kept;
  }

  static List<ScanFurnitureHint> _capFurniture(
    List<ScanFurnitureHint> items,
    List<String> notes,
  ) {
    if (items.length <= 12) return items;
    // Prefer larger / more central pieces as "primary" furniture.
    final sorted = List<ScanFurnitureHint>.from(items)
      ..sort((a, b) {
        final aa = a.widthFt * a.lengthFt;
        final bb = b.widthFt * b.lengthFt;
        return bb.compareTo(aa);
      });
    final kept = sorted.take(12).toList();
    notes.add(
      'Kept ${kept.length} of ${items.length} furniture items '
      '(largest pieces first — edit the rest in the editor)',
    );
    return kept;
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
    if (furniture.isNotEmpty && furniture.length <= 12) {
      s += 0.05;
      s += (furniture.length.clamp(1, 6) / 6) * 0.08;
    } else {
      // Do not claim high confidence with an empty furniture list.
      s = s.clamp(0.0, 0.52);
    }
    if (furniture.length > 15) s -= 0.08;
    // Aspect not extreme
    final aspect = widthFt / lengthFt;
    if (aspect > 0.4 && aspect < 2.5) s += 0.03;
    final cap = furniture.isEmpty ? 0.52 : 0.94;
    return s.clamp(0.28, cap);
  }
}
