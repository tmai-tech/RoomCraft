import 'dart:math' as math;
import 'dart:ui';

import '../../models/stroke_model.dart';

/// Pure geometry for Planner5D-class top-down blueprint openings (+148).
///
/// - Wall perimeter is drawn with **gaps** at doors/windows (not a solid box
///   with orange lines on top).
/// - Door swing arcs always open **into** the room.
/// - Opening midpoints carry type + width labels (ft).
class BlueprintOpenings {
  BlueprintOpenings._();

  /// Axis-aligned wall edge index for a rectangular room.
  /// 0=top(y=0/south), 1=right, 2=bottom(y=h/north), 3=left.
  static int? wallIndexForOpening(
    Offset a,
    Offset b, {
    required double wPx,
    required double hPx,
    double tol = 8.0,
  }) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    if ((mid.dy - 0).abs() <= tol && a.dy.abs() <= tol * 2 && b.dy.abs() <= tol * 2) {
      return 0; // south / top in unflipped model
    }
    if ((mid.dx - wPx).abs() <= tol &&
        (a.dx - wPx).abs() <= tol * 2 &&
        (b.dx - wPx).abs() <= tol * 2) {
      return 1; // east
    }
    if ((mid.dy - hPx).abs() <= tol &&
        (a.dy - hPx).abs() <= tol * 2 &&
        (b.dy - hPx).abs() <= tol * 2) {
      return 2; // north / bottom
    }
    if ((mid.dx - 0).abs() <= tol && a.dx.abs() <= tol * 2 && b.dx.abs() <= tol * 2) {
      return 3; // west
    }
    return null;
  }

  /// Project opening endpoints onto a wall's 1D parameter [0, wallLen].
  static (double lo, double hi)? projectOnWall(
    Offset a,
    Offset b, {
    required int wallIndex,
    required double wPx,
    required double hPx,
  }) {
    double t(Offset p) {
      switch (wallIndex) {
        case 0: // top: x along width
        case 2: // bottom
          return p.dx.clamp(0.0, wPx);
        case 1: // right: y along length
        case 3: // left
          return p.dy.clamp(0.0, hPx);
        default:
          return 0;
      }
    }

    final t0 = t(a);
    final t1 = t(b);
    final lo = math.min(t0, t1);
    final hi = math.max(t0, t1);
    if (hi - lo < 2) return null;
    return (lo, hi);
  }

  /// Closed rectangle wall pieces with openings cut out (Planner5D-style gaps).
  ///
  /// Returns pixel-space segments for the four sides. Callers draw thick walls
  /// only on these pieces so doors/windows read as openings, not painted-on top.
  static List<(Offset start, Offset end)> perimeterWithGaps({
    required double wPx,
    required double hPx,
    required List<StrokeModel> strokes,
    double padPx = 1.5,
  }) {
    final openings = strokes
        .where((s) =>
            s.type != StrokeType.wall &&
            s.points.length >= 2)
        .toList();

    // gaps[wallIndex] = list of (lo, hi) along that wall
    final gaps = <int, List<(double, double)>>{
      0: [],
      1: [],
      2: [],
      3: [],
    };

    for (final o in openings) {
      final a = o.points.first;
      final b = o.points.last;
      final wi = wallIndexForOpening(a, b, wPx: wPx, hPx: hPx);
      if (wi == null) continue;
      final proj = projectOnWall(a, b, wallIndex: wi, wPx: wPx, hPx: hPx);
      if (proj == null) continue;
      gaps[wi]!.add((proj.$1 - padPx, proj.$2 + padPx));
    }

    final out = <(Offset, Offset)>[];

    Offset ptOnWall(int wall, double t) {
      switch (wall) {
        case 0:
          return Offset(t.clamp(0.0, wPx), 0);
        case 1:
          return Offset(wPx, t.clamp(0.0, hPx));
        case 2:
          return Offset(t.clamp(0.0, wPx), hPx);
        case 3:
          return Offset(0, t.clamp(0.0, hPx));
        default:
          return Offset.zero;
      }
    }

    double wallLen(int wall) => (wall == 0 || wall == 2) ? wPx : hPx;

    for (var wall = 0; wall < 4; wall++) {
      final len = wallLen(wall);
      final raw = List<(double, double)>.from(gaps[wall]!);
      // Merge overlapping gaps
      raw.sort((a, b) => a.$1.compareTo(b.$1));
      final merged = <(double, double)>[];
      for (final g in raw) {
        final lo = g.$1.clamp(0.0, len);
        final hi = g.$2.clamp(0.0, len);
        if (hi <= lo) continue;
        if (merged.isEmpty || lo > merged.last.$2 + 0.5) {
          merged.add((lo, hi));
        } else {
          final prev = merged.removeLast();
          merged.add((prev.$1, math.max(prev.$2, hi)));
        }
      }

      var cursor = 0.0;
      for (final g in merged) {
        if (g.$1 > cursor + 1.0) {
          out.add((ptOnWall(wall, cursor), ptOnWall(wall, g.$1)));
        }
        cursor = math.max(cursor, g.$2);
      }
      if (cursor < len - 1.0) {
        out.add((ptOnWall(wall, cursor), ptOnWall(wall, len)));
      }
    }
    return out;
  }

  /// Door swing arc that opens into the room (not outside).
  ///
  /// Hinge is [p1]; leaf tip rests at [p2] when closed. Sweep is ±π/2 chosen
  /// so a mid-arc sample is closer to room center than the exterior alternative.
  static ({
    Offset hinge,
    Offset leaf,
    double radius,
    double startAngle,
    double sweep,
  }) inwardDoorSwing(
    Offset p1,
    Offset p2, {
    required double roomWPx,
    required double roomHPx,
  }) {
    final r = (p1 - p2).distance;
    final angle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
    final center = Offset(roomWPx / 2, roomHPx / 2);

    double sampleDist(double sweep) {
      final midA = angle + sweep / 2;
      final sample = Offset(
        p1.dx + r * 0.65 * math.cos(midA),
        p1.dy + r * 0.65 * math.sin(midA),
      );
      return (sample - center).distance;
    }

    final dPlus = sampleDist(math.pi / 2);
    final dMinus = sampleDist(-math.pi / 2);
    final sweep = dPlus <= dMinus ? math.pi / 2 : -math.pi / 2;

    return (
      hinge: p1,
      leaf: p2,
      radius: r,
      startAngle: angle,
      sweep: sweep,
    );
  }

  /// Prefer hinge at the corner-ward end so swing looks natural; still inward.
  ///
  /// Tries both stroke endpoint as hinge and picks the inward-valid option
  /// with mid-arc deepest inside the room (min distance to exterior).
  static ({
    Offset hinge,
    Offset leaf,
    double radius,
    double startAngle,
    double sweep,
  }) bestInwardDoorSwing(
    Offset a,
    Offset b, {
    required double roomWPx,
    required double roomHPx,
  }) {
    final s1 = inwardDoorSwing(a, b, roomWPx: roomWPx, roomHPx: roomHPx);
    final s2 = inwardDoorSwing(b, a, roomWPx: roomWPx, roomHPx: roomHPx);
    final center = Offset(roomWPx / 2, roomHPx / 2);

    double midDepth(
      ({
        Offset hinge,
        Offset leaf,
        double radius,
        double startAngle,
        double sweep,
      }) s,
    ) {
      final midA = s.startAngle + s.sweep / 2;
      final sample = Offset(
        s.hinge.dx + s.radius * 0.65 * math.cos(midA),
        s.hinge.dy + s.radius * 0.65 * math.sin(midA),
      );
      return (sample - center).distance;
    }

    return midDepth(s1) <= midDepth(s2) ? s1 : s2;
  }

  /// Human label for opening stroke mid-point (Planner5D dim string).
  static String openingLabel(StrokeType type, double lengthFt) {
    final name = switch (type) {
      StrokeType.door => 'Door',
      StrokeType.window => 'Win',
      StrokeType.balcony => 'Mesh',
      StrokeType.wall => 'Wall',
    };
    final w = lengthFt.clamp(0.1, 40.0);
    final text = w >= 10 ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
    return '$name $text′';
  }

  /// True when sample point of a swing is inside the room AABB (with margin).
  static bool swingSampleInside(
    Offset hinge,
    double radius,
    double startAngle,
    double sweep, {
    required double roomWPx,
    required double roomHPx,
    double margin = 2.0,
  }) {
    final midA = startAngle + sweep / 2;
    final sample = Offset(
      hinge.dx + radius * 0.65 * math.cos(midA),
      hinge.dy + radius * 0.65 * math.sin(midA),
    );
    return sample.dx >= -margin &&
        sample.dy >= -margin &&
        sample.dx <= roomWPx + margin &&
        sample.dy <= roomHPx + margin;
  }
}
