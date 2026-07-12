import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog/furniture_catalog.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';

/// Guarantees a dimensionally correct top-down plan.
///
/// Room width × length always match the values the user measured.
/// Walls form a clean rectangle; openings sit on wall edges; furniture uses
/// catalog footprints and is fully inside the room (no hanging outside).
class AccurateScan {
  AccurateScan._();

  /// Force [widthFt] × [lengthFt] geometry and sanitize furniture/openings.
  static ScanResult enforce({
    required double widthFt,
    required double lengthFt,
    List<ScanWallSegment> openings = const [],
    List<ScanFurnitureHint> furniture = const [],
    List<String> warnings = const [],
    String? sourceLabel,
  }) {
    final w = widthFt <= 0 ? 10.0 : widthFt;
    final l = lengthFt <= 0 ? 10.0 : lengthFt;

    final notes = <String>[
      if (sourceLabel != null) sourceLabel,
      'Accurate plan: ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft '
          '(your measurements — photo aspect not used)',
      ...warnings,
    ];

    final outline = rectangleWalls(w, l);
    final doorsWindows = _projectOpeningsOntoWalls(
      openings
          .where((s) =>
              s.type == StrokeType.door ||
              s.type == StrokeType.window ||
              s.type == StrokeType.balcony)
          .toList(),
      w,
      l,
    );

    // Default door + window only when AI / vision gave none.
    final openingsFinal = doorsWindows.isEmpty
        ? _defaultOpenings(w, l)
        : doorsWindows;

    final cleanFurniture = _sanitizeFurniture(furniture, w, l, notes);

    return ScanResult(
      roomWidthFt: w,
      roomLengthFt: l,
      walls: [...outline, ...openingsFinal],
      furniture: cleanFurniture,
      warnings: notes,
    );
  }

  /// Perfect rectangular outline at exact size.
  static List<ScanWallSegment> rectangleWalls(double w, double l) {
    return [
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset.zero,
        endFt: Offset(w, 0),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(w, 0),
        endFt: Offset(w, l),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(w, l),
        endFt: Offset(0, l),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(0, l),
        endFt: Offset.zero,
      ),
    ];
  }

  static List<ScanWallSegment> _defaultOpenings(double w, double l) {
    final doorLen = math.min(3.0, w * 0.25).clamp(2.0, 3.5);
    final winLen = math.min(4.0, w * 0.35).clamp(2.0, 5.0);
    return [
      ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset((w - doorLen) / 2, 0),
        endFt: Offset((w + doorLen) / 2, 0),
      ),
      ScanWallSegment(
        type: StrokeType.window,
        startFt: Offset((w - winLen) / 2, l),
        endFt: Offset((w + winLen) / 2, l),
      ),
    ];
  }

  /// Snap opening segments onto the nearest outer wall edge.
  static List<ScanWallSegment> _projectOpeningsOntoWalls(
    List<ScanWallSegment> openings,
    double w,
    double l,
  ) {
    final out = <ScanWallSegment>[];
    for (final o in openings) {
      final mid = Offset(
        (o.startFt.dx + o.endFt.dx) / 2,
        (o.startFt.dy + o.endFt.dy) / 2,
      );
      final len = o.lengthFt.clamp(1.5, math.min(w, l) * 0.5);
      // Distance to each wall (top y=0, right x=w, bottom y=l, left x=0)
      final dTop = mid.dy.abs();
      final dRight = (w - mid.dx).abs();
      final dBottom = (l - mid.dy).abs();
      final dLeft = mid.dx.abs();
      final minD = [dTop, dRight, dBottom, dLeft].reduce(math.min);

      late Offset a;
      late Offset b;
      if (minD == dTop) {
        final cx = mid.dx.clamp(len / 2, w - len / 2);
        a = Offset(cx - len / 2, 0);
        b = Offset(cx + len / 2, 0);
      } else if (minD == dBottom) {
        final cx = mid.dx.clamp(len / 2, w - len / 2);
        a = Offset(cx - len / 2, l);
        b = Offset(cx + len / 2, l);
      } else if (minD == dRight) {
        final cy = mid.dy.clamp(len / 2, l - len / 2);
        a = Offset(w, cy - len / 2);
        b = Offset(w, cy + len / 2);
      } else {
        final cy = mid.dy.clamp(len / 2, l - len / 2);
        a = Offset(0, cy - len / 2);
        b = Offset(0, cy + len / 2);
      }
      out.add(ScanWallSegment(type: o.type, startFt: a, endFt: b));
    }
    return out;
  }

  static List<ScanFurnitureHint> _sanitizeFurniture(
    List<ScanFurnitureHint> input,
    double roomW,
    double roomL,
    List<String> notes,
  ) {
    final cleaned = <ScanFurnitureHint>[];
    var dropped = 0;

    for (final raw in input) {
      if (!raw.included) continue;

      final catalog = FurnitureCatalog.entryFor(raw.type);
      // Prefer catalog footprint so sizes match editor catalog (correctness).
      final fw = catalog.defaultWidthFt;
      final fl = catalog.defaultLengthFt;

      // Snap rotation to 45° (matches editor).
      final rotDeg = (raw.rotationRad * 180 / math.pi);
      final snappedDeg = (rotDeg / 45).round() * 45.0;
      final rot = snappedDeg * math.pi / 180;

      // Axis-aligned footprint bounds (conservative for rotated items).
      final cosA = math.cos(rot).abs();
      final sinA = math.sin(rot).abs();
      final occW = fw * cosA + fl * sinA;
      final occL = fw * sinA + fl * cosA;

      if (occW > roomW - 0.2 || occL > roomL - 0.2) {
        dropped++;
        continue; // piece does not fit this room
      }

      // Position is treated as top-left of unrotated item in scan JSON.
      var x = raw.posFt.dx;
      var y = raw.posFt.dy;
      x = x.clamp(0.0, math.max(0.0, roomW - occW));
      y = y.clamp(0.0, math.max(0.0, roomL - occL));

      final candidate = ScanFurnitureHint(
        type: raw.type,
        posFt: Offset(x, y),
        widthFt: fw,
        lengthFt: fl,
        rotationRad: rot,
        included: true,
      );

      // Drop heavy overlaps with already accepted pieces.
      if (_heavilyOverlaps(candidate, cleaned, roomW, roomL)) {
        dropped++;
        continue;
      }
      cleaned.add(candidate);
    }

    if (dropped > 0) {
      notes.add(
        'Dropped $dropped furniture item(s) that did not fit or heavily overlapped',
      );
    }
    if (cleaned.isEmpty && input.isNotEmpty) {
      notes.add('No furniture kept after accuracy check — add from catalog');
    }

    return cleaned;
  }

  static bool _heavilyOverlaps(
    ScanFurnitureHint a,
    List<ScanFurnitureHint> others,
    double _,
    double __,
  ) {
    final ra = _aabb(a);
    for (final b in others) {
      final rb = _aabb(b);
      final inter = ra.intersect(rb);
      if (inter.isEmpty) continue;
      final area = inter.width * inter.height;
      final areaA = ra.width * ra.height;
      if (areaA > 0 && area / areaA > 0.35) return true;
    }
    return false;
  }

  static Rect _aabb(ScanFurnitureHint f) {
    final cosA = math.cos(f.rotationRad).abs();
    final sinA = math.sin(f.rotationRad).abs();
    final occW = f.widthFt * cosA + f.lengthFt * sinA;
    final occL = f.widthFt * sinA + f.lengthFt * cosA;
    return Rect.fromLTWH(f.posFt.dx, f.posFt.dy, occW, occL);
  }
}
