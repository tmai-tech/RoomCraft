import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import 'ai_designer.dart';
import 'layout_score.dart';

/// Planner 5D–style AI Styler: free on-device style transformation + tips.
///
/// Not photoreal image restyle (that needs paid HD render). Instead:
/// 1) re-furnish / re-layer for a design language
/// 2) emit actionable décor tips (palette, materials, lighting)
class StyleReport {
  final DesignStyle style;
  final List<FurnitureItem> furniture;
  final int score;
  final List<String> tips;
  final String palette;
  final String materials;

  const StyleReport({
    required this.style,
    required this.furniture,
    required this.score,
    required this.tips,
    required this.palette,
    required this.materials,
  });
}

class AiStyler {
  AiStyler._();

  /// Transform [room] into [style], preferring to keep major pieces when possible.
  static StyleReport apply({
    required RoomModel room,
    required double pixelsPerFoot,
    required DesignStyle style,
    bool keepExistingMajor = true,
  }) {
    // Full style recipe (Planner-style Styler → Furnisher pipeline on-device)
    final furniture = AiDesigner.furnish(
      room: room,
      pixelsPerFoot: pixelsPerFoot,
      style: style,
    );

    final eval = LayoutScore.evaluate(
      room.copyWith(furniture: furniture),
      pixelsPerFoot,
    );

    return StyleReport(
      style: style,
      furniture: furniture,
      score: eval.score,
      tips: _tipsFor(style, room),
      palette: _palette(style),
      materials: _materials(style),
    );
  }

  static List<String> _tipsFor(DesignStyle style, RoomModel room) {
    final area = room.widthInFeet * room.lengthInFeet;
    final base = <String>[
      'Room ~${room.widthInFeet.toStringAsFixed(1)}×${room.lengthInFeet.toStringAsFixed(1)} ft (${area.round()} ft²)',
    ];
    switch (style) {
      case DesignStyle.modernMinimal:
        return [
          ...base,
          'Keep walkways ≥ 2.5 ft; hide clutter in closed storage',
          'Limit accent colors to 1–2; prefer matte black + light wood',
          'One statement light + recessed/soft ambient',
        ];
      case DesignStyle.cozy:
        return [
          ...base,
          'Layer textiles: rug under seating, throw on sofa',
          'Warm palette: terracotta, cream, soft greens',
          'Add 2–3 light sources (floor + table + lamp)',
        ];
      case DesignStyle.scandinavian:
        return [
          ...base,
          'Light wood floors + white/soft gray walls',
          'Greenery (plants) and natural textiles',
          'Simple lines; avoid heavy dark bulk furniture',
        ];
      case DesignStyle.family:
        return [
          ...base,
          'Durable fabrics; round coffee table corners if kids',
          'TV opposite main sofa; clear door swing',
          'Dining near kitchen wall if openings allow',
        ];
      case DesignStyle.homeOffice:
        return [
          ...base,
          'Desk perpendicular to window to reduce glare',
          'Task lamp + monitor depth ≥ 2 ft from wall',
          'Cable routing behind desk; closed storage for paper',
        ];
      case DesignStyle.studio:
        return [
          ...base,
          'Zone sleep vs work with rug + lighting, not walls',
          'Murphy/daybed if under 140 ft²',
          'Vertical storage to free floor',
        ];
    }
  }

  static String _palette(DesignStyle style) {
    switch (style) {
      case DesignStyle.modernMinimal:
        return 'White · charcoal · light oak · black metal';
      case DesignStyle.cozy:
        return 'Cream · terracotta · olive · warm wood';
      case DesignStyle.scandinavian:
        return 'White · soft gray · birch · sage';
      case DesignStyle.family:
        return 'Warm white · navy · oak · soft blue';
      case DesignStyle.homeOffice:
        return 'Warm gray · walnut · navy · brass';
      case DesignStyle.studio:
        return 'Off-white · black · natural wood · linen';
    }
  }

  static String _materials(DesignStyle style) {
    switch (style) {
      case DesignStyle.modernMinimal:
        return 'Matte lacquer, glass, metal legs, low-pile rug';
      case DesignStyle.cozy:
        return 'Bouclé, linen, mid-pile wool rug, ceramic lamps';
      case DesignStyle.scandinavian:
        return 'Light wood, cotton, jute, powder-coated metal';
      case DesignStyle.family:
        return 'Performance fabric, rounded wood, washable rug';
      case DesignStyle.homeOffice:
        return 'Solid desk top, ergonomic mesh, acoustic shelf';
      case DesignStyle.studio:
        return 'Multi-use furniture, slim profiles, area rug zoning';
    }
  }
}
