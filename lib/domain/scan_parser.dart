import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'wall_relative_scan.dart';

/// Parses / validates / normalizes AI JSON and applies scale calibration.
class ScanParser {
  static const _uuid = Uuid();

  static const Map<String, FurnitureType> _furnitureAliases = {
    'BED': FurnitureType.bed,
    'DOUBLE_BED': FurnitureType.bed,
    'QUEEN_BED': FurnitureType.bed,
    'KING_BED': FurnitureType.bed,
    'MATTRESS': FurnitureType.bed,
    'WARDROBE': FurnitureType.wardrobe,
    'CLOSET': FurnitureType.wardrobe,
    'CABINET': FurnitureType.wardrobe,
    'DRESSER': FurnitureType.wardrobe,
    'CUPBOARD': FurnitureType.wardrobe,
    'ARMOIRE': FurnitureType.wardrobe,
    'SOFA': FurnitureType.sofa,
    'COUCH': FurnitureType.sofa,
    'LOVESEAT': FurnitureType.sofa,
    'SECTIONAL': FurnitureType.sofa,
    'TABLE': FurnitureType.table,
    'DESK': FurnitureType.table,
    'DINING_TABLE': FurnitureType.table,
    'COFFEE_TABLE': FurnitureType.table,
    'SIDE_TABLE': FurnitureType.table,
    'CHAIR': FurnitureType.chair,
    'ARMCHAIR': FurnitureType.chair,
    'OFFICE_CHAIR': FurnitureType.chair,
    'STOOL': FurnitureType.chair,
    'BENCH': FurnitureType.chair,
    'TV_UNIT': FurnitureType.tvUnit,
    'TVUNIT': FurnitureType.tvUnit,
    'TV': FurnitureType.tvUnit,
    'TV_STAND': FurnitureType.tvUnit,
    'TELEVISION': FurnitureType.tvUnit,
    'MEDIA_CONSOLE': FurnitureType.tvUnit,
    'BOOKSHELF': FurnitureType.bookshelf,
    'BOOKCASE': FurnitureType.bookshelf,
    'SHELF': FurnitureType.bookshelf,
    'SHELVING': FurnitureType.bookshelf,
    'NIGHTSTAND': FurnitureType.nightstand,
    'NIGHT_STAND': FurnitureType.nightstand,
    'BEDSIDE': FurnitureType.nightstand,
    'BEDSIDE_TABLE': FurnitureType.nightstand,
  };

  /// Parse raw AI map → [ScanResult]. Throws [FormatException] if unusable.
  static ScanResult parse(Map<String, dynamic> raw) {
    final warnings = <String>[];

    var roomWidth = _asDouble(raw['roomWidth']) ?? _asDouble(raw['width']);
    var roomLength = _asDouble(raw['roomLength']) ?? _asDouble(raw['length']);

    if (roomWidth == null || roomWidth <= 0) {
      roomWidth = 12.0;
      warnings.add('Missing roomWidth — defaulted to 12 ft');
    }
    if (roomLength == null || roomLength <= 0) {
      roomLength = 12.0;
      warnings.add('Missing roomLength — defaulted to 12 ft');
    }

    // Sanity clamp
    if (roomWidth > 80 || roomLength > 80) {
      warnings.add('Very large room dimensions from AI — check scale');
    }
    if (roomWidth < 4 || roomLength < 4) {
      warnings.add('Very small room dimensions from AI — check scale');
    }

    // Prefer wall-relative layout when model returns wall + fromLeft (stable).
    final wallOpenings = <WallOpeningHint>[];
    final wallFurniture = <WallFurnitureHint>[];
    final freeWalls = <ScanWallSegment>[];
    final freeFurniture = <ScanFurnitureHint>[];

    final wallsRaw = <dynamic>[
      if (raw['walls'] is List) ...raw['walls'] as List,
      if (raw['openings'] is List) ...raw['openings'] as List,
    ];
    for (final item in wallsRaw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final confRaw = map['confidence'] ?? map['conf'];
      final conf = confRaw is num ? confRaw.toDouble() : 0.8;
      if (conf < 0.55) {
        warnings.add('Skipped low-confidence opening (${map['type']})');
        continue;
      }
      final type = _parseStrokeType(map['type']?.toString());

      final wall = _parseWallSide(map['wall']?.toString());
      final fromLeft = _asDouble(map['fromLeft'] ?? map['from_left'] ?? map['leftFt']);
      final widthAlong = _asDouble(
            map['width'] ?? map['widthFt'] ?? map['openingWidth'],
          ) ??
          _asDouble((map['dim'] is Map) ? (map['dim'] as Map)['w'] : null);

      // Wall-relative openings (not outline walls).
      if (wall != null &&
          fromLeft != null &&
          widthAlong != null &&
          type != StrokeType.wall) {
        wallOpenings.add(WallOpeningHint.fromLeft(
          wall: wall,
          type: type,
          fromLeftFt: fromLeft,
          widthFt: widthAlong,
          wallLengthFt: wall.lengthFt(roomWidth, roomLength),
          confidence: conf,
          evidence: map['evidence']?.toString() ?? '',
        ));
        continue;
      }

      final start = _parsePoint(map['start']);
      final end = _parsePoint(map['end']);
      if (start == null || end == null) {
        warnings.add('Skipped a wall segment with invalid points');
        continue;
      }
      if ((end - start).distance < 0.1) {
        warnings.add('Skipped near-zero length wall segment');
        continue;
      }
      freeWalls.add(ScanWallSegment(type: type, startFt: start, endFt: end));
    }

    final furnRaw = raw['furniture'];
    if (furnRaw is List) {
      for (final item in furnRaw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final type = _parseFurnitureType(map['type']?.toString());
        if (type == null) {
          warnings.add('Unknown furniture type: ${map['type']}');
          continue;
        }
        final confRaw = map['confidence'] ?? map['conf'];
        final conf = confRaw is num ? confRaw.toDouble() : 0.7;
        final dim = map['dim'] ?? map['size'];
        double? w;
        double? l;
        if (dim is Map) {
          w = _asDouble(dim['w'] ?? dim['width']);
          l = _asDouble(dim['l'] ?? dim['length'] ?? dim['h']);
        }
        w ??= 3.0;
        l ??= 3.0;

        final wall = _parseWallSide(map['wall']?.toString());
        final fromLeft = _asDouble(
          map['fromLeft'] ?? map['from_left'] ?? map['alongWall'],
        );
        final depth = _asDouble(map['depth'] ?? map['depthFt'] ?? map['fromWall']) ??
            mathMin(w, l) / 2 + 0.2;

        if (wall != null && fromLeft != null) {
          wallFurniture.add(WallFurnitureHint.fromLeft(
            type: type,
            wall: wall,
            fromLeftFt: fromLeft,
            depthFt: depth,
            widthFt: w.clamp(0.5, 20),
            lengthFt: l.clamp(0.5, 20),
            wallLengthFt: wall.lengthFt(roomWidth, roomLength),
            confidence: conf,
            evidence: map['evidence']?.toString() ?? '',
          ));
          continue;
        }

        final pos = _parsePoint(map['pos'] ?? map['position']);
        final rotDeg = _asDouble(map['rot'] ?? map['rotation']) ?? 0;
        final posFt = pos ?? Offset(roomWidth / 2, roomLength / 2);
        freeFurniture.add(ScanFurnitureHint(
          type: type,
          posFt: Offset(
            posFt.dx.clamp(0, roomWidth),
            posFt.dy.clamp(0, roomLength),
          ),
          widthFt: w.clamp(0.5, 20),
          lengthFt: l.clamp(0.5, 20),
          rotationRad: rotDeg * pi / 180.0,
        ));
      }
    }

    // Wall-relative items → stable compose (designer method).
    if (wallOpenings.isNotEmpty || wallFurniture.isNotEmpty) {
      warnings.add(
        'Used wall-anchored layout '
        '(${wallFurniture.length} furniture, ${wallOpenings.length} openings)',
      );
      final composed = WallRelativeComposer.compose(
        widthFt: roomWidth,
        lengthFt: roomLength,
        openings: wallOpenings,
        furniture: wallFurniture,
        warnings: warnings,
        overviewPhotos: 1,
      );
      // Merge any freeform extras that didn't have wall tags.
      if (freeFurniture.isEmpty && freeWalls.isEmpty) {
        return composed;
      }
      return composed.copyWith(
        walls: [
          ...composed.walls.where((s) => s.type == StrokeType.wall),
          ...composed.walls.where((s) => s.type != StrokeType.wall),
          ...freeWalls,
        ],
        furniture: [...composed.furniture, ...freeFurniture],
      );
    }

    final outline = freeWalls.where((s) => s.type == StrokeType.wall).toList();
    final openingsOnly =
        freeWalls.where((s) => s.type != StrokeType.wall).toList();
    final walls = <ScanWallSegment>[
      if (outline.isEmpty) ...[
        ScanWallSegment(
          type: StrokeType.wall,
          startFt: Offset.zero,
          endFt: Offset(roomWidth, 0),
        ),
        ScanWallSegment(
          type: StrokeType.wall,
          startFt: Offset(roomWidth, 0),
          endFt: Offset(roomWidth, roomLength),
        ),
        ScanWallSegment(
          type: StrokeType.wall,
          startFt: Offset(roomWidth, roomLength),
          endFt: Offset(0, roomLength),
        ),
        ScanWallSegment(
          type: StrokeType.wall,
          startFt: Offset(0, roomLength),
          endFt: Offset.zero,
        ),
      ] else
        ...outline,
      ...openingsOnly,
    ];
    if (outline.isEmpty) {
      warnings.add(
        openingsOnly.isEmpty
            ? 'No walls detected — created rectangular outline'
            : 'Added rectangular outline around openings',
      );
    }

    return _normalize(
      ScanResult(
        roomWidthFt: roomWidth,
        roomLengthFt: roomLength,
        walls: walls,
        furniture: freeFurniture,
        warnings: warnings,
      ),
    );
  }

  static double mathMin(double a, double b) => a < b ? a : b;

  static WallSide? _parseWallSide(String? raw) {
    if (raw == null) return null;
    switch (raw.trim().toLowerCase()) {
      case 'south':
      case 'a':
      case 'wall_a':
      case 'bottom':
      case 'near':
        return WallSide.south;
      case 'east':
      case 'b':
      case 'wall_b':
      case 'right':
        return WallSide.east;
      case 'north':
      case 'c':
      case 'wall_c':
      case 'top':
      case 'far':
        return WallSide.north;
      case 'west':
      case 'd':
      case 'wall_d':
      case 'left':
        return WallSide.west;
      default:
        return null;
    }
  }

  /// Scale so a chosen wall segment matches [targetLengthFt].
  static ScanResult applyScaleCalibration(
    ScanResult result, {
    required int wallIndex,
    required double targetLengthFt,
  }) {
    if (wallIndex < 0 || wallIndex >= result.walls.length) return result;
    if (targetLengthFt <= 0) return result;

    final wall = result.walls[wallIndex];
    final current = wall.lengthFt;
    if (current < 0.01) return result;

    final factor = targetLengthFt / current;
    final walls = result.walls
        .map(
          (w) => ScanWallSegment(
            type: w.type,
            startFt: w.startFt * factor,
            endFt: w.endFt * factor,
          ),
        )
        .toList();
    final furniture = result.furniture
        .map(
          (f) => ScanFurnitureHint(
            type: f.type,
            posFt: f.posFt * factor,
            widthFt: f.widthFt * factor,
            lengthFt: f.lengthFt * factor,
            rotationRad: f.rotationRad,
            included: f.included,
          ),
        )
        .toList();

    return _normalize(
      ScanResult(
        roomWidthFt: result.roomWidthFt * factor,
        roomLengthFt: result.roomLengthFt * factor,
        walls: walls,
        furniture: furniture,
        warnings: [
          ...result.warnings,
          'Scale calibrated: wall ${wallIndex + 1} set to ${targetLengthFt.toStringAsFixed(1)} ft',
        ],
      ),
    );
  }

  /// Convert feet-space scan to editor strokes/furniture (pixel positions).
  ///
  /// +133: always inject a closed rectangle of wall strokes so the plan is never
  /// a broken open outline (feedback 225fb5de incomplete walls).
  static ({
    double width,
    double length,
    List<StrokeModel> strokes,
    List<FurnitureItem> furniture,
  }) toEditor(ScanResult result, double pixelsPerFoot) {
    final pxf = pixelsPerFoot <= 0 ? 20.0 : pixelsPerFoot;
    final w = result.roomWidthFt <= 0 ? 12.0 : result.roomWidthFt;
    final l = result.roomLengthFt <= 0 ? 12.0 : result.roomLengthFt;

    final openings = result.walls.where((s) => s.type != StrokeType.wall).map((seg) {
      return StrokeModel(
        id: _uuid.v4(),
        type: seg.type,
        points: [
          Offset(seg.startFt.dx * pxf, seg.startFt.dy * pxf),
          Offset(seg.endFt.dx * pxf, seg.endFt.dy * pxf),
        ],
      );
    }).toList();

    // Full closed perimeter (always)
    final perimeter = <StrokeModel>[
      StrokeModel(
        id: _uuid.v4(),
        type: StrokeType.wall,
        points: [Offset.zero, Offset(w * pxf, 0)],
      ),
      StrokeModel(
        id: _uuid.v4(),
        type: StrokeType.wall,
        points: [Offset(w * pxf, 0), Offset(w * pxf, l * pxf)],
      ),
      StrokeModel(
        id: _uuid.v4(),
        type: StrokeType.wall,
        points: [Offset(w * pxf, l * pxf), Offset(0, l * pxf)],
      ),
      StrokeModel(
        id: _uuid.v4(),
        type: StrokeType.wall,
        points: [Offset(0, l * pxf), Offset.zero],
      ),
    ];

    final furniture = result.furniture.where((f) => f.included).map((f) {
      return FurnitureItem(
        id: _uuid.v4(),
        type: f.type,
        position: Offset(f.posFt.dx * pxf, f.posFt.dy * pxf),
        widthInFeet: f.widthFt,
        lengthInFeet: f.lengthFt,
        rotationAngle: f.rotationRad,
      );
    }).toList();

    return (
      width: w,
      length: l,
      strokes: [...perimeter, ...openings],
      furniture: furniture,
    );
  }

  /// Reverse of [toEditor]: blueprint room (px) → scan plan (feet) (+110).
  ///
  /// Used so user-corrected editor geometry can become Phase B gold reference.
  static ScanResult fromEditor({
    required double widthFt,
    required double lengthFt,
    required List<StrokeModel> strokes,
    required List<FurnitureItem> furniture,
    required double pixelsPerFoot,
    List<String> warnings = const [],
    double? accuracyScore,
  }) {
    final pxf = pixelsPerFoot <= 0 ? 1.0 : pixelsPerFoot;
    final walls = <ScanWallSegment>[];
    for (final s in strokes) {
      if (s.type == StrokeType.wall) continue;
      if (s.points.length < 2) continue;
      walls.add(ScanWallSegment(
        type: s.type,
        startFt: Offset(s.points.first.dx / pxf, s.points.first.dy / pxf),
        endFt: Offset(s.points.last.dx / pxf, s.points.last.dy / pxf),
      ));
    }
    final furn = furniture.map((f) {
      return ScanFurnitureHint(
        type: f.type,
        posFt: Offset(f.position.dx / pxf, f.position.dy / pxf),
        widthFt: f.widthInFeet,
        lengthFt: f.lengthInFeet,
        rotationRad: f.rotationAngle,
        included: true,
      );
    }).toList();
    return ScanResult(
      roomWidthFt: widthFt,
      roomLengthFt: lengthFt,
      walls: walls,
      furniture: furn,
      warnings: [
        ...warnings,
        'User-corrected plan from editor (+110)',
      ],
      accuracyScore: accuracyScore ?? 0.95,
    );
  }

  static ScanResult _normalize(ScanResult r) {
    if (r.walls.isEmpty) return r;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final w in r.walls) {
      minX = min(minX, min(w.startFt.dx, w.endFt.dx));
      minY = min(minY, min(w.startFt.dy, w.endFt.dy));
      maxX = max(maxX, max(w.startFt.dx, w.endFt.dx));
      maxY = max(maxY, max(w.startFt.dy, w.endFt.dy));
    }
    // Shift to origin with small padding
    final ox = minX;
    final oy = minY;
    final walls = r.walls
        .map(
          (w) => ScanWallSegment(
            type: w.type,
            startFt: Offset(w.startFt.dx - ox, w.startFt.dy - oy),
            endFt: Offset(w.endFt.dx - ox, w.endFt.dy - oy),
          ),
        )
        .toList();
    final furniture = r.furniture
        .map(
          (f) => ScanFurnitureHint(
            type: f.type,
            posFt: Offset(f.posFt.dx - ox, f.posFt.dy - oy),
            widthFt: f.widthFt,
            lengthFt: f.lengthFt,
            rotationRad: f.rotationRad,
            included: f.included,
          ),
        )
        .toList();

    // Keep declared room size — do not inflate from wall extents (AI often
    // draws walls slightly past the room). AccurateScan.enforce will rebuild
    // a clean rectangle at the user-measured size.
    return ScanResult(
      roomWidthFt: r.roomWidthFt,
      roomLengthFt: r.roomLengthFt,
      walls: walls,
      furniture: furniture,
      warnings: r.warnings,
    );
  }

  static StrokeType _parseStrokeType(String? raw) {
    switch ((raw ?? 'wall').toLowerCase()) {
      case 'door':
        return StrokeType.door;
      case 'window':
        return StrokeType.window;
      case 'balcony':
        return StrokeType.balcony;
      default:
        return StrokeType.wall;
    }
  }

  static FurnitureType? _parseFurnitureType(String? raw) {
    if (raw == null) return null;
    final key = raw.trim().toUpperCase().replaceAll(' ', '_').replaceAll('-', '_');
    if (_furnitureAliases.containsKey(key)) return _furnitureAliases[key];
    // camelCase enum names
    for (final t in FurnitureType.values) {
      if (t.name.toUpperCase() == key.replaceAll('_', '')) return t;
      if (t.name.toUpperCase() == key) return t;
    }
    return null;
  }

  static Offset? _parsePoint(dynamic raw) {
    if (raw is! Map) return null;
    final x = _asDouble(raw['x'] ?? raw['dx']);
    final y = _asDouble(raw['y'] ?? raw['dy']);
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
