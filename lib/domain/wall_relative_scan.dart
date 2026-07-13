import 'dart:math' as math;
import 'dart:ui';

import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'accurate_scan.dart';

/// Labelled perimeter walls of a rectangular room (designer walk order).
enum WallSide {
  /// y = 0 (bottom of plan / first wall user faces optional)
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
        return 'Stand facing this wall. Show full width of wall + floor edge. Include any door/window on THIS wall only.';
      case WallSide.east:
        return 'Turn 90° right. Capture the full length wall. Openings only on THIS wall.';
      case WallSide.north:
        return 'Continue around. Capture the wall opposite the first. Full wall + floor.';
      case WallSide.west:
        return 'Last wall. Capture full length. Then you may add furniture overview photos.';
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

/// Opening on a wall: [t0]–[t1] are fractions 0–1 along the wall (left→right as you face it).
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
}

/// Furniture anchored to a wall or free in room.
/// [t] = fraction along wall centerline (0–1), [depthFt] = distance from wall into room.
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
  /// If true, pos is free center (overview photo) not wall-anchored.
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
}

/// Compose a [ScanResult] from measured room size + wall-relative detections.
///
/// This is how designers work: overall measure → each wall → place objects
/// relative to walls — NOT freeform pixel guessing in a single photo.
class WallRelativeComposer {
  /// Convert wall-relative hints into feet-space scan geometry.
  static ScanResult compose({
    required double widthFt,
    required double lengthFt,
    List<WallOpeningHint> openings = const [],
    List<WallFurnitureHint> furniture = const [],
    List<String> warnings = const [],
    int wallPhotos = 0,
    int overviewPhotos = 0,
  }) {
    final w = widthFt <= 0 ? 10.0 : widthFt;
    final l = lengthFt <= 0 ? 10.0 : lengthFt;

    final notes = <String>[
      'Wall-relative compose (designer method): measure room → map each wall',
      'Size locked: ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft',
      if (wallPhotos > 0) 'Wall photos used: $wallPhotos / 4',
      if (overviewPhotos > 0) 'Overview photos: $overviewPhotos',
      ...warnings,
    ];

    final segs = <ScanWallSegment>[];
    for (final o in openings) {
      if (o.confidence < 0.65) {
        notes.add('Skipped low-confidence ${o.type.name} on ${o.wall.shortLabel}');
        continue;
      }
      final a = _pointOnWall(o.wall, o.t0.clamp(0.0, 1.0), w, l);
      final b = _pointOnWall(o.wall, o.t1.clamp(0.0, 1.0), w, l);
      if ((a - b).distance < 0.3) continue;
      segs.add(ScanWallSegment(type: o.type, startFt: a, endFt: b));
    }

    final furn = <ScanFurnitureHint>[];
    for (final f in furniture) {
      if (f.confidence < 0.7) {
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
        center = _furnitureCenter(f.wall!, f.t, f.depthFt, f.widthFt, f.lengthFt, w, l);
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

    // Accuracy: more wall photos + openings = higher
    var acc = 0.4;
    acc += (wallPhotos.clamp(0, 4) / 4) * 0.35;
    if (segs.isNotEmpty) acc += 0.1;
    if (furn.isNotEmpty) acc += 0.08;
    if (overviewPhotos > 0) acc += 0.05;
    acc = acc.clamp(0.4, 0.95);

    notes.add(
      'Scan confidence ~${(acc * 100).round()}% — '
      'wall-relative mapping is more reliable than single-photo guess',
    );

    return AccurateScan.enforce(
      widthFt: w,
      lengthFt: l,
      openings: segs,
      furniture: furn,
      warnings: notes,
      sourceLabel: 'Wall-by-wall precision compose (interior designer method)',
      inventDefaultOpenings: false,
      accuracyScore: acc,
    );
  }

  /// Point on wall at fraction [t] (0=start, 1=end) walking CCW from SW corner.
  static Offset _pointOnWall(WallSide wall, double t, double w, double l) {
    switch (wall) {
      case WallSide.south:
        // SW → SE along x
        return Offset(t * w, 0);
      case WallSide.east:
        // SE → NE along y
        return Offset(w, t * l);
      case WallSide.north:
        // NE → NW along -x (facing wall from outside: left is E)
        // When facing north wall from inside looking north: left is west.
        // Designer facing the wall: left-to-right as photographed.
        // Facing north wall from inside: left = west (x small), right = east (x large)?
        // If you face the north wall (looking +y), left is west (x=0), right is east (x=w).
        // t=0 left → x = t*w ... wait left is west x=0, right x=w, so x = t*w, y = l
        return Offset(t * w, l);
      case WallSide.west:
        // NW → SW: facing west wall looking -x: left is south? 
        // Facing west (looking -x): left is south (y=0), right is north (y=l) → y = t*l
        // Actually facing west: up is north. left = south (y small), right = north (y large).
        return Offset(0, t * l);
    }
  }

  /// Center of furniture against [wall]: [t] along wall, [depth] from wall face.
  static Offset _furnitureCenter(
    WallSide wall,
    double t,
    double depthFt,
    double fw,
    double fl,
    double w,
    double l,
  ) {
    // Depth into room from wall — at least half depth of piece
    final d = math.max(depthFt, fl / 2 + 0.1);
    final tt = t.clamp(0.05, 0.95);
    switch (wall) {
      case WallSide.south:
        return Offset(tt * w, d);
      case WallSide.east:
        return Offset(w - d, tt * l);
      case WallSide.north:
        return Offset(tt * w, l - d);
      case WallSide.west:
        return Offset(d, tt * l);
    }
  }

  /// Rotation so long side of piece runs along the wall (common for sofas/beds).
  static double _wallFacingRotation(WallSide wall) {
    switch (wall) {
      case WallSide.south:
      case WallSide.north:
        return 0; // width along X
      case WallSide.east:
      case WallSide.west:
        return math.pi / 2;
    }
  }
}
