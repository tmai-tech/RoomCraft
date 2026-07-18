import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/layout/isometric.dart';
import '../domain/units.dart';
import '../models/furniture_item.dart';
import '../models/room_model.dart';
import '../models/stroke_model.dart';

/// Lightweight Planner5D-style isometric view of a top-down plan.
/// Pure CustomPainter — no 3D engine or paid SDKs.
class IsometricPainter extends CustomPainter {
  final RoomModel room;
  final double pixelsPerFoot;
  final UnitSystem unitSystem;
  /// Extra yaw in radians around the room center (user orbit).
  final double yaw;
  final double wallHeightFt;
  final String? selectedId;
  /// When true, use perspective projection (vanishing depth) instead of pure iso.
  final bool perspective;
  /// Walkthrough: camera offset from room center in model px (plan X/Y).
  final double walkX;
  final double walkY;
  /// Eye height in feet for walkthrough.
  final double eyeHeightFt;

  IsometricPainter({
    required this.room,
    required this.pixelsPerFoot,
    this.unitSystem = UnitSystem.feet,
    this.yaw = 0,
    this.wallHeightFt = 8.0,
    this.selectedId,
    this.perspective = true, // walkthrough-first (Planner 3D explore)
    this.walkX = 0,
    this.walkY = 0,
    this.eyeHeightFt = 5.5,
  });

  double get _scale => pixelsPerFoot;

  @override
  void paint(Canvas canvas, Size size) {
    final w = room.widthInFeet * _scale;
    final d = room.lengthInFeet * _scale;
    final h = wallHeightFt * _scale * 0.55; // visual wall height

    // Collect projected points for fit
    final sample = <Offset>[];
    for (final c in [
      const Offset(0, 0),
      Offset(w, 0),
      Offset(w, d),
      Offset(0, d),
    ]) {
      final p = _rotThenProject(c.dx, c.dy, 0, w, d);
      sample.add(p);
      sample.add(_rotThenProject(c.dx, c.dy, h, w, d));
    }
    for (final f in room.furniture) {
      final fh = _heightFor(f.type) * _scale * 0.55;
      sample.addAll(
        _furnitureProjected(f, fh, w, d),
      );
    }

    final bounds = Iso.boundsOf(sample);
    if (bounds.width <= 0 || bounds.height <= 0) return;

    const pad = 28.0;
    final sx = (size.width - pad * 2) / bounds.width;
    final sy = (size.height - pad * 2) / bounds.height;
    final s = math.min(sx, sy);

    // Soft sky → floor gradient (Planner-style 3D stage)
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFE8F0F8),
          Color(0xFFF4F6F8),
          Color(0xFFECEFF1),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);

    // Soft floor shadow ellipse
    final shadow = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.72),
        width: size.width * 0.55,
        height: size.height * 0.12,
      ),
      shadow,
    );

    Offset map(Offset p) {
      return Offset(
        size.width / 2 + (p.dx - bounds.center.dx) * s,
        size.height / 2 + (p.dy - bounds.center.dy) * s,
      );
    }

    // Floor — warm wood-ish gradient (free CustomPainter “materials”)
    final floorPts = [
      map(_rotThenProject(0, 0, 0, w, d)),
      map(_rotThenProject(w, 0, 0, w, d)),
      map(_rotThenProject(w, d, 0, w, d)),
      map(_rotThenProject(0, d, 0, w, d)),
    ];
    final floorPath = Path()..addPolygon(floorPts, true);
    final floorBounds = Rect.fromPoints(floorPts[0], floorPts[2]);
    canvas.drawPath(
      floorPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFE8D9C0),
            const Color(0xFFD4C0A0),
            const Color(0xFFC8B090),
          ],
        ).createShader(floorBounds),
    );
    canvas.drawPath(
      floorPath,
      Paint()
        ..color = Colors.brown.shade400.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Ceiling plane (perspective walkthrough feel)
    if (perspective) {
      final ceilPts = [
        map(_rotThenProject(0, 0, h, w, d)),
        map(_rotThenProject(w, 0, h, w, d)),
        map(_rotThenProject(w, d, h, w, d)),
        map(_rotThenProject(0, d, h, w, d)),
      ];
      final ceilPath = Path()..addPolygon(ceilPts, true);
      canvas.drawPath(
        ceilPath,
        Paint()..color = Colors.blueGrey.shade100.withValues(alpha: 0.35),
      );
      canvas.drawPath(
        ceilPath,
        Paint()
          ..color = Colors.blueGrey.shade300.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Grid on floor
    final gridPaint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    final step = _scale; // 1 ft
    for (var x = step; x < w; x += step) {
      canvas.drawLine(
        map(_rotThenProject(x, 0, 0, w, d)),
        map(_rotThenProject(x, d, 0, w, d)),
        gridPaint,
      );
    }
    for (var y = step; y < d; y += step) {
      canvas.drawLine(
        map(_rotThenProject(0, y, 0, w, d)),
        map(_rotThenProject(w, y, 0, w, d)),
        gridPaint,
      );
    }

    // Walls (four edges extruded)
    _drawWall(canvas, map, 0, 0, w, 0, h, w, d, Colors.blueGrey.shade200);
    _drawWall(canvas, map, w, 0, w, d, h, w, d, Colors.blueGrey.shade300);
    _drawWall(canvas, map, w, d, 0, d, h, w, d, Colors.blueGrey.shade400);
    _drawWall(canvas, map, 0, d, 0, 0, h, w, d, Colors.blueGrey.shade200);

    // Openings as floor-level colored bands
    for (final stroke in room.strokes) {
      if (stroke.points.length < 2) continue;
      final a = stroke.points.first;
      final b = stroke.points.last;
      final color = switch (stroke.type) {
        StrokeType.door => Colors.brown.shade400,
        StrokeType.window => Colors.lightBlue.shade300,
        StrokeType.balcony => Colors.teal.shade300,
        StrokeType.wall => Colors.transparent,
      };
      if (color == Colors.transparent) continue;
      final p0 = map(_rotThenProject(a.dx, a.dy, 1, w, d));
      final p1 = map(_rotThenProject(b.dx, b.dy, 1, w, d));
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..color = color
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Furniture boxes (painter's algorithm-ish: sort by screen Y)
    final boxes = <_IsoBox>[];
    for (final f in room.furniture) {
      final fh = _heightFor(f.type) * _scale * 0.55;
      boxes.add(
        _IsoBox(
          item: f,
          height: fh,
          depthKey: _rotThenProject(f.position.dx, f.position.dy, 0, w, d).dy,
        ),
      );
    }
    boxes.sort((a, b) => a.depthKey.compareTo(b.depthKey));

    for (final box in boxes) {
      _drawFurnitureBox(
        canvas,
        map,
        box.item,
        box.height,
        w,
        d,
        selected: box.item.id == selectedId,
      );
    }

    // Dimension label
    final label =
        '${LengthFormat.formatFeet(room.widthInFeet, unitSystem)} × '
        '${LengthFormat.formatFeet(room.lengthInFeet, unitSystem)} · '
        '${perspective ? '3D walkthrough' : 'Isometric 3D'}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.blueGrey.shade700,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 24);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height - 28));
  }

  void _drawWall(
    Canvas canvas,
    Offset Function(Offset) map,
    double x0,
    double y0,
    double x1,
    double y1,
    double h,
    double roomW,
    double roomD,
    Color color,
  ) {
    final b0 = map(_rotThenProject(x0, y0, 0, roomW, roomD));
    final b1 = map(_rotThenProject(x1, y1, 0, roomW, roomD));
    final t1 = map(_rotThenProject(x1, y1, h, roomW, roomD));
    final t0 = map(_rotThenProject(x0, y0, h, roomW, roomD));
    final path = Path()
      ..moveTo(b0.dx, b0.dy)
      ..lineTo(b1.dx, b1.dy)
      ..lineTo(t1.dx, t1.dy)
      ..lineTo(t0.dx, t0.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.55));
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.blueGrey.shade600.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _drawFurnitureBox(
    Canvas canvas,
    Offset Function(Offset) map,
    FurnitureItem item,
    double h,
    double roomW,
    double roomD, {
    bool selected = false,
  }) {
    final fw = item.widthInFeet * _scale;
    final fd = item.lengthInFeet * _scale;
    final corners = Iso.boxCorners(
      cx: item.position.dx,
      cy: item.position.dy,
      w: fw,
      d: fd,
      h: h,
      rotation: item.rotationAngle + yaw,
    );
    // Apply room yaw via re-project of original model points is already in boxCorners
    // but yaw for furniture was incorrectly added to rotation. Recompute with room yaw:
    final bottom = <Offset>[];
    final top = <Offset>[];
    final hw = fw / 2;
    final hd = fd / 2;
    final cos = math.cos(item.rotationAngle);
    final sin = math.sin(item.rotationAngle);
    final locals = [
      Offset(-hw, -hd),
      Offset(hw, -hd),
      Offset(hw, hd),
      Offset(-hw, hd),
    ];
    for (final p in locals) {
      final rx = p.dx * cos - p.dy * sin;
      final ry = p.dx * sin + p.dy * cos;
      final x = item.position.dx + rx;
      final y = item.position.dy + ry;
      bottom.add(map(_rotThenProject(x, y, 0, roomW, roomD)));
      top.add(map(_rotThenProject(x, y, h, roomW, roomD)));
    }
    // silence unused
    assert(corners.length == 8);

    final fill = _materialColor(item.type);

    // Soft drop shadow under furniture (free path toward Planner “realistic” stage)
    final shadowPath = Path()..addPolygon(bottom, true);
    canvas.drawPath(
      shadowPath,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Draw three visible faces (simple)
    void face(List<Offset> pts, Color c) {
      final path = Path()..addPolygon(pts, true);
      canvas.drawPath(path, Paint()..color = c);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Lit faces: left darker, right mid, top brightest (cheap Phong stand-in)
    face([bottom[0], bottom[1], top[1], top[0]], Color.lerp(fill, Colors.black, 0.32)!);
    face([bottom[1], bottom[2], top[2], top[1]], Color.lerp(fill, Colors.black, 0.14)!);
    face([bottom[3], bottom[0], top[0], top[3]], Color.lerp(fill, Colors.black, 0.24)!);
    face([top[0], top[1], top[2], top[3]], Color.lerp(fill, Colors.white, 0.28)!);

    if (selected) {
      final outline = Paint()
        ..color = Colors.amber.shade700
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawPath(Path()..addPolygon(top, true), outline);
      canvas.drawPath(Path()..addPolygon([bottom[0], bottom[1], top[1], top[0]], true), outline);
    }

    // Label
    final mid = Offset(
      (top[0].dx + top[2].dx) / 2,
      (top[0].dy + top[2].dy) / 2,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: item.type.shortLabel,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
  }

  List<Offset> _furnitureProjected(
    FurnitureItem f,
    double h,
    double roomW,
    double roomD,
  ) {
    final fw = f.widthInFeet * _scale;
    final fd = f.lengthInFeet * _scale;
    final hw = fw / 2;
    final hd = fd / 2;
    final cos = math.cos(f.rotationAngle);
    final sin = math.sin(f.rotationAngle);
    final out = <Offset>[];
    for (final p in [
      Offset(-hw, -hd),
      Offset(hw, -hd),
      Offset(hw, hd),
      Offset(-hw, hd),
    ]) {
      final rx = p.dx * cos - p.dy * sin;
      final ry = p.dx * sin + p.dy * cos;
      final x = f.position.dx + rx;
      final y = f.position.dy + ry;
      out.add(_rotThenProject(x, y, 0, roomW, roomD));
      out.add(_rotThenProject(x, y, h, roomW, roomD));
    }
    return out;
  }

  /// Rotate plan around room center by [yaw], then project.
  /// [perspective] uses a simple camera sitting above-front looking at room center.
  Offset _rotThenProject(
    double x,
    double y,
    double z,
    double roomW,
    double roomD,
  ) {
    final cx = roomW / 2;
    final cy = roomD / 2;
    final dx = x - cx;
    final dy = y - cy;
    final cos = math.cos(yaw);
    final sin = math.sin(yaw);
    final rx = dx * cos - dy * sin + cx;
    final ry = dx * sin + dy * cos + cy;

    if (!perspective) {
      return Iso.project(rx, ry, z);
    }

    // First-person / explore camera inside or elevated over the room.
    // World: X right, Y up (height z), Z into depth (plan y).
    final eyeX = cx + walkX;
    final eyeY = eyeHeightFt * _scale;
    final eyeZ = cy + walkY;
    // Point relative to eye
    var vx = rx - eyeX;
    var vy = z - eyeY;
    var vz = ry - eyeZ;
    // Yaw around vertical (Y)
    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final rx2 = vx * cosY - vz * sinY;
    final rz2 = vx * sinY + vz * cosY;
    final ry2 = vy;
    // Look slightly down
    final pitch = 0.12;
    final ry3 = ry2 * math.cos(pitch) - rz2 * math.sin(pitch);
    final rz3 = ry2 * math.sin(pitch) + rz2 * math.cos(pitch);
    final dist = math.max(8.0, rz3);
    final f = roomD * 0.95;
    return Offset(rx2 * f / dist, -ry3 * f / dist);
  }

  static double _heightFor(FurnitureType t) => t.defaultHeightFt;

  /// Material-ish palette (fabric / wood / metal) — free CustomPainter only.
  static Color _materialColor(FurnitureType t) {
    return switch (t) {
      FurnitureType.sofa || FurnitureType.chair || FurnitureType.bed =>
        Color.lerp(t.planColor, const Color(0xFF6B4F3A), 0.25)!,
      FurnitureType.table ||
      FurnitureType.desk ||
      FurnitureType.bookshelf ||
      FurnitureType.wardrobe ||
      FurnitureType.dresser ||
      FurnitureType.nightstand =>
        Color.lerp(t.planColor, const Color(0xFF8B6914), 0.35)!,
      FurnitureType.lamp || FurnitureType.appliance || FurnitureType.tvUnit =>
        Color.lerp(t.planColor, const Color(0xFF546E7A), 0.4)!,
      FurnitureType.plant => const Color(0xFF4CAF50),
      FurnitureType.rug => Color.lerp(t.planColor, const Color(0xFFBCAAA4), 0.3)!,
      _ => t.planColor,
    };
  }

  @override
  bool shouldRepaint(covariant IsometricPainter old) {
    return old.room != room ||
        old.pixelsPerFoot != pixelsPerFoot ||
        old.unitSystem != unitSystem ||
        old.yaw != yaw ||
        old.wallHeightFt != wallHeightFt ||
        old.selectedId != selectedId ||
        old.perspective != perspective ||
        old.walkX != walkX ||
        old.walkY != walkY ||
        old.eyeHeightFt != eyeHeightFt;
  }
}

class _IsoBox {
  final FurnitureItem item;
  final double height;
  final double depthKey;
  _IsoBox({required this.item, required this.height, required this.depthKey});
}
