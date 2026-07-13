import 'dart:math' as math;
import 'dart:ui';

import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'accurate_scan.dart';

/// Labelled perimeter walls of a rectangular room (designer walk order A→D).
enum WallSide {
  /// y = 0
  south,
  /// x = width
  east,
  /// y = length
  north,
  /// x = 0
  west,
}

extension WallSideX on WallSide {
  String get label {
    switch (this) {
      case WallSide.south:
        return 'Wall A (width side)';
      case WallSide.east:
        return 'Wall B (length side)';
      case WallSide.north:
        return 'Wall C (opposite width)';
      case WallSide.west:
        return 'Wall D (opposite length)';
    }
  }

  String get shortLabel {
    switch (this) {
      case WallSide.south:
        return 'Wall A';
      case WallSide.east:
        return 'Wall B';
      case WallSide.north:
        return 'Wall C';
      case WallSide.west:
        return 'Wall D';
    }
  }

  String get tip {
    switch (this) {
      case WallSide.south:
        return 'Face this wall from inside. Left of photo = left as you face it. '
            'Tape: measure from LEFT corner along the wall to each opening.';
      case WallSide.east:
        return 'Turn 90° right. Face this length wall. Measure from left corner.';
      case WallSide.north:
        return 'Continue around. Face opposite width wall. Left→right as you face it.';
      case WallSide.west:
        return 'Last length wall. Face it; measure from left corner along wall.';
    }
  }

  /// Length of this wall in feet for a W×L rectangle.
  double lengthFt(double widthFt, double lengthFt) {
    switch (this) {
      case WallSide.south:
      case WallSide.north:
        return widthFt;
      case WallSide.east:
      case WallSide.west:
        return lengthFt;
    }
  }
}

/// Standard opening widths used when vision is unsure (interior design norms).
class OpeningPriors {
  static double clampWidth(StrokeType type, double raw, double wallLen) {
    final maxW = math.max(1.0, wallLen * 0.85);
    switch (type) {
      case StrokeType.door:
        // Standard interior door ~2.5–3.5 ft; exterior up to ~4
        return raw.clamp(2.0, math.min(4.0, maxW));
      case StrokeType.window:
        return raw.clamp(1.5, math.min(8.0, maxW));
      case StrokeType.balcony:
        return raw.clamp(3.0, math.min(14.0, maxW));
      case StrokeType.wall:
        return raw.clamp(0.5, maxW);
    }
  }

  static double defaultWidth(StrokeType type) {
    switch (type) {
      case StrokeType.door:
        return 3.0;
      case StrokeType.window:
        return 4.0;
      case StrokeType.balcony:
        return 6.0;
      case StrokeType.wall:
        return 1.0;
    }
  }
}

/// Opening on a wall: [t0]–[t1] are fractions 0–1 **left→right as you face the wall**.
class WallOpeningHint {
  final WallSide wall;
  final StrokeType type; // door | window | balcony
  final double t0;
  final double t1;
  final double confidence;
  final String evidence;

  const WallOpeningHint({
    required this.wall,
    required this.type,
    required this.t0,
    required this.t1,
    this.confidence = 1,
    this.evidence = '',
  });

  /// Designer field measure: distance from **left corner while facing the wall**.
  factory WallOpeningHint.fromLeft({
    required WallSide wall,
    required StrokeType type,
    required double fromLeftFt,
    required double widthFt,
    required double wallLengthFt,
    double confidence = 1,
    String evidence = 'tape measure',
  }) {
    final wl = wallLengthFt <= 0 ? 1.0 : wallLengthFt;
    final w = OpeningPriors.clampWidth(type, widthFt, wl);
    final left = fromLeftFt.clamp(0.0, math.max(0.0, wl - 0.5));
    final right = (left + w).clamp(0.0, wl);
    return WallOpeningHint(
      wall: wall,
      type: type,
      t0: (left / wl).clamp(0.0, 1.0),
      t1: (right / wl).clamp(0.0, 1.0),
      confidence: confidence,
      evidence: evidence,
    );
  }

  double fromLeftFt(double wallLengthFt) => t0 * wallLengthFt;

  double widthAlongWallFt(double wallLengthFt) =>
      math.max(0.1, (t1 - t0).abs() * wallLengthFt);
}

/// Furniture anchored to a wall or free in room.
/// [t] = fraction along wall **left→right facing the wall**, [depthFt] into room.
class WallFurnitureHint {
  final FurnitureType type;
  final WallSide? wall;
  final double t;
  final double depthFt;
  final double widthFt;
  final double lengthFt;
  final double rotDeg;
  final double confidence;
  final String evidence;
  final bool freePlace;
  final double? freeXFt;
  final double? freeYFt;

  const WallFurnitureHint({
    required this.type,
    this.wall,
    this.t = 0.5,
    this.depthFt = 1.5,
    required this.widthFt,
    required this.lengthFt,
    this.rotDeg = 0,
    this.confidence = 1,
    this.evidence = '',
    this.freePlace = false,
    this.freeXFt,
    this.freeYFt,
  });

  /// Center of piece is [fromLeftFt] from left corner when facing wall.
  factory WallFurnitureHint.fromLeft({
    required FurnitureType type,
    required WallSide wall,
    required double fromLeftFt,
    required double depthFt,
    required double widthFt,
    required double lengthFt,
    required double wallLengthFt,
    double confidence = 1,
    String evidence = 'tape measure',
  }) {
    final wl = wallLengthFt <= 0 ? 1.0 : wallLengthFt;
    final t = (fromLeftFt / wl).clamp(0.05, 0.95);
    return WallFurnitureHint(
      type: type,
      wall: wall,
      t: t,
      depthFt: depthFt.clamp(0.5, 12),
      widthFt: widthFt,
      lengthFt: lengthFt,
      confidence: confidence,
      evidence: evidence,
    );
  }
}

/// Compose a [ScanResult] from measured room size + wall-relative detections.
///
/// Matches how interior designers work (field measure):
/// 1. Overall room W × L (tape / laser)
/// 2. Each wall clockwise: corner → opening → width → next
/// 3. Furniture: distance along wall + depth from wall face
///
/// Coordinates use **facing-the-wall left→right**, not plan CCW order.
class WallRelativeComposer {
  static ScanResult compose({
    required double widthFt,
    required double lengthFt,
    List<WallOpeningHint> openings = const [],
    List<WallFurnitureHint> furniture = const [],
    List<String> warnings = const [],
    int wallPhotos = 0,
    int overviewPhotos = 0,
    bool fromTapeMeasure = false,
  }) {
    final w = widthFt <= 0 ? 10.0 : widthFt;
    final l = lengthFt <= 0 ? 10.0 : lengthFt;

    final notes = <String>[
      fromTapeMeasure
          ? 'Field measure compose (designer tape method) — highest precision without LiDAR'
          : 'Wall-relative compose (designer method): measure room → map each wall',
      'Size locked: ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft',
      if (wallPhotos > 0) 'Wall photos used: $wallPhotos / 4',
      if (overviewPhotos > 0) 'Overview photos: $overviewPhotos',
      ...warnings,
    ];

    final segs = <ScanWallSegment>[];
    for (final o in openings) {
      if (o.confidence < 0.55 && !fromTapeMeasure) {
        notes.add('Skipped low-confidence ${o.type.name} on ${o.wall.shortLabel}');
        continue;
      }
      final wallLen = o.wall.lengthFt(w, l);
      // Enforce realistic opening widths (vision often invents wrong spans)
      final fromL = o.fromLeftFt(wallLen);
      final rawW = o.widthAlongWallFt(wallLen);
      final fixed = WallOpeningHint.fromLeft(
        wall: o.wall,
        type: o.type,
        fromLeftFt: fromL,
        widthFt: OpeningPriors.clampWidth(o.type, rawW, wallLen),
        wallLengthFt: wallLen,
        confidence: o.confidence,
        evidence: o.evidence,
      );
      final a = _pointOnWallFacing(fixed.wall, fixed.t0, w, l);
      final b = _pointOnWallFacing(fixed.wall, fixed.t1, w, l);
      if ((a - b).distance < 0.4) continue;
      segs.add(ScanWallSegment(type: fixed.type, startFt: a, endFt: b));
    }

    final furn = <ScanFurnitureHint>[];
    for (final f in furniture) {
      if (f.confidence < 0.65 && !fromTapeMeasure) {
        notes.add('Skipped low-confidence ${f.type.name}');
        continue;
      }
      late Offset center;
      late double rot;
      if (f.freePlace && f.freeXFt != null && f.freeYFt != null) {
        center = Offset(
          f.freeXFt!.clamp(0.5, w - 0.5),
          f.freeYFt!.clamp(0.5, l - 0.5),
        );
        rot = f.rotDeg * math.pi / 180;
      } else if (f.wall != null) {
        center = _furnitureCenterFacing(
          f.wall!,
          f.t,
          f.depthFt,
          f.widthFt,
          f.lengthFt,
          w,
          l,
        );
        rot = _wallFacingRotation(f.wall!);
      } else {
        continue;
      }
      furn.add(ScanFurnitureHint(
        type: f.type,
        posFt: center,
        widthFt: f.widthFt,
        lengthFt: f.lengthFt,
        rotationRad: rot,
      ));
    }

    // Accuracy: tape > wall photos > free vision
    var acc = fromTapeMeasure ? 0.82 : 0.38;
    if (fromTapeMeasure) {
      if (segs.isNotEmpty) acc += 0.08;
      if (furn.isNotEmpty) acc += 0.05;
      acc = acc.clamp(0.82, 0.98);
    } else {
      acc += (wallPhotos.clamp(0, 4) / 4) * 0.35;
      if (segs.isNotEmpty) acc += 0.1;
      if (furn.isNotEmpty) acc += 0.08;
      if (overviewPhotos > 0) acc += 0.05;
      acc = acc.clamp(0.35, 0.88);
    }

    notes.add(
      'Scan confidence ~${(acc * 100).round()}% — '
      '${fromTapeMeasure ? "tape distances are plan truth" : "photo AI is assistive; edit openings in Review"}',
    );

    return AccurateScan.enforce(
      widthFt: w,
      lengthFt: l,
      openings: segs,
      furniture: furn,
      warnings: notes,
      sourceLabel: fromTapeMeasure
          ? 'Field measure (interior designer tape method)'
          : 'Wall-by-wall precision compose (interior designer method)',
      inventDefaultOpenings: false,
      accuracyScore: acc,
    );
  }

  /// Point on wall at fraction [t] **left→right as you face the wall from inside**.
  ///
  /// Facing south wall (looking −y): left = east (x=w), right = west (x=0).
  /// Facing east wall (looking +x): left = north (y=l), right = south (y=0).
  /// Facing north wall (looking +y): left = west (x=0), right = east (x=w).
  /// Facing west wall (looking −x): left = south (y=0), right = north (y=l).
  static Offset _pointOnWallFacing(WallSide wall, double t, double w, double l) {
    final tt = t.clamp(0.0, 1.0);
    switch (wall) {
      case WallSide.south:
        return Offset(w * (1.0 - tt), 0);
      case WallSide.east:
        return Offset(w, l * (1.0 - tt));
      case WallSide.north:
        return Offset(tt * w, l);
      case WallSide.west:
        return Offset(0, tt * l);
    }
  }

  /// Center of furniture against [wall]: [t] along wall (facing L→R), [depth] into room.
  static Offset _furnitureCenterFacing(
    WallSide wall,
    double t,
    double depthFt,
    double fw,
    double fl,
    double w,
    double l,
  ) {
    final d = math.max(depthFt, fl / 2 + 0.1);
    final tt = t.clamp(0.05, 0.95);
    switch (wall) {
      case WallSide.south:
        // along wall x = w*(1-t), into room +y
        return Offset(w * (1.0 - tt), d);
      case WallSide.east:
        // along wall y = l*(1-t), into room −x
        return Offset(w - d, l * (1.0 - tt));
      case WallSide.north:
        return Offset(tt * w, l - d);
      case WallSide.west:
        return Offset(d, tt * l);
    }
  }

  /// Rotation so long side of piece runs along the wall.
  static double _wallFacingRotation(WallSide wall) {
    switch (wall) {
      case WallSide.south:
      case WallSide.north:
        return 0;
      case WallSide.east:
      case WallSide.west:
        return math.pi / 2;
    }
  }

  /// Reverse: given a segment on the room outline, recover wall + fromLeft + width.
  static ({WallSide wall, double fromLeftFt, double widthFt})? openingToField(
    ScanWallSegment seg,
    double roomW,
    double roomL, {
    double edgeTol = 0.35,
  }) {
    if (seg.type == StrokeType.wall) return null;
    final mid = Offset(
      (seg.startFt.dx + seg.endFt.dx) / 2,
      (seg.startFt.dy + seg.endFt.dy) / 2,
    );
    final len = seg.lengthFt;

    late WallSide wall;
    late double fromLeft;

    if (mid.dy <= edgeTol) {
      wall = WallSide.south;
      // facing: left = east, x decreases as t increases
      final leftEdgeX = math.max(seg.startFt.dx, seg.endFt.dx);
      fromLeft = roomW - leftEdgeX;
    } else if (mid.dy >= roomL - edgeTol) {
      wall = WallSide.north;
      final leftEdgeX = math.min(seg.startFt.dx, seg.endFt.dx);
      fromLeft = leftEdgeX;
    } else if (mid.dx >= roomW - edgeTol) {
      wall = WallSide.east;
      final leftEdgeY = math.max(seg.startFt.dy, seg.endFt.dy);
      fromLeft = roomL - leftEdgeY;
    } else if (mid.dx <= edgeTol) {
      wall = WallSide.west;
      final leftEdgeY = math.min(seg.startFt.dy, seg.endFt.dy);
      fromLeft = leftEdgeY;
    } else {
      return null;
    }

    return (
      wall: wall,
      fromLeftFt: fromLeft.clamp(0.0, wall.lengthFt(roomW, roomL)),
      widthFt: OpeningPriors.clampWidth(
        seg.type,
        len,
        wall.lengthFt(roomW, roomL),
      ),
    );
  }
}
