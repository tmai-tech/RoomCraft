import 'package:flutter/material.dart';

import '../models/furniture_item.dart';

enum FurnitureCategory { sleep, seating, tables, storage, media }

class FurnitureCatalogEntry {
  final FurnitureType type;
  final String label;
  final FurnitureCategory category;
  final IconData icon;
  final double defaultWidthFt;
  final double defaultLengthFt;
  final String description;

  const FurnitureCatalogEntry({
    required this.type,
    required this.label,
    required this.category,
    required this.icon,
    required this.defaultWidthFt,
    required this.defaultLengthFt,
    required this.description,
  });
}

/// Built-in furniture definitions (top-down sizes in feet).
class FurnitureCatalog {
  static const List<FurnitureCatalogEntry> all = [
    FurnitureCatalogEntry(
      type: FurnitureType.bed,
      label: 'Bed',
      category: FurnitureCategory.sleep,
      icon: Icons.bed,
      defaultWidthFt: 5.0,
      defaultLengthFt: 6.5,
      description: 'Queen-size bed',
    ),
    FurnitureCatalogEntry(
      type: FurnitureType.nightstand,
      label: 'Nightstand',
      category: FurnitureCategory.sleep,
      icon: Icons.table_restaurant,
      defaultWidthFt: 1.5,
      defaultLengthFt: 1.5,
      description: 'Bedside table',
    ),
    FurnitureCatalogEntry(
      type: FurnitureType.sofa,
      label: 'Sofa',
      category: FurnitureCategory.seating,
      icon: Icons.weekend,
      defaultWidthFt: 6.0,
      defaultLengthFt: 3.0,
      description: '3-seater sofa',
    ),
    FurnitureCatalogEntry(
      type: FurnitureType.chair,
      label: 'Chair',
      category: FurnitureCategory.seating,
      icon: Icons.chair,
      defaultWidthFt: 1.8,
      defaultLengthFt: 1.8,
      description: 'Dining / desk chair',
    ),
    FurnitureCatalogEntry(
      type: FurnitureType.table,
      label: 'Table',
      category: FurnitureCategory.tables,
      icon: Icons.table_bar,
      defaultWidthFt: 4.0,
      defaultLengthFt: 4.0,
      description: 'Dining or coffee table',
    ),
    FurnitureCatalogEntry(
      type: FurnitureType.wardrobe,
      label: 'Wardrobe',
      category: FurnitureCategory.storage,
      icon: Icons.door_sliding,
      defaultWidthFt: 4.0,
      defaultLengthFt: 2.0,
      description: 'Closet / wardrobe',
    ),
    FurnitureCatalogEntry(
      type: FurnitureType.bookshelf,
      label: 'Bookshelf',
      category: FurnitureCategory.storage,
      icon: Icons.menu_book,
      defaultWidthFt: 3.0,
      defaultLengthFt: 1.0,
      description: 'Bookcase',
    ),
    FurnitureCatalogEntry(
      type: FurnitureType.tvUnit,
      label: 'TV Unit',
      category: FurnitureCategory.media,
      icon: Icons.tv,
      defaultWidthFt: 5.0,
      defaultLengthFt: 1.5,
      description: 'TV stand / media console',
    ),
  ];

  static FurnitureCatalogEntry entryFor(FurnitureType type) {
    return all.firstWhere(
      (e) => e.type == type,
      orElse: () => all.first,
    );
  }

  static List<FurnitureCatalogEntry> byCategory(FurnitureCategory c) {
    return all.where((e) => e.category == c).toList();
  }

  static String categoryLabel(FurnitureCategory c) {
    switch (c) {
      case FurnitureCategory.sleep:
        return 'Sleep';
      case FurnitureCategory.seating:
        return 'Seating';
      case FurnitureCategory.tables:
        return 'Tables';
      case FurnitureCategory.storage:
        return 'Storage';
      case FurnitureCategory.media:
        return 'Media';
    }
  }
}
