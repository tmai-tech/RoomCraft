import '../../models/room_model.dart';
import 'clearances.dart';
import 'collision.dart';
import 'furniture_bounds.dart';

class LayoutScore {
  final int score; // 0–100
  final List<LayoutTip> tips;
  final Set<String> collisionIds;

  const LayoutScore({
    required this.score,
    required this.tips,
    required this.collisionIds,
  });

  static LayoutScore evaluate(RoomModel room, double pixelsPerFoot) {
    final tips = Clearances.analyze(room, pixelsPerFoot);
    final collisions = Collision.overlappingIds(room.furniture, pixelsPerFoot);

    var score = 100;
    for (final t in tips) {
      if (t.severity == 'error') score -= 20;
      if (t.severity == 'warn') score -= 10;
    }
    score -= collisions.length * 5;

    // Reward leaving free space (30–60% filled ideal)
    final total = room.widthInFeet * room.lengthInFeet;
    if (total > 0 && room.furniture.isNotEmpty) {
      final filled = room.furniture.fold<double>(
        0,
        (s, f) => s + f.widthInFeet * f.lengthInFeet,
      );
      final ratio = filled / total;
      if (ratio >= 0.25 && ratio <= 0.55) {
        score += 5;
      } else if (ratio > 0.7) {
        score -= 10;
      }
    }

    // Out of bounds check
    final roomR = FurnitureBounds.roomRect(
      room.widthInFeet,
      room.lengthInFeet,
      pixelsPerFoot,
    );
    for (final f in room.furniture) {
      final r = FurnitureBounds.itemRect(f, pixelsPerFoot);
      if (r.left < roomR.left - 2 ||
          r.top < roomR.top - 2 ||
          r.right > roomR.right + 2 ||
          r.bottom > roomR.bottom + 2) {
        score -= 15;
        break;
      }
    }

    if (score < 0) score = 0;
    if (score > 100) score = 100;

    return LayoutScore(score: score, tips: tips, collisionIds: collisions);
  }
}
