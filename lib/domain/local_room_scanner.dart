import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/room_model.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'layout/auto_arrange.dart';

/// Free, offline room plan estimator (no Gemini / no paid API).
///
/// Uses photo aspect ratio, optional wall measurements, and open-source
/// AutoArrange packing — similar spirit to Sweet Home 3D 2D planning,
/// without cloud vision models.
class LocalRoomScanner {
  /// Build a [ScanResult] from photos without network AI.
  static Future<ScanResult> scan({
    required List<File> images,
    Map<File, double>? wallMeasurementsFt,
    RoomLayoutType? preferredLayout,
  }) async {
    if (images.isEmpty) {
      throw Exception('Add at least one room photo.');
    }

    final warnings = <String>[
      'Free offline scan (no API key). Estimate only — edit walls & furniture next.',
    ];

    double aspect = 1.25;
    double avgLuma = 0.5;
    try {
      final bytes = await images.first.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        aspect = decoded.width / math.max(decoded.height, 1);
        var sum = 0.0;
        var n = 0;
        final stepX = math.max(1, decoded.width ~/ 32);
        final stepY = math.max(1, decoded.height ~/ 32);
        for (var y = 0; y < decoded.height; y += stepY) {
          for (var x = 0; x < decoded.width; x += stepX) {
            final p = decoded.getPixel(x, y);
            sum += (p.r * 0.299 + p.g * 0.587 + p.b * 0.114) / 255.0;
            n++;
          }
        }
        if (n > 0) avgLuma = sum / n;
        warnings.add(
          'Photo ${decoded.width}×${decoded.height} · aspect ${aspect.toStringAsFixed(2)}',
        );
      }
    } catch (_) {
      warnings.add('Could not fully decode photo — used default proportions');
    }

    double? measured;
    if (wallMeasurementsFt != null && wallMeasurementsFt.isNotEmpty) {
      measured = wallMeasurementsFt.values.reduce((a, b) => a + b) /
          wallMeasurementsFt.length;
      warnings.add(
        'Scale from ${wallMeasurementsFt.length} measurement(s): '
        'avg ${measured.toStringAsFixed(1)} ft',
      );
    }

    late double widthFt;
    late double lengthFt;
    if (measured != null && measured > 0) {
      if (aspect >= 1) {
        widthFt = measured;
        lengthFt = measured / aspect;
      } else {
        lengthFt = measured;
        widthFt = measured * aspect;
      }
    } else {
      widthFt = 12.0 * math.sqrt(aspect.clamp(0.5, 2.0));
      lengthFt = 12.0 / math.sqrt(aspect.clamp(0.5, 2.0));
      warnings.add('No wall length entered — used typical ~12 ft base size');
    }

    widthFt = widthFt.clamp(6.0, 40.0);
    lengthFt = lengthFt.clamp(6.0, 40.0);

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
      ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(widthFt * 0.35, 0),
        endFt: Offset(widthFt * 0.35 + 3.0, 0),
      ),
      ScanWallSegment(
        type: StrokeType.window,
        startFt: Offset(widthFt * 0.25, lengthFt),
        endFt: Offset(widthFt * 0.55, lengthFt),
      ),
    ];

    var type = preferredLayout ?? RoomLayoutType.living;
    if (preferredLayout == null) {
      if (avgLuma > 0.55 && widthFt * lengthFt > 140) {
        type = RoomLayoutType.living;
      } else if (avgLuma < 0.4 || widthFt * lengthFt < 120) {
        type = RoomLayoutType.bedroom;
      } else {
        type = RoomLayoutType.office;
      }
    }
    warnings.add('Preset furniture: ${AutoArrange.label(type)}');

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

    final furniture = placed
        .map(
          (f) => ScanFurnitureHint(
            type: f.type,
            posFt: Offset(f.position.dx / pxf, f.position.dy / pxf),
            widthFt: f.widthInFeet,
            lengthFt: f.lengthInFeet,
            rotationRad: f.rotationAngle,
            included: true,
          ),
        )
        .toList();

    return ScanResult(
      roomWidthFt: widthFt,
      roomLengthFt: lengthFt,
      walls: walls,
      furniture: furniture,
      warnings: warnings,
    );
  }
}
