import 'package:flutter/material.dart';

enum FurnitureType { bed, wardrobe, sofa, table, chair, tvUnit, bookshelf, nightstand }

class FurnitureItem {
  final String id;
  final FurnitureType type;
  final Offset position;
  final double rotationAngle; // radians
  final double widthInFeet;
  final double lengthInFeet;

  const FurnitureItem({
    required this.id,
    required this.type,
    required this.position,
    this.rotationAngle = 0.0,
    required this.widthInFeet,
    required this.lengthInFeet,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'position': {'dx': position.dx, 'dy': position.dy},
      'rotationAngle': rotationAngle,
      'widthInFeet': widthInFeet,
      'lengthInFeet': lengthInFeet,
    };
  }

  factory FurnitureItem.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String? ?? 'table';
    final type = FurnitureType.values.firstWhere(
      (e) => e.name == typeName || e.name.toUpperCase() == typeName.toUpperCase(),
      orElse: () => FurnitureType.table,
    );
    final pos = map['position'];
    double dx = 0;
    double dy = 0;
    if (pos is Map) {
      dx = (pos['dx'] as num?)?.toDouble() ?? 0;
      dy = (pos['dy'] as num?)?.toDouble() ?? 0;
    }
    return FurnitureItem(
      id: map['id'] as String? ?? UniqueKey().toString(),
      type: type,
      position: Offset(dx, dy),
      rotationAngle: (map['rotationAngle'] as num?)?.toDouble() ?? 0.0,
      widthInFeet: (map['widthInFeet'] as num?)?.toDouble() ?? 3.0,
      lengthInFeet: (map['lengthInFeet'] as num?)?.toDouble() ?? 3.0,
    );
  }

  FurnitureItem copyWith({
    Offset? position,
    double? rotationAngle,
    double? widthInFeet,
    double? lengthInFeet,
  }) {
    return FurnitureItem(
      id: id,
      type: type,
      position: position ?? this.position,
      rotationAngle: rotationAngle ?? this.rotationAngle,
      widthInFeet: widthInFeet ?? this.widthInFeet,
      lengthInFeet: lengthInFeet ?? this.lengthInFeet,
    );
  }
}
