import 'package:flutter/material.dart';

import '../models/furniture_item.dart';

enum FurnitureCategory { sleep, seating, tables, storage, media, outdoor }

class FurnitureCatalogEntry {
  /// Unique catalog id (e.g. queen_bed) — type is used for drawing/AI.
  final String id;
  final FurnitureType type;
  final String label;
  final FurnitureCategory category;
  final IconData icon;
  final double defaultWidthFt;
  final double defaultLengthFt;
  final String description;

  const FurnitureCatalogEntry({
    required this.id,
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
/// ~40 SKUs for daily planning — variants share [FurnitureType] for painters.
class FurnitureCatalog {
  static const List<FurnitureCatalogEntry> all = [
    // —— Sleep ——
    FurnitureCatalogEntry(
      id: 'twin_bed',
      type: FurnitureType.bed,
      label: 'Twin bed',
      category: FurnitureCategory.sleep,
      icon: Icons.bed,
      defaultWidthFt: 3.2,
      defaultLengthFt: 6.3,
      description: 'Single / twin mattress',
    ),
    FurnitureCatalogEntry(
      id: 'full_bed',
      type: FurnitureType.bed,
      label: 'Full bed',
      category: FurnitureCategory.sleep,
      icon: Icons.bed,
      defaultWidthFt: 4.5,
      defaultLengthFt: 6.3,
      description: 'Full / double',
    ),
    FurnitureCatalogEntry(
      id: 'queen_bed',
      type: FurnitureType.bed,
      label: 'Queen bed',
      category: FurnitureCategory.sleep,
      icon: Icons.bed,
      defaultWidthFt: 5.0,
      defaultLengthFt: 6.7,
      description: 'Queen-size bed',
    ),
    FurnitureCatalogEntry(
      id: 'king_bed',
      type: FurnitureType.bed,
      label: 'King bed',
      category: FurnitureCategory.sleep,
      icon: Icons.bed,
      defaultWidthFt: 6.3,
      defaultLengthFt: 6.7,
      description: 'King-size bed',
    ),
    FurnitureCatalogEntry(
      id: 'nightstand',
      type: FurnitureType.nightstand,
      label: 'Nightstand',
      category: FurnitureCategory.sleep,
      icon: Icons.table_restaurant,
      defaultWidthFt: 1.5,
      defaultLengthFt: 1.5,
      description: 'Bedside table',
    ),
    FurnitureCatalogEntry(
      id: 'nightstand_wide',
      type: FurnitureType.nightstand,
      label: 'Wide nightstand',
      category: FurnitureCategory.sleep,
      icon: Icons.table_restaurant,
      defaultWidthFt: 2.0,
      defaultLengthFt: 1.6,
      description: 'Larger bedside',
    ),
    // —— Seating ——
    FurnitureCatalogEntry(
      id: 'sofa_3',
      type: FurnitureType.sofa,
      label: 'Sofa 3-seat',
      category: FurnitureCategory.seating,
      icon: Icons.weekend,
      defaultWidthFt: 7.0,
      defaultLengthFt: 3.0,
      description: 'Standard sofa',
    ),
    FurnitureCatalogEntry(
      id: 'sofa_2',
      type: FurnitureType.sofa,
      label: 'Loveseat',
      category: FurnitureCategory.seating,
      icon: Icons.weekend,
      defaultWidthFt: 5.0,
      defaultLengthFt: 3.0,
      description: '2-seater sofa',
    ),
    FurnitureCatalogEntry(
      id: 'sectional',
      type: FurnitureType.sofa,
      label: 'Sectional (L)',
      category: FurnitureCategory.seating,
      icon: Icons.weekend,
      defaultWidthFt: 8.5,
      defaultLengthFt: 6.5,
      description: 'L-shaped sectional footprint',
    ),
    FurnitureCatalogEntry(
      id: 'armchair',
      type: FurnitureType.chair,
      label: 'Armchair',
      category: FurnitureCategory.seating,
      icon: Icons.chair,
      defaultWidthFt: 2.8,
      defaultLengthFt: 2.8,
      description: 'Lounge armchair',
    ),
    FurnitureCatalogEntry(
      id: 'dining_chair',
      type: FurnitureType.chair,
      label: 'Dining chair',
      category: FurnitureCategory.seating,
      icon: Icons.chair,
      defaultWidthFt: 1.6,
      defaultLengthFt: 1.6,
      description: 'Dining chair',
    ),
    FurnitureCatalogEntry(
      id: 'office_chair',
      type: FurnitureType.chair,
      label: 'Office chair',
      category: FurnitureCategory.seating,
      icon: Icons.chair_alt,
      defaultWidthFt: 2.0,
      defaultLengthFt: 2.0,
      description: 'Desk chair',
    ),
    FurnitureCatalogEntry(
      id: 'stool',
      type: FurnitureType.chair,
      label: 'Stool',
      category: FurnitureCategory.seating,
      icon: Icons.event_seat,
      defaultWidthFt: 1.2,
      defaultLengthFt: 1.2,
      description: 'Bar / side stool',
    ),
    FurnitureCatalogEntry(
      id: 'ottoman',
      type: FurnitureType.chair,
      label: 'Ottoman',
      category: FurnitureCategory.seating,
      icon: Icons.crop_square,
      defaultWidthFt: 2.0,
      defaultLengthFt: 2.0,
      description: 'Footstool / ottoman',
    ),
    FurnitureCatalogEntry(
      id: 'bench',
      type: FurnitureType.chair,
      label: 'Bench',
      category: FurnitureCategory.seating,
      icon: Icons.weekend_outlined,
      defaultWidthFt: 4.0,
      defaultLengthFt: 1.5,
      description: 'Entry or dining bench',
    ),
    // —— Tables ——
    FurnitureCatalogEntry(
      id: 'coffee_table',
      type: FurnitureType.table,
      label: 'Coffee table',
      category: FurnitureCategory.tables,
      icon: Icons.table_bar,
      defaultWidthFt: 3.5,
      defaultLengthFt: 2.0,
      description: 'Living room coffee table',
    ),
    FurnitureCatalogEntry(
      id: 'dining_table_4',
      type: FurnitureType.table,
      label: 'Dining table (4)',
      category: FurnitureCategory.tables,
      icon: Icons.table_restaurant,
      defaultWidthFt: 4.0,
      defaultLengthFt: 3.0,
      description: '4-person dining',
    ),
    FurnitureCatalogEntry(
      id: 'dining_table_6',
      type: FurnitureType.table,
      label: 'Dining table (6)',
      category: FurnitureCategory.tables,
      icon: Icons.table_restaurant,
      defaultWidthFt: 5.5,
      defaultLengthFt: 3.2,
      description: '6-person dining',
    ),
    FurnitureCatalogEntry(
      id: 'desk',
      type: FurnitureType.table,
      label: 'Desk',
      category: FurnitureCategory.tables,
      icon: Icons.desktop_windows,
      defaultWidthFt: 4.5,
      defaultLengthFt: 2.2,
      description: 'Work desk',
    ),
    FurnitureCatalogEntry(
      id: 'desk_small',
      type: FurnitureType.table,
      label: 'Compact desk',
      category: FurnitureCategory.tables,
      icon: Icons.desktop_windows,
      defaultWidthFt: 3.5,
      defaultLengthFt: 1.8,
      description: 'Small writing desk',
    ),
    FurnitureCatalogEntry(
      id: 'side_table',
      type: FurnitureType.table,
      label: 'Side table',
      category: FurnitureCategory.tables,
      icon: Icons.table_bar,
      defaultWidthFt: 1.8,
      defaultLengthFt: 1.8,
      description: 'End / side table',
    ),
    FurnitureCatalogEntry(
      id: 'console_table',
      type: FurnitureType.table,
      label: 'Console table',
      category: FurnitureCategory.tables,
      icon: Icons.table_bar,
      defaultWidthFt: 4.0,
      defaultLengthFt: 1.2,
      description: 'Hall console',
    ),
    // —— Storage ——
    FurnitureCatalogEntry(
      id: 'wardrobe',
      type: FurnitureType.wardrobe,
      label: 'Wardrobe',
      category: FurnitureCategory.storage,
      icon: Icons.door_sliding,
      // +38: default to wide sliding unit (study feedback / gold-plan style)
      defaultWidthFt: 6.5,
      defaultLengthFt: 1.5,
      description: 'Closet / sliding wardrobe',
    ),
    FurnitureCatalogEntry(
      id: 'wardrobe_wide',
      type: FurnitureType.wardrobe,
      label: 'Wide wardrobe',
      category: FurnitureCategory.storage,
      icon: Icons.door_sliding,
      defaultWidthFt: 6.7,
      defaultLengthFt: 1.5,
      description: 'Large sliding wardrobe',
    ),
    FurnitureCatalogEntry(
      id: 'dresser',
      type: FurnitureType.wardrobe,
      label: 'Dresser',
      category: FurnitureCategory.storage,
      icon: Icons.inventory_2,
      defaultWidthFt: 4.5,
      defaultLengthFt: 1.8,
      description: 'Chest of drawers',
    ),
    FurnitureCatalogEntry(
      id: 'chest',
      type: FurnitureType.wardrobe,
      label: 'Tall chest',
      category: FurnitureCategory.storage,
      icon: Icons.inventory_2,
      defaultWidthFt: 2.5,
      defaultLengthFt: 1.6,
      description: 'Tall dresser',
    ),
    FurnitureCatalogEntry(
      id: 'bookshelf',
      type: FurnitureType.bookshelf,
      label: 'Bookshelf',
      category: FurnitureCategory.storage,
      icon: Icons.menu_book,
      defaultWidthFt: 3.0,
      defaultLengthFt: 1.0,
      description: 'Bookcase',
    ),
    FurnitureCatalogEntry(
      id: 'bookshelf_tall',
      type: FurnitureType.bookshelf,
      label: 'Tall bookcase',
      category: FurnitureCategory.storage,
      icon: Icons.menu_book,
      defaultWidthFt: 2.5,
      defaultLengthFt: 1.2,
      description: 'Tall narrow bookcase',
    ),
    FurnitureCatalogEntry(
      id: 'shelf_low',
      type: FurnitureType.bookshelf,
      label: 'Low shelf',
      category: FurnitureCategory.storage,
      icon: Icons.view_agenda,
      defaultWidthFt: 4.0,
      defaultLengthFt: 1.2,
      description: 'Low media / display shelf',
    ),
    FurnitureCatalogEntry(
      id: 'cabinet',
      type: FurnitureType.wardrobe,
      label: 'Storage cabinet',
      category: FurnitureCategory.storage,
      icon: Icons.kitchen,
      defaultWidthFt: 3.0,
      defaultLengthFt: 1.5,
      description: 'General cabinet',
    ),
    FurnitureCatalogEntry(
      id: 'shoe_rack',
      type: FurnitureType.bookshelf,
      label: 'Shoe rack',
      category: FurnitureCategory.storage,
      icon: Icons.grid_view,
      defaultWidthFt: 2.5,
      defaultLengthFt: 1.0,
      description: 'Entry shoe storage',
    ),
    // —— Media ——
    FurnitureCatalogEntry(
      id: 'tv_unit',
      type: FurnitureType.tvUnit,
      label: 'TV unit',
      category: FurnitureCategory.media,
      icon: Icons.tv,
      defaultWidthFt: 5.0,
      defaultLengthFt: 1.5,
      description: 'TV stand / media console',
    ),
    FurnitureCatalogEntry(
      id: 'tv_unit_wide',
      type: FurnitureType.tvUnit,
      label: 'Wide TV console',
      category: FurnitureCategory.media,
      icon: Icons.tv,
      defaultWidthFt: 6.5,
      defaultLengthFt: 1.6,
      description: 'Large media console',
    ),
    FurnitureCatalogEntry(
      id: 'tv_unit_compact',
      type: FurnitureType.tvUnit,
      label: 'Compact TV stand',
      category: FurnitureCategory.media,
      icon: Icons.tv,
      defaultWidthFt: 3.5,
      defaultLengthFt: 1.4,
      description: 'Small TV stand',
    ),
    // —— Outdoor / utility (reuse types) ——
    FurnitureCatalogEntry(
      id: 'plant_stand',
      type: FurnitureType.table,
      label: 'Plant stand',
      category: FurnitureCategory.outdoor,
      icon: Icons.local_florist,
      defaultWidthFt: 1.5,
      defaultLengthFt: 1.5,
      description: 'Plant / pedestal',
    ),
    FurnitureCatalogEntry(
      id: 'laundry_hamper',
      type: FurnitureType.nightstand,
      label: 'Laundry hamper',
      category: FurnitureCategory.outdoor,
      icon: Icons.local_laundry_service,
      defaultWidthFt: 1.8,
      defaultLengthFt: 1.8,
      description: 'Hamper footprint',
    ),
    FurnitureCatalogEntry(
      id: 'mirror_floor',
      type: FurnitureType.bookshelf,
      label: 'Floor mirror',
      category: FurnitureCategory.outdoor,
      icon: Icons.crop_portrait,
      defaultWidthFt: 2.0,
      defaultLengthFt: 0.8,
      description: 'Leaning / floor mirror',
    ),
    FurnitureCatalogEntry(
      id: 'rug_area',
      type: FurnitureType.table,
      label: 'Area rug (mark)',
      category: FurnitureCategory.outdoor,
      icon: Icons.crop_landscape,
      defaultWidthFt: 8.0,
      defaultLengthFt: 5.0,
      description: 'Rug outline for planning',
    ),
  ];

  static FurnitureCatalogEntry entryFor(FurnitureType type) {
    return all.firstWhere(
      (e) => e.type == type,
      orElse: () => all.first,
    );
  }

  /// Prefer wide wardrobe when scan reports a long unit (+38).
  static FurnitureCatalogEntry entryForSized(
    FurnitureType type, {
    double? widthFt,
    double? lengthFt,
  }) {
    if (type == FurnitureType.wardrobe) {
      final long = mathMax(widthFt ?? 0, lengthFt ?? 0);
      if (long >= 5.5) {
        return byId('wardrobe_wide') ?? entryFor(type);
      }
    }
    return entryFor(type);
  }

  static double mathMax(double a, double b) => a > b ? a : b;

  static FurnitureCatalogEntry? byId(String id) {
    try {
      return all.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<FurnitureCatalogEntry> byCategory(FurnitureCategory c) {
    return all.where((e) => e.category == c).toList();
  }

  static List<FurnitureCatalogEntry> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) {
      return e.label.toLowerCase().contains(q) ||
          e.description.toLowerCase().contains(q) ||
          e.id.contains(q) ||
          e.type.name.toLowerCase().contains(q) ||
          categoryLabel(e.category).toLowerCase().contains(q);
    }).toList();
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
      case FurnitureCategory.outdoor:
        return 'Other';
    }
  }
}
