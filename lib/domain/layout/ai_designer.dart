import 'dart:ui';

import 'package:uuid/uuid.dart';

import '../../catalog/furniture_catalog.dart';
import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import 'auto_arrange.dart';

/// Planner 5D–style design style for AI Furnisher.
enum DesignStyle {
  modernMinimal,
  cozy,
  scandinavian,
  family,
  homeOffice,
  studio,
}

extension DesignStyleX on DesignStyle {
  String get label {
    switch (this) {
      case DesignStyle.modernMinimal:
        return 'Modern minimal';
      case DesignStyle.cozy:
        return 'Cozy';
      case DesignStyle.scandinavian:
        return 'Scandinavian';
      case DesignStyle.family:
        return 'Family living';
      case DesignStyle.homeOffice:
        return 'Home office';
      case DesignStyle.studio:
        return 'Studio loft';
    }
  }

  String get subtitle {
    switch (this) {
      case DesignStyle.modernMinimal:
        return 'Low clutter, clean lines, open walkways';
      case DesignStyle.cozy:
        return 'Soft seating, warm layers, lamps & rugs';
      case DesignStyle.scandinavian:
        return 'Light woods, plants, simple storage';
      case DesignStyle.family:
        return 'Durable seating, dining, media for daily life';
      case DesignStyle.homeOffice:
        return 'Desk focus with storage and meeting seating';
      case DesignStyle.studio:
        return 'Sleep + work + lounge in one open plan';
    }
  }

  /// Suggested room layout type for packing heuristics.
  RoomLayoutType get roomHint {
    switch (this) {
      case DesignStyle.homeOffice:
        return RoomLayoutType.office;
      case DesignStyle.family:
      case DesignStyle.cozy:
        return RoomLayoutType.living;
      case DesignStyle.studio:
      case DesignStyle.modernMinimal:
      case DesignStyle.scandinavian:
        return RoomLayoutType.bedroom;
    }
  }
}

/// Free, on-device AI Designer (Furnisher): catalog-driven auto-furnish.
///
/// No paid LLM required — style recipes + [AutoArrange] placement.
class AiDesigner {
  static const _uuid = Uuid();

  /// Build a furnished plan for [room] in [style].
  /// Replaces furniture; keeps walls/openings.
  static List<FurnitureItem> furnish({
    required RoomModel room,
    required double pixelsPerFoot,
    required DesignStyle style,
  }) {
    final specs = _recipe(style, room.widthInFeet, room.lengthInFeet);
    final seed = <FurnitureItem>[];
    for (final s in specs) {
      final entry = FurnitureCatalog.byId(s) ?? FurnitureCatalog.all.first;
      seed.add(
        FurnitureItem(
          id: _uuid.v4(),
          type: entry.type,
          position: const Offset(0, 0),
          widthInFeet: entry.defaultWidthFt,
          lengthInFeet: entry.defaultLengthFt,
          catalogId: entry.id,
        ),
      );
    }

    final rugs = seed.where((f) => f.type == FurnitureType.rug).toList();
    final solid = seed.where((f) => f.type != FurnitureType.rug).toList();
    final seeded = room.copyWith(furniture: solid);
    final arrangeStyle = switch (style) {
      DesignStyle.modernMinimal => ArrangeStyle.spacious,
      DesignStyle.cozy => ArrangeStyle.conversation,
      DesignStyle.scandinavian => ArrangeStyle.spacious,
      DesignStyle.family => ArrangeStyle.conversation,
      DesignStyle.homeOffice => ArrangeStyle.wallHug,
      DesignStyle.studio => ArrangeStyle.spacious,
    };

    final placed = AutoArrange.arrangeWithStyle(
      room: seeded,
      pixelsPerFoot: pixelsPerFoot,
      style: arrangeStyle,
    );

    // Rugs are floor layers — center, ignore packing collisions
    final center = Offset(
      room.widthInFeet * pixelsPerFoot / 2,
      room.lengthInFeet * pixelsPerFoot / 2,
    );
    return [
      ...placed,
      for (final r in rugs) r.copyWith(position: center, rotationAngle: 0),
    ];
  }

  /// Catalog SKU ids for a style, scaled by room area.
  static List<String> _recipe(DesignStyle style, double w, double l) {
    final area = w * l;
    final large = area >= 180;
    final small = area < 120;

    switch (style) {
      case DesignStyle.modernMinimal:
        return [
          if (!small) 'queen_bed' else 'full_bed',
          'nightstand',
          'wardrobe',
          'desk_small',
          'office_chair',
          if (large) 'floor_lamp',
          if (large) 'plant_stand',
          'rug_bedroom',
        ];
      case DesignStyle.cozy:
        return [
          'sofa_3',
          'armchair',
          'coffee_table',
          'tv_unit',
          'side_table',
          'floor_lamp',
          'table_lamp',
          'rug_area',
          'plant_large',
          if (large) 'bookshelf',
          if (large) 'ottoman',
        ];
      case DesignStyle.scandinavian:
        return [
          if (!small) 'queen_bed' else 'twin_bed',
          'nightstand',
          'nightstand_wide',
          'dresser',
          'bookshelf',
          'plant_large',
          'plant_stand',
          'floor_lamp',
          'rug_bedroom',
          if (large) 'bench',
        ];
      case DesignStyle.family:
        return [
          'sofa_3',
          'coffee_table',
          'tv_unit',
          'dining_table_4',
          'dining_chair',
          'dining_chair',
          'sideboard',
          'rug_area',
          'plant_stand',
          if (large) 'armchair',
        ];
      case DesignStyle.homeOffice:
        return [
          if (large) 'desk_l' else 'desk',
          'office_chair',
          'bookshelf_tall',
          'bookshelf',
          'filing_cabinet',
          'printer_stand',
          if (large) 'meeting_table',
          if (large) 'dining_chair',
          if (large) 'dining_chair',
          'plant_stand',
          'floor_lamp',
          if (!small) 'lounge_pod',
        ];
      case DesignStyle.studio:
        return [
          if (!small) 'queen_bed' else 'daybed',
          'nightstand',
          'wardrobe_narrow',
          'desk',
          'office_chair',
          'sofa_2',
          'coffee_table',
          'tv_unit_compact',
          'rug_area',
          'plant_stand',
        ];
    }
  }
}
