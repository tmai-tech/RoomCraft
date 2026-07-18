import 'package:flutter/material.dart';

/// Core furniture kinds used for drawing, collision, and AI parse.
/// Catalog SKUs map onto these (many SKUs share a type).
enum FurnitureType {
  bed,
  wardrobe,
  sofa,
  table,
  chair,
  tvUnit,
  bookshelf,
  nightstand,
  // Planner-scale expansion
  desk,
  dresser,
  rug,
  plant,
  lamp,
  appliance,
  vanity,
  bathtub,
  toilet,
  outdoor,
}

class FurnitureItem {
  final String id;
  final FurnitureType type;
  final Offset position;
  final double rotationAngle; // radians
  final double widthInFeet;
  final double lengthInFeet;
  /// Optional catalog SKU id (e.g. queen_bed) for richer labels/3D.
  final String? catalogId;

  const FurnitureItem({
    required this.id,
    required this.type,
    required this.position,
    this.rotationAngle = 0.0,
    required this.widthInFeet,
    required this.lengthInFeet,
    this.catalogId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'position': {'dx': position.dx, 'dy': position.dy},
      'rotationAngle': rotationAngle,
      'widthInFeet': widthInFeet,
      'lengthInFeet': lengthInFeet,
      if (catalogId != null) 'catalogId': catalogId,
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
      catalogId: map['catalogId'] as String?,
    );
  }

  FurnitureItem copyWith({
    Offset? position,
    double? rotationAngle,
    double? widthInFeet,
    double? lengthInFeet,
    String? catalogId,
  }) {
    return FurnitureItem(
      id: id,
      type: type,
      position: position ?? this.position,
      rotationAngle: rotationAngle ?? this.rotationAngle,
      widthInFeet: widthInFeet ?? this.widthInFeet,
      lengthInFeet: lengthInFeet ?? this.lengthInFeet,
      catalogId: catalogId ?? this.catalogId,
    );
  }
}

extension FurnitureTypeVisual on FurnitureType {
  /// Default extruded height in feet for isometric 3D.
  double get defaultHeightFt {
    switch (this) {
      case FurnitureType.bed:
        return 2.2;
      case FurnitureType.wardrobe:
      case FurnitureType.dresser:
        return 6.5;
      case FurnitureType.sofa:
        return 2.8;
      case FurnitureType.table:
        return 2.5;
      case FurnitureType.desk:
        return 2.5;
      case FurnitureType.chair:
        return 3.0;
      case FurnitureType.tvUnit:
        return 2.0;
      case FurnitureType.bookshelf:
        return 6.0;
      case FurnitureType.nightstand:
        return 2.0;
      case FurnitureType.rug:
        return 0.15;
      case FurnitureType.plant:
        return 3.5;
      case FurnitureType.lamp:
        return 5.0;
      case FurnitureType.appliance:
        return 3.0;
      case FurnitureType.vanity:
        return 3.0;
      case FurnitureType.bathtub:
        return 2.0;
      case FurnitureType.toilet:
        return 2.5;
      case FurnitureType.outdoor:
        return 2.5;
    }
  }

  Color get planColor {
    switch (this) {
      case FurnitureType.bed:
        return const Color(0xFFBBDEFB);
      case FurnitureType.sofa:
        return const Color(0xFFB2DFDB);
      case FurnitureType.table:
      case FurnitureType.desk:
        return const Color(0xFFBCAAA4);
      case FurnitureType.chair:
        return const Color(0xFFA1887F);
      case FurnitureType.wardrobe:
      case FurnitureType.dresser:
        return const Color(0xFF8D6E63);
      case FurnitureType.tvUnit:
        return const Color(0xFFBDBDBD);
      case FurnitureType.bookshelf:
        return const Color(0xFFFFCC80);
      case FurnitureType.nightstand:
        return const Color(0xFFD7CCC8);
      case FurnitureType.rug:
        return const Color(0xFFE1BEE7);
      case FurnitureType.plant:
        return const Color(0xFFA5D6A7);
      case FurnitureType.lamp:
        return const Color(0xFFFFF59D);
      case FurnitureType.appliance:
        return const Color(0xFF90A4AE);
      case FurnitureType.vanity:
        return const Color(0xFFB3E5FC);
      case FurnitureType.bathtub:
        return const Color(0xFFB2EBF2);
      case FurnitureType.toilet:
        return const Color(0xFFE0E0E0);
      case FurnitureType.outdoor:
        return const Color(0xFFC5E1A5);
    }
  }

  String get shortLabel {
    switch (this) {
      case FurnitureType.bed:
        return 'Bed';
      case FurnitureType.wardrobe:
        return 'Wardrobe';
      case FurnitureType.sofa:
        return 'Sofa';
      case FurnitureType.table:
        return 'Table';
      case FurnitureType.chair:
        return 'Chair';
      case FurnitureType.tvUnit:
        return 'TV';
      case FurnitureType.bookshelf:
        return 'Shelf';
      case FurnitureType.nightstand:
        return 'Nightstand';
      case FurnitureType.desk:
        return 'Desk';
      case FurnitureType.dresser:
        return 'Dresser';
      case FurnitureType.rug:
        return 'Rug';
      case FurnitureType.plant:
        return 'Plant';
      case FurnitureType.lamp:
        return 'Lamp';
      case FurnitureType.appliance:
        return 'Appliance';
      case FurnitureType.vanity:
        return 'Vanity';
      case FurnitureType.bathtub:
        return 'Bath';
      case FurnitureType.toilet:
        return 'Toilet';
      case FurnitureType.outdoor:
        return 'Outdoor';
    }
  }
}
