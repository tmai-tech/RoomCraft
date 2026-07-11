import 'package:flutter/material.dart';

import 'furniture_item.dart';
import 'stroke_model.dart';

/// Validated photo → top-view scan (geometry in feet until converted to pixels).
class ScanWallSegment {
  final StrokeType type;
  final Offset startFt;
  final Offset endFt;

  const ScanWallSegment({
    required this.type,
    required this.startFt,
    required this.endFt,
  });

  double get lengthFt => (endFt - startFt).distance;
}

class ScanFurnitureHint {
  final FurnitureType type;
  final Offset posFt;
  final double widthFt;
  final double lengthFt;
  final double rotationRad;
  final bool included;

  const ScanFurnitureHint({
    required this.type,
    required this.posFt,
    required this.widthFt,
    required this.lengthFt,
    this.rotationRad = 0,
    this.included = true,
  });

  ScanFurnitureHint copyWith({bool? included}) {
    return ScanFurnitureHint(
      type: type,
      posFt: posFt,
      widthFt: widthFt,
      lengthFt: lengthFt,
      rotationRad: rotationRad,
      included: included ?? this.included,
    );
  }
}

class ScanResult {
  final double roomWidthFt;
  final double roomLengthFt;
  final List<ScanWallSegment> walls;
  final List<ScanFurnitureHint> furniture;
  final List<String> warnings;

  const ScanResult({
    required this.roomWidthFt,
    required this.roomLengthFt,
    required this.walls,
    required this.furniture,
    this.warnings = const [],
  });

  ScanResult copyWith({
    double? roomWidthFt,
    double? roomLengthFt,
    List<ScanWallSegment>? walls,
    List<ScanFurnitureHint>? furniture,
    List<String>? warnings,
  }) {
    return ScanResult(
      roomWidthFt: roomWidthFt ?? this.roomWidthFt,
      roomLengthFt: roomLengthFt ?? this.roomLengthFt,
      walls: walls ?? this.walls,
      furniture: furniture ?? this.furniture,
      warnings: warnings ?? this.warnings,
    );
  }
}
