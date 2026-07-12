import 'dart:math';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';

/// Parses / validates / normalizes AI JSON and applies scale calibration.
class ScanParser {
  static const _uuid = Uuid();

  static const Map<String, FurnitureType> _furnitureAliases = {
    'BED': FurnitureType.bed,
    'WARDROBE': FurnitureType.wardrobe,
    'SOFA': FurnitureType.sofa,
    'TABLE': FurnitureType.table,
    'CHAIR': FurnitureType.chair,
    'TV_UNIT': FurnitureType.tvUnit,
    'TVUNIT': FurnitureType.tvUnit,
    'TV': FurnitureType.tvUnit,
    'BOOKSHELF': FurnitureType.bookshelf,
    'NIGHTSTAND': FurnitureType.nightstand,
    'NIGHT_STAND': FurnitureType.nightstand,
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

    final walls = <ScanWallSegment>[];
    final wallsRaw = raw['walls'];
    if (wallsRaw is List) {
      for (final item in wallsRaw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final type = _parseStrokeType(map['type']?.toString());
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
        walls.add(ScanWallSegment(type: type, startFt: start, endFt: end));
      }
    }

    if (walls.isEmpty) {
      // Synthesize a rectangular room outline so user still gets a plan.
      warnings.add('No walls detected — created rectangular outline');
      walls.addAll([
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
      ]);
    }

    final furniture = <ScanFurnitureHint>[];
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
        final pos = _parsePoint(map['pos'] ?? map['position']);
        final dim = map['dim'] ?? map['size'];
        double? w;
        double? l;
        if (dim is Map) {
          w = _asDouble(dim['w'] ?? dim['width']);
          l = _asDouble(dim['l'] ?? dim['length'] ?? dim['h']);
        }
        w ??= 3.0;
        l ??= 3.0;
        final rotDeg = _asDouble(map['rot'] ?? map['rotation']) ?? 0;
        final posFt = pos ?? Offset(roomWidth / 2, roomLength / 2);
        // Clamp into room
        final clamped = Offset(
          posFt.dx.clamp(0, roomWidth),
          posFt.dy.clamp(0, roomLength),
        );
        furniture.add(ScanFurnitureHint(
          type: type,
          posFt: clamped,
          widthFt: w.clamp(0.5, 20),
          lengthFt: l.clamp(0.5, 20),
          rotationRad: rotDeg * pi / 180.0,
        ));
      }
    }

    // Normalize so min corner is near origin
    return _normalize(
      ScanResult(
        roomWidthFt: roomWidth,
        roomLengthFt: roomLength,
        walls: walls,
        furniture: furniture,
        warnings: warnings,
      ),
    );
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
  static ({
    double width,
    double length,
    List<StrokeModel> strokes,
    List<FurnitureItem> furniture,
  }) toEditor(ScanResult result, double pixelsPerFoot) {
    final strokes = result.walls.map((w) {
      return StrokeModel(
        id: _uuid.v4(),
        type: w.type,
        points: [
          Offset(w.startFt.dx * pixelsPerFoot, w.startFt.dy * pixelsPerFoot),
          Offset(w.endFt.dx * pixelsPerFoot, w.endFt.dy * pixelsPerFoot),
        ],
      );
    }).toList();

    final furniture = result.furniture.where((f) => f.included).map((f) {
      return FurnitureItem(
        id: _uuid.v4(),
        type: f.type,
        position: Offset(f.posFt.dx * pixelsPerFoot, f.posFt.dy * pixelsPerFoot),
        widthInFeet: f.widthFt,
        lengthInFeet: f.lengthFt,
        rotationAngle: f.rotationRad,
      );
    }).toList();

    return (
      width: result.roomWidthFt,
      length: result.roomLengthFt,
      strokes: strokes,
      furniture: furniture,
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
