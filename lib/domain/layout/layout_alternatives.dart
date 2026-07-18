import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import 'auto_arrange.dart';
import 'clearances.dart';
import 'layout_score.dart';

/// One scored alternative layout using the same furniture pieces.
class LayoutAlternative {
  final ArrangeStyle style;
  final List<FurnitureItem> furniture;
  final int score;
  final List<LayoutTip> tips;

  const LayoutAlternative({
    required this.style,
    required this.furniture,
    required this.score,
    required this.tips,
  });

  String get letter {
    switch (style) {
      case ArrangeStyle.spacious:
        return 'A';
      case ArrangeStyle.wallHug:
        return 'B';
      case ArrangeStyle.conversation:
        return 'C';
    }
  }
}

/// Generate scored layout alternatives without mutating the live room.
class LayoutAlternatives {
  LayoutAlternatives._();

  /// Produce A/B/C options for [room]'s current furniture.
  /// Empty furniture → empty list.
  static List<LayoutAlternative> generate({
    required RoomModel room,
    required double pixelsPerFoot,
  }) {
    if (room.furniture.isEmpty) return const [];

    final out = <LayoutAlternative>[];

    for (final style in ArrangeStyle.values) {
      final items = AutoArrange.arrangeWithStyle(
        room: room,
        pixelsPerFoot: pixelsPerFoot,
        style: style,
      );
      final evalRoom = room.copyWith(furniture: items);
      final eval = LayoutScore.evaluate(evalRoom, pixelsPerFoot);
      out.add(
        LayoutAlternative(
          style: style,
          furniture: items,
          score: eval.score,
          tips: eval.tips,
        ),
      );
    }

    // Best score first
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}
