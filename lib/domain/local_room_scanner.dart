import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/room_model.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'layout/auto_arrange.dart';

/// Free offline room plan builder (no cloud vision).
///
/// **Proportions:** uses exact [roomWidthFt] × [roomLengthFt] when provided.
/// Never warps true measurements by photo aspect ratio.
/// **Furniture:** empty by default — only places preset pieces when the user
/// explicitly chooses a non-empty [preferredLayout].
class LocalRoomScanner {
  /// Build a [ScanResult] from photos without network AI.
  static Future<ScanResult> scan({
    required List<File> images,
    Map<File, double>? wallMeasurementsFt,
    RoomLayoutType? preferredLayout,
    double? roomWidthFt,
    double? roomLengthFt,
  }) async {
    if (images.isEmpty) {
      throw Exception('Add at least one room photo.');
    }

    final warnings = <String>[
      'Free offline plan — proportions from your room size. '
          'No furniture invented unless you pick a preset.',
    ];

    // Photo metadata only for diagnostics (not for warping dimensions).
    try {
      final bytes = await images.first.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final aspect = decoded.width / math.max(decoded.height, 1);
        warnings.add(
          'Photo ${decoded.width}×${decoded.height} · aspect ${aspect.toStringAsFixed(2)} (not used for size)',
        );
      }
    } catch (_) {
      warnings.add('Could not fully decode photo — plan still uses your room size');
    }

    final dims = resolveDimensions(
      roomWidthFt: roomWidthFt,
      roomLengthFt: roomLengthFt,
      wallMeasurementsFt: wallMeasurementsFt,
    );
    final widthFt = dims.widthFt;
    final lengthFt = dims.lengthFt;
    warnings.addAll(dims.notes);

    final walls = <ScanWallSegment>[
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset.zero,
        endFt: Offset(widthFt, 0),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(widthFt, 0),
        endFt: Offset(widthFt, lengthFt),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(widthFt, lengthFt),
        endFt: Offset(0, lengthFt),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(0, lengthFt),
        endFt: Offset.zero,
      ),
      // Generic door/window placeholders on the outline (not furniture).
      ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(widthFt * 0.35, 0),
        endFt: Offset(widthFt * 0.35 + math.min(3.0, widthFt * 0.25), 0),
      ),
      ScanWallSegment(
        type: StrokeType.window,
        startFt: Offset(widthFt * 0.25, lengthFt),
        endFt: Offset(widthFt * 0.55, lengthFt),
      ),
    ];

    final type = preferredLayout ?? RoomLayoutType.empty;
    final furniture = <ScanFurnitureHint>[];

    if (type != RoomLayoutType.empty) {
      warnings.add(
        'Preset furniture: ${AutoArrange.label(type)} '
        '(not from photo — switch to Empty or free AI for real items)',
      );
      const pxf = 20.0;
      final room = RoomModel(
        id: 'local-scan',
        name: 'Local scan',
        widthInFeet: widthFt,
        lengthInFeet: lengthFt,
      );
      final placed = AutoArrange.arrange(
        room: room,
        pixelsPerFoot: pxf,
        type: type,
      );
      furniture.addAll(
        placed.map(
          (f) => ScanFurnitureHint(
            type: f.type,
            posFt: Offset(f.position.dx / pxf, f.position.dy / pxf),
            widthFt: f.widthInFeet,
            lengthFt: f.lengthInFeet,
            rotationRad: f.rotationAngle,
            included: true,
          ),
        ),
      );
    } else {
      warnings.add(
        'Empty plan — add furniture from the catalog or enable free AI detection',
      );
    }

    return ScanResult(
      roomWidthFt: widthFt,
      roomLengthFt: lengthFt,
      walls: walls,
      furniture: furniture,
      warnings: warnings,
    );
  }

  /// Resolve exact width × length in feet.
  ///
  /// Priority:
  /// 1. Explicit [roomWidthFt] / [roomLengthFt]
  /// 2. Two+ wall measurements → first = width, second = length
  /// 3. One measurement → square room of that size
  /// 4. Default 10×10 (common square room, not photo aspect)
  static ({double widthFt, double lengthFt, List<String> notes}) resolveDimensions({
    double? roomWidthFt,
    double? roomLengthFt,
    Map<File, double>? wallMeasurementsFt,
  }) {
    final notes = <String>[];

    double? w = roomWidthFt;
    double? l = roomLengthFt;

    if ((w == null || w <= 0) || (l == null || l <= 0)) {
      final values = wallMeasurementsFt?.values
              .where((v) => v > 0)
              .toList() ??
          const <double>[];
      if (values.length >= 2) {
        w ??= values[0];
        l ??= values[1];
        notes.add(
          'Size from wall lengths: ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft',
        );
      } else if (values.length == 1) {
        w ??= values.first;
        l ??= values.first;
        notes.add(
          'One wall length (${values.first.toStringAsFixed(1)} ft) → square room',
        );
      }
    } else {
      notes.add(
        'Exact room size: ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft',
      );
    }

    w ??= 10.0;
    l ??= 10.0;
    if (roomWidthFt == null && roomLengthFt == null &&
        (wallMeasurementsFt == null || wallMeasurementsFt.isEmpty)) {
      notes.add('No size entered — default 10 × 10 ft square (edit in review)');
    }

    // Soft sanity only — do not distort proportions.
    if (w < 3 || l < 3) {
      notes.add('Room sides under 3 ft look too small — check units');
    }
    if (w > 80 || l > 80) {
      notes.add('Room sides over 80 ft look very large — check units');
    }

    return (widthFt: w, lengthFt: l, notes: notes);
  }
}
