import 'package:flutter/material.dart';

enum FurnitureType { bed, wardrobe, sofa, table, chair, tvUnit, bookshelf, nightstand }

class FurnitureItem {
  final String id;
  final FurnitureType type;
  Offset position;
  double rotationAngle; // in radians
  final double widthInFeet;
  final double lengthInFeet;

  FurnitureItem({
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
    return FurnitureItem(
      id: map['id'],
      type: FurnitureType.values.firstWhere((e) => e.name == map['type']),
      position: Offset(map['position']['dx'], map['position']['dy']),
      rotationAngle: map['rotationAngle'] ?? 0.0,
      widthInFeet: map['widthInFeet'],
      lengthInFeet: map['lengthInFeet'],
    );
  }
}
