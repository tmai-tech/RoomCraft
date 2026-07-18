import 'dart:math' as math;
import 'dart:ui';

import 'package:uuid/uuid.dart';

import '../../models/furniture_item.dart';
import '../../models/room_model.dart';
import '../../models/stroke_model.dart';
import 'collision.dart';
import 'furniture_bounds.dart';

enum RoomLayoutType { bedroom, living, office, empty }

/// Placement strategy for reflow of existing pieces (A/B/C alternatives).
enum ArrangeStyle {
  /// Along walls, open center (default product path).
  spacious,

  /// Maximize wall contact; denser storage walls.
  wallHug,

  /// Cluster seating / work pieces toward conversation / focus zones.
  conversation,
}

extension ArrangeStyleX on ArrangeStyle {
  String get label {
    switch (this) {
      case ArrangeStyle.spacious:
        return 'Spacious';
      case ArrangeStyle.wallHug:
        return 'Wall hug';
      case ArrangeStyle.conversation:
        return 'Conversation';
    }
  }

  String get subtitle {
    switch (this) {
      case ArrangeStyle.spacious:
        return 'Pieces along walls, clear walkways through the middle';
      case ArrangeStyle.wallHug:
        return 'Maximize wall contact for storage and beds';
      case ArrangeStyle.conversation:
        return 'Cluster seating / desks for face-to-face use';
    }
  }
}

/// Rule-based packer for spacious layouts.
///
/// Primary product use: re-pack **existing** scanned furniture (same pieces)
/// into a more open layout. Presets only when the room is empty.
class AutoArrange {
  static const _uuid = Uuid();

  /// Arrange furniture for a more spacious room.
  ///
  /// - If [seedFromExisting] or the room already has furniture → keep those
  ///   pieces (types + sizes), only move/rotate them.
  /// - If empty → place a minimal preset for [type] (catalog starter only).
  static List<FurnitureItem> arrange({
    required RoomModel room,
    required double pixelsPerFoot,
    required RoomLayoutType type,
    bool seedFromExisting = false,
  }) {
    final roomR = FurnitureBounds.roomRect(
      room.widthInFeet,
      room.lengthInFeet,
      pixelsPerFoot,
    );

    final useExisting =
        (seedFromExisting || room.furniture.isNotEmpty) && room.furniture.isNotEmpty;

    if (useExisting) {
      return arrangeSpacious(room: room, pixelsPerFoot: pixelsPerFoot);
    }

    return _placeFromSpecs(
      room: room,
      roomR: roomR,
      pixelsPerFoot: pixelsPerFoot,
      specs: _preset(type)
          .map(
            (s) => _Spec(
              id: _uuid.v4(),
              type: s.type,
              w: s.w,
              l: s.l,
              rot: 0,
            ),
          )
          .toList(),
    );
  }

  /// Keep every existing piece; place them against walls with clear walkways.
  static List<FurnitureItem> arrangeSpacious({
    required RoomModel room,
    required double pixelsPerFoot,
  }) {
    return arrangeWithStyle(
      room: room,
      pixelsPerFoot: pixelsPerFoot,
      style: ArrangeStyle.spacious,
    );
  }

  /// Reflow existing pieces with a named [style] (spacious / wall-hug / conversation).
  static List<FurnitureItem> arrangeWithStyle({
    required RoomModel room,
    required double pixelsPerFoot,
    required ArrangeStyle style,
  }) {
    final roomR = FurnitureBounds.roomRect(
      room.widthInFeet,
      room.lengthInFeet,
      pixelsPerFoot,
    );

    final specs = room.furniture
        .map(
          (f) => _Spec(
            id: f.id,
            type: f.type,
            w: f.widthInFeet,
            l: f.lengthInFeet,
            rot: f.rotationAngle,
            catalogId: f.catalogId,
          ),
        )
        .toList();

    // Largest first — big pieces claim walls, small fill gaps
    specs.sort((a, b) => (b.w * b.l).compareTo(a.w * a.l));

    return _placeFromSpecs(
      room: room,
      roomR: roomR,
      pixelsPerFoot: pixelsPerFoot,
      specs: specs,
      preferSpacious: style == ArrangeStyle.spacious,
      style: style,
    );
  }

  static List<FurnitureItem> _placeFromSpecs({
    required RoomModel room,
    required Rect roomR,
    required double pixelsPerFoot,
    required List<_Spec> specs,
    bool preferSpacious = false,
    ArrangeStyle style = ArrangeStyle.spacious,
  }) {
    final placed = <FurnitureItem>[];
    // Wider margin when optimizing for space (walkways)
    final margin = switch (style) {
      ArrangeStyle.spacious => 0.75 * pixelsPerFoot,
      ArrangeStyle.wallHug => 0.35 * pixelsPerFoot,
      ArrangeStyle.conversation => 0.55 * pixelsPerFoot,
    };
    final doorKeepOut = _doorKeepOutCenters(room, pixelsPerFoot);

    for (final s in specs) {
      final itemW = s.w * pixelsPerFoot;
      final itemH = s.l * pixelsPerFoot;

      // Prefer wall-facing orientations for beds/sofas/storage
      final rotations = _rotationCandidates(s.type, s.rot);

      FurnitureItem? best;
      var bestScore = -1e9;

      for (final rot in rotations) {
        final candidates = _candidatePositions(
          roomR,
          itemW,
          itemH,
          margin,
          spacious: style == ArrangeStyle.spacious,
          conversation: style == ArrangeStyle.conversation,
        );
        for (final pos in candidates) {
          var item = FurnitureItem(
            id: s.id,
            type: s.type,
            position: pos,
            widthInFeet: s.w,
            lengthInFeet: s.l,
            rotationAngle: rot,
            catalogId: s.catalogId,
          );
          item = item.copyWith(
            position: FurnitureBounds.clampCenterInRoom(
              item,
              pixelsPerFoot,
              roomR,
            ),
          );
          if (Collision.overlapsAny(item, placed, pixelsPerFoot, padding: 6)) {
            continue;
          }
          // Soft avoid door keep-outs
          if (_hitsDoorKeepOut(item, pixelsPerFoot, doorKeepOut)) {
            continue;
          }
          final score = _placementScore(
            item,
            placed,
            roomR,
            pixelsPerFoot,
            spacious: preferSpacious,
            style: style,
          );
          if (score > bestScore) {
            bestScore = score;
            best = item;
          }
        }
      }

      best ??= FurnitureItem(
        id: s.id,
        type: s.type,
        position: roomR.center,
        widthInFeet: s.w,
        lengthInFeet: s.l,
        rotationAngle: s.rot,
        catalogId: s.catalogId,
      );
      best = Collision.resolveOverlaps(best, placed, pixelsPerFoot, roomR);
      placed.add(best);
    }

    return placed;
  }

  /// Score higher when against walls and with more free center (spacious).
  static double _placementScore(
    FurnitureItem item,
    List<FurnitureItem> others,
    Rect room,
    double pxf, {
    required bool spacious,
    ArrangeStyle style = ArrangeStyle.spacious,
  }) {
    final r = FurnitureBounds.itemRect(item, pxf);
    var score = 0.0;

    // Prefer hugging outer walls
    final distWall = math.min(
      math.min(r.left - room.left, room.right - r.right),
      math.min(r.top - room.top, room.bottom - r.bottom),
    );
    final wallWeight = style == ArrangeStyle.wallHug ? 70.0 : 40.0;
    score += math.max(0, wallWeight - distWall); // closer to wall → higher

    if (style == ArrangeStyle.wallHug) {
      // Strongly prefer storage / beds on walls
      if (item.type == FurnitureType.wardrobe ||
          item.type == FurnitureType.bookshelf ||
          item.type == FurnitureType.tvUnit ||
          item.type == FurnitureType.bed) {
        if (distWall < 14) score += 40;
      }
      // Small items fill corners
      if (item.type == FurnitureType.nightstand ||
          item.type == FurnitureType.chair) {
        final corner = math.min(
          math.min((r.left - room.left).abs(), (room.right - r.right).abs()),
          math.min((r.top - room.top).abs(), (room.bottom - r.bottom).abs()),
        );
        if (corner < 20) score += 20;
      }
    }

    if (style == ArrangeStyle.conversation) {
      final seating = item.type == FurnitureType.sofa ||
          item.type == FurnitureType.chair ||
          item.type == FurnitureType.table ||
          item.type == FurnitureType.desk;
      final dCenter = (item.position - room.center).distance;
      if (seating) {
        // Prefer near center for conversation / desk clusters
        score += math.max(0, 120 - dCenter) * 0.35;
        for (final o in others) {
          if (o.type == FurnitureType.sofa ||
              o.type == FurnitureType.chair ||
              o.type == FurnitureType.table) {
            final d = (item.position - o.position).distance;
            // Prefer moderate clustering (not on top, not far)
            score += math.max(0, 60 - (d - 40).abs()) * 0.2;
          }
        }
      } else {
        // Storage stays on walls
        score += math.max(0, 50 - distWall);
      }
    }

    if (spacious || style == ArrangeStyle.spacious) {
      // Reward distance from room center (leave open middle)
      final dCenter = (item.position - room.center).distance;
      score += dCenter * 0.15;

      // Reward separation from other furniture
      for (final o in others) {
        final d = (item.position - o.position).distance;
        score += math.min(d, 80) * 0.05;
      }

      // Beds / sofas prefer longer side along a wall
      if (item.type == FurnitureType.bed || item.type == FurnitureType.sofa) {
        final alongTop = (r.top - room.top).abs() < 12;
        final alongBot = (room.bottom - r.bottom).abs() < 12;
        final alongL = (r.left - room.left).abs() < 12;
        final alongR = (room.right - r.right).abs() < 12;
        if (alongTop || alongBot || alongL || alongR) score += 25;
      }
    }

    return score;
  }

  static List<double> _rotationCandidates(FurnitureType type, double current) {
    // 0 and 90° cover most wall alignments; keep current if already set
    final base = <double>{0.0, math.pi / 2, math.pi, 3 * math.pi / 2, current};
    return base.toList();
  }

  static List<Offset> _doorKeepOutCenters(RoomModel room, double pxf) {
    final list = <Offset>[];
    for (final s in room.strokes) {
      if (s.type != StrokeType.door || s.points.length < 2) continue;
      list.add(
        Offset(
          (s.points.first.dx + s.points.last.dx) / 2,
          (s.points.first.dy + s.points.last.dy) / 2,
        ),
      );
    }
    return list;
  }

  static bool _hitsDoorKeepOut(
    FurnitureItem item,
    double pxf,
    List<Offset> doors,
  ) {
    final r = FurnitureBounds.itemRect(item, pxf);
    const keep = 2.5; // ft
    for (final d in doors) {
      final keepPx = keep * pxf;
      final doorR = Rect.fromCircle(center: d, radius: keepPx);
      if (r.overlaps(doorR)) return true;
    }
    return false;
  }

  static List<({FurnitureType type, double w, double l})> _preset(
    RoomLayoutType type,
  ) {
    switch (type) {
      case RoomLayoutType.bedroom:
        return [
          (type: FurnitureType.bed, w: 5.0, l: 6.5),
          (type: FurnitureType.wardrobe, w: 4.0, l: 2.0),
          (type: FurnitureType.nightstand, w: 1.5, l: 1.5),
          (type: FurnitureType.nightstand, w: 1.5, l: 1.5),
        ];
      case RoomLayoutType.living:
        return [
          (type: FurnitureType.sofa, w: 6.0, l: 3.0),
          (type: FurnitureType.table, w: 3.5, l: 2.0),
          (type: FurnitureType.tvUnit, w: 5.0, l: 1.5),
          (type: FurnitureType.chair, w: 1.8, l: 1.8),
          (type: FurnitureType.chair, w: 1.8, l: 1.8),
        ];
      case RoomLayoutType.office:
        return [
          (type: FurnitureType.table, w: 4.5, l: 2.5),
          (type: FurnitureType.chair, w: 1.8, l: 1.8),
          (type: FurnitureType.bookshelf, w: 3.0, l: 1.0),
        ];
      case RoomLayoutType.empty:
        return [];
    }
  }

  /// Prefer wall-aligned placements: perimeter first when spacious.
  static List<Offset> _candidatePositions(
    Rect room,
    double itemW,
    double itemH,
    double margin, {
    bool spacious = false,
    bool conversation = false,
  }) {
    final cx = room.center.dx;
    final cy = room.center.dy;
    final left = room.left + itemW / 2 + margin;
    final right = room.right - itemW / 2 - margin;
    final top = room.top + itemH / 2 + margin;
    final bottom = room.bottom - itemH / 2 - margin;

    final list = <Offset>[];

    if (conversation) {
      // Center-first ring for conversation clusters
      list.addAll([
        Offset(cx, cy),
        Offset(cx - itemW, cy),
        Offset(cx + itemW, cy),
        Offset(cx, cy - itemH),
        Offset(cx, cy + itemH),
        Offset(cx - itemW * 0.7, cy - itemH * 0.7),
        Offset(cx + itemW * 0.7, cy - itemH * 0.7),
        Offset(cx - itemW * 0.7, cy + itemH * 0.7),
        Offset(cx + itemW * 0.7, cy + itemH * 0.7),
      ]);
    }

    // Against walls (perimeter)
    list.addAll([
      Offset(cx, top),
      Offset(cx, bottom),
      Offset(left, cy),
      Offset(right, cy),
      Offset(left, top),
      Offset(right, top),
      Offset(left, bottom),
      Offset(right, bottom),
    ]);

    // Quarter points on each wall
    list.addAll([
      Offset(left + (right - left) * 0.25, top),
      Offset(left + (right - left) * 0.75, top),
      Offset(left + (right - left) * 0.25, bottom),
      Offset(left + (right - left) * 0.75, bottom),
      Offset(left, top + (bottom - top) * 0.25),
      Offset(left, top + (bottom - top) * 0.75),
      Offset(right, top + (bottom - top) * 0.25),
      Offset(right, top + (bottom - top) * 0.75),
    ]);

    if (!spacious) {
      list.add(Offset(cx, cy));
    }

    // Grid fill (skip very center when spacious)
    final steps = spacious ? 5 : 4;
    for (var ix = 0; ix <= steps; ix++) {
      for (var iy = 0; iy <= steps; iy++) {
        if (spacious && ix > 1 && ix < steps - 1 && iy > 1 && iy < steps - 1) {
          continue; // leave open middle
        }
        final x = left + (right - left) * ix / steps;
        final y = top + (bottom - top) * iy / steps;
        list.add(Offset(x, y));
      }
    }
    return list;
  }

  static String label(RoomLayoutType t) {
    switch (t) {
      case RoomLayoutType.bedroom:
        return 'Bedroom starter';
      case RoomLayoutType.living:
        return 'Living starter';
      case RoomLayoutType.office:
        return 'Office starter';
      case RoomLayoutType.empty:
        return 'Empty (no furniture)';
    }
  }
}

class _Spec {
  final String id;
  final FurnitureType type;
  final double w;
  final double l;
  final double rot;
  final String? catalogId;
  const _Spec({
    required this.id,
    required this.type,
    required this.w,
    required this.l,
    required this.rot,
    this.catalogId,
  });
}
