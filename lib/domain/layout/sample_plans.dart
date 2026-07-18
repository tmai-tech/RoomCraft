import 'package:uuid/uuid.dart';

import '../../models/room_model.dart';
import 'ai_designer.dart';

/// Planner 5D–style “Gallery of Ideas” — free on-device starter plans.
class SamplePlan {
  final String id;
  final String title;
  final String blurb;
  final DesignStyle style;
  final double widthFt;
  final double lengthFt;

  const SamplePlan({
    required this.id,
    required this.title,
    required this.blurb,
    required this.style,
    required this.widthFt,
    required this.lengthFt,
  });
}

class SamplePlans {
  static const List<SamplePlan> all = [
    SamplePlan(
      id: 'cozy_living',
      title: 'Cozy living room',
      blurb: 'Sofa, media, warm layers — 16×14',
      style: DesignStyle.cozy,
      widthFt: 16,
      lengthFt: 14,
    ),
    SamplePlan(
      id: 'modern_bedroom',
      title: 'Modern minimal bedroom',
      blurb: 'Clean sleep + storage — 14×12',
      style: DesignStyle.modernMinimal,
      widthFt: 14,
      lengthFt: 12,
    ),
    SamplePlan(
      id: 'scandi_sleep',
      title: 'Scandinavian bedroom',
      blurb: 'Light woods, plants, calm — 13×11',
      style: DesignStyle.scandinavian,
      widthFt: 13,
      lengthFt: 11,
    ),
    SamplePlan(
      id: 'family_great',
      title: 'Family great room',
      blurb: 'Seating + dining + TV — 18×16',
      style: DesignStyle.family,
      widthFt: 18,
      lengthFt: 16,
    ),
    SamplePlan(
      id: 'home_office',
      title: 'Home office',
      blurb: 'Desk focus + storage — 12×10',
      style: DesignStyle.homeOffice,
      widthFt: 12,
      lengthFt: 10,
    ),
    SamplePlan(
      id: 'studio_loft',
      title: 'Studio loft',
      blurb: 'Sleep + work + lounge — 15×12',
      style: DesignStyle.studio,
      widthFt: 15,
      lengthFt: 12,
    ),
    SamplePlan(
      id: 'dining_nook',
      title: 'Dining nook',
      blurb: 'Table + seating cluster — 12×11',
      style: DesignStyle.cozy,
      widthFt: 12,
      lengthFt: 11,
    ),
    SamplePlan(
      id: 'master_suite',
      title: 'Master suite',
      blurb: 'King bed + storage lounge — 16×14',
      style: DesignStyle.modernMinimal,
      widthFt: 16,
      lengthFt: 14,
    ),
  ];

  static const _uuid = Uuid();

  /// Materialize a ready-to-edit [RoomModel] with furniture placed.
  static RoomModel materialize(SamplePlan plan, {double pixelsPerFoot = 20}) {
    final empty = RoomModel(
      id: _uuid.v4(),
      name: plan.title,
      widthInFeet: plan.widthFt,
      lengthInFeet: plan.lengthFt,
    );
    final furniture = AiDesigner.furnish(
      room: empty,
      pixelsPerFoot: pixelsPerFoot,
      style: plan.style,
    );
    return empty.copyWith(
      furniture: furniture,
      updatedAt: DateTime.now(),
    );
  }
}
