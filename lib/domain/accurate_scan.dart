import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog/furniture_catalog.dart';
import '../models/furniture_item.dart';
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
  ///
  /// [inventDefaultOpenings]: when true and vision found no doors/windows,
  /// add a placeholder door+window (legacy offline path). Precision scans
  /// should pass false so we never invent openings.
  static ScanResult enforce({
    required double widthFt,
    required double lengthFt,
    List<ScanWallSegment> openings = const [],
    List<ScanFurnitureHint> furniture = const [],
    List<String> warnings = const [],
    String? sourceLabel,
    bool inventDefaultOpenings = true,
    double? accuracyScore,
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

    final List<ScanWallSegment> openingsFinal;
    if (doorsWindows.isEmpty && inventDefaultOpenings) {
      openingsFinal = _defaultOpenings(w, l);
      notes.add(
        'No openings detected — placeholder door/window added (edit in blueprint)',
      );
    } else if (doorsWindows.isEmpty) {
      openingsFinal = const [];
      notes.add(
        'No doors/windows confidently detected — add them with Door/Window tools',
      );
    } else {
      openingsFinal = doorsWindows;
    }

    final cleanFurniture = _sanitizeFurniture(furniture, w, l, notes);

    return ScanResult(
      roomWidthFt: w,
      roomLengthFt: l,
      walls: [...outline, ...openingsFinal],
      furniture: cleanFurniture,
      warnings: notes,
      accuracyScore: accuracyScore,
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
    // +136: door on long wall (typical entry), window opposite / short side
    final longIsW = w >= l;
    final doorLen = math.min(3.0, math.min(w, l) * 0.28).clamp(2.4, 3.2);
    final winLen = math.min(4.5, math.max(w, l) * 0.28).clamp(2.5, 5.0);
    if (longIsW) {
      // Door on south (y=l), window on north (y=0)
      return [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset((w - doorLen) / 2, l),
          endFt: Offset((w + doorLen) / 2, l),
        ),
        ScanWallSegment(
          type: StrokeType.window,
          startFt: Offset((w - winLen) / 2, 0),
          endFt: Offset((w + winLen) / 2, 0),
        ),
      ];
    }
    // Tall room: door on east, window on west
    return [
      ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(w, (l - doorLen) / 2),
        endFt: Offset(w, (l + doorLen) / 2),
      ),
      ScanWallSegment(
        type: StrokeType.window,
        startFt: Offset(0, (l - winLen) / 2),
        endFt: Offset(0, (l + winLen) / 2),
      ),
    ];
  }

  /// Snap opening segments onto the nearest outer wall edge.
  ///
  /// +59: mesh/balcony may span most of a wall (gold plan); do not crush to
  /// 50% of the short room side like a normal door.
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
      // Distance to each wall (top y=0, right x=w, bottom y=l, left x=0)
      final dTop = mid.dy.abs();
      final dRight = (w - mid.dx).abs();
      final dBottom = (l - mid.dy).abs();
      final dLeft = mid.dx.abs();
      final minD = [dTop, dRight, dBottom, dLeft].reduce(math.min);

      // Wall length for the edge we snap to
      final wallLen =
          (minD == dTop || minD == dBottom) ? w : l;
      final len = _clampOpeningLen(o.type, o.lengthFt, wallLen);

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

  static double _clampOpeningLen(
    StrokeType type,
    double raw,
    double wallLen,
  ) {
    final maxOnWall = math.max(2.0, wallLen * 0.92);
    switch (type) {
      case StrokeType.door:
        return raw.clamp(2.0, math.min(4.0, maxOnWall));
      case StrokeType.window:
        return raw.clamp(1.5, math.min(10.0, maxOnWall));
      case StrokeType.balcony:
        // Gold mesh/sliding glass often 5–10+ ft
        return raw.clamp(3.5, math.min(14.0, maxOnWall));
      case StrokeType.wall:
        return raw.clamp(1.0, maxOnWall);
    }
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

      // +38: size-aware catalog (long wardrobe → wide entry, not 4×2 crush)
      final catalog = FurnitureCatalog.entryForSized(
        raw.type,
        widthFt: raw.widthFt,
        lengthFt: raw.lengthFt,
      );
      // Keep scanned sizes when realistic; fall back to catalog defaults.
      var fw = raw.widthFt;
      var fl = raw.lengthFt;
      final cw = catalog.defaultWidthFt;
      final cl = catalog.defaultLengthFt;

      if (raw.type == FurnitureType.wardrobe) {
        // +70: long sliding wardrobes span most of a wall (gold ~72% of 20ft).
        // Old checks used min(room) and fw>roomW which crushed N/S units when
        // along was stored in width on a room where width < along (or vice versa).
        final maxAlong = math.max(roomW, roomL) * 0.92;
        var along = math.max(fw, fl);
        var deep = math.min(fw, fl);
        if (fw < 0.5 || fl < 0.5) {
          along = cw;
          deep = cl;
        } else {
          if (along > maxAlong) along = maxAlong;
          if (along < 4.0 && deep < 1.0) {
            along = cw;
            deep = cl;
          }
          if (deep > 2.8 || deep < 1.0) deep = 1.5;
          along = along.clamp(4.0, maxAlong);
        }
        // Preserve which axis was long (rotation handles wall alignment)
        if (raw.widthFt >= raw.lengthFt) {
          fw = along;
          fl = deep;
        } else {
          fw = deep;
          fl = along;
        }
      } else if (fw < 0.5 || fl < 0.5 || fw > roomW || fl > roomL) {
        fw = cw;
        fl = cl;
      } else if (fw > cw * 2.5 ||
          fl > cl * 2.5 ||
          fw < cw * 0.35 ||
          fl < cl * 0.35) {
        fw = cw;
        fl = cl;
      }

      // Snap rotation to 45° (matches editor).
      final rotDeg = (raw.rotationRad * 180 / math.pi);
      final snappedDeg = (rotDeg / 45).round() * 45.0;
      final rot = snappedDeg * math.pi / 180;

      // Axis-aligned footprint (center-based position from vision).
      final cosA = math.cos(rot).abs();
      final sinA = math.sin(rot).abs();
      final occW = fw * cosA + fl * sinA;
      final occL = fw * sinA + fl * cosA;

      if (occW > roomW - 0.15 || occL > roomL - 0.15) {
        // Scale down slightly to keep the piece rather than drop it
        final scale = math.min(
          (roomW - 0.3) / occW,
          (roomL - 0.3) / occL,
        ).clamp(0.4, 1.0);
        fw *= scale;
        fl *= scale;
      }

      final occW2 = fw * cosA + fl * sinA;
      final occL2 = fw * sinA + fl * cosA;
      if (occW2 > roomW - 0.1 || occL2 > roomL - 0.1) {
        dropped++;
        continue;
      }

      // pos is CENTER of the piece in feet (matches editor / painters).
      var cx = raw.posFt.dx;
      var cy = raw.posFt.dy;
      // If model returned near-corner (0,0) with large piece, treat as top-left
      if (cx < occW2 * 0.15 && cy < occL2 * 0.15 && raw.posFt.dx < 1.0) {
        cx = raw.posFt.dx + occW2 / 2;
        cy = raw.posFt.dy + occL2 / 2;
      }
      cx = cx.clamp(occW2 / 2, math.max(occW2 / 2, roomW - occW2 / 2));
      cy = cy.clamp(occL2 / 2, math.max(occL2 / 2, roomL - occL2 / 2));

      final candidate = ScanFurnitureHint(
        type: raw.type,
        posFt: Offset(cx, cy),
        widthFt: fw,
        lengthFt: fl,
        rotationRad: rot,
        included: true,
      );

      // Soft overlap: only drop near-duplicates
      if (_heavilyOverlaps(candidate, cleaned)) {
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
    } else if (cleaned.isNotEmpty) {
      notes.add(
        'Placed ${cleaned.length} piece(s) from scan as-is. '
        'Use Arrange to try a more spacious layout.',
      );
    }

    return cleaned;
  }

  static bool _heavilyOverlaps(
    ScanFurnitureHint a,
    List<ScanFurnitureHint> others,
  ) {
    final ra = _centerAabb(a);
    for (final b in others) {
      final rb = _centerAabb(b);
      final inter = ra.intersect(rb);
      if (inter.isEmpty) continue;
      final area = inter.width * inter.height;
      final areaA = ra.width * ra.height;
      // Only drop near-duplicates (was 35% — too aggressive for tight rooms)
      if (areaA > 0 && area / areaA > 0.55) return true;
    }
    return false;
  }

  /// AABB from center-based furniture position.
  static Rect _centerAabb(ScanFurnitureHint f) {
    final cosA = math.cos(f.rotationRad).abs();
    final sinA = math.sin(f.rotationRad).abs();
    final occW = f.widthFt * cosA + f.lengthFt * sinA;
    final occL = f.widthFt * sinA + f.lengthFt * cosA;
    return Rect.fromCenter(
      center: f.posFt,
      width: occW,
      height: occL,
    );
  }
}
