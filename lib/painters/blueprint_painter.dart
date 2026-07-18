import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/layout/room_geometry.dart';
import '../domain/layout/walkway_heatmap.dart';
import '../domain/units.dart';
import '../models/room_model.dart';
import '../models/stroke_model.dart';

class BlueprintPainter extends CustomPainter {
  final RoomModel room;
  final StrokeModel? currentStroke;
  final double pixelsPerFoot;
  final UnitSystem unitSystem;
  /// Model-space (0,0) is drawn at this canvas offset so left/top walls
  /// are not stuck to the InteractiveViewer edge.
  final Offset origin;
  /// Planner-style walkway free-path overlay (green clear / red blocked).
  final bool showWalkwayHeatmap;

  BlueprintPainter({
    required this.room,
    this.currentStroke,
    required this.pixelsPerFoot,
    this.unitSystem = UnitSystem.feet,
    this.origin = Offset.zero,
    this.showWalkwayHeatmap = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    _drawRoomOutline(canvas);
    if (showWalkwayHeatmap) {
      _drawWalkwayHeatmap(canvas);
    }

    for (final stroke in room.strokes) {
      _drawStroke(canvas, stroke);
      _drawMeasurements(canvas, stroke);
    }

    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
      _drawMeasurements(canvas, currentStroke!);
    }
    canvas.restore();
  }

  void _drawWalkwayHeatmap(Canvas canvas) {
    final cells = WalkwayHeatmap.compute(room, pixelsPerFoot);
    for (final c in cells) {
      final color = c.isBlocked
          ? Colors.red.withValues(alpha: 0.22)
          : c.isTight
              ? Colors.orange.withValues(alpha: 0.18)
              : Colors.green.withValues(alpha: 0.12);
      canvas.drawRect(c.rect, Paint()..color = color);
    }
  }

  void _drawRoomOutline(Canvas canvas) {
    final w = room.widthInFeet * pixelsPerFoot;
    final h = room.lengthInFeet * pixelsPerFoot;
    final paint = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (room.isPolygonFloor) {
      final path =
          RoomGeometry.pathFromFt(room.floorPolygonFt!, pixelsPerFoot);
      canvas.drawPath(path, paint);
      canvas.drawPath(path, border);
      // Dim the cutout area of the bounding box so L-shape is obvious
      final bb = Path()..addRect(Rect.fromLTWH(0, 0, w, h));
      final cutout = Path.combine(PathOperation.difference, bb, path);
      canvas.drawPath(
        cutout,
        Paint()..color = Colors.grey.shade300.withValues(alpha: 0.55),
      );
    } else {
      final rect = Rect.fromLTWH(0, 0, w, h);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, border);
    }

    // Room size label
    final shape = RoomGeometry.shapeLabel(room.floorPolygonFt);
    final label =
        '${LengthFormat.formatFeet(room.widthInFeet, unitSystem)} × '
        '${LengthFormat.formatFeet(room.lengthInFeet, unitSystem)} · $shape';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.blueGrey.shade700,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(8, h + 6));
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final major = Paint()
      ..color = Colors.grey.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Align major lines with room model origin so the left wall sits on a grid line.
    final ox = origin.dx;
    final oy = origin.dy;
    for (double i = ox; i <= size.width; i += pixelsPerFoot) {
      final isMajor = ((i - ox) / pixelsPerFoot).round() % 5 == 0;
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), isMajor ? major : paint);
    }
    for (double i = ox - pixelsPerFoot; i >= 0; i -= pixelsPerFoot) {
      final isMajor = ((ox - i) / pixelsPerFoot).round() % 5 == 0;
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), isMajor ? major : paint);
    }
    for (double i = oy; i <= size.height; i += pixelsPerFoot) {
      final isMajor = ((i - oy) / pixelsPerFoot).round() % 5 == 0;
      canvas.drawLine(Offset(0, i), Offset(size.width, i), isMajor ? major : paint);
    }
    for (double i = oy - pixelsPerFoot; i >= 0; i -= pixelsPerFoot) {
      final isMajor = ((oy - i) / pixelsPerFoot).round() % 5 == 0;
      canvas.drawLine(Offset(0, i), Offset(size.width, i), isMajor ? major : paint);
    }
  }

  void _drawStroke(Canvas canvas, StrokeModel stroke) {
    if (stroke.points.isEmpty) return;
    if (stroke.points.length == 1) {
      _drawPoint(canvas, stroke.points.first, stroke.type);
      return;
    }

    final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (var i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }

    switch (stroke.type) {
      case StrokeType.wall:
        final paint = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 8.0;
        canvas.drawPath(path, paint);
        break;
      case StrokeType.door:
        final paint = Paint()
          ..color = Colors.orange
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 4.0;
        _drawDashedPath(canvas, path, paint);
        _drawDoorArc(canvas, stroke.points.first, stroke.points.last);
        break;
      case StrokeType.window:
        final paint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 6.0;
        canvas.drawPath(path, paint);
        final innerPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawPath(path, innerPaint);
        break;
      case StrokeType.balcony:
        final paint = Paint()
          ..color = Colors.green
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3.0;
        _drawDashedPath(canvas, path, paint);
        _drawRailing(canvas, path);
        break;
    }
  }

  void _drawPoint(Canvas canvas, Offset p, StrokeType type) {
    final paint = Paint()..style = PaintingStyle.fill;
    if (type == StrokeType.wall) {
      paint.color = Colors.black;
      canvas.drawCircle(p, 4.0, paint);
    } else if (type == StrokeType.door) {
      paint.color = Colors.orange;
      canvas.drawCircle(p, 2.0, paint);
    } else if (type == StrokeType.window) {
      paint.color = Colors.blue;
      canvas.drawCircle(p, 3.0, paint);
    } else if (type == StrokeType.balcony) {
      paint.color = Colors.green;
      canvas.drawCircle(p, 2.0, paint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const double dashWidth = 10, dashSpace = 5;
    double distance = 0.0;
    for (final pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        final extractPath = pathMetric.extractPath(distance, distance + dashWidth);
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashSpace;
      }
      distance = 0.0;
    }
  }

  void _drawDoorArc(Canvas canvas, Offset p1, Offset p2) {
    if ((p1 - p2).distance < 5) return;
    final r = (p1 - p2).distance;
    final angle = atan2(p2.dy - p1.dy, p2.dx - p1.dx);

    // Filled swing sector (keep-out visual)
    final fill = Paint()
      ..color = Colors.orange.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..arcTo(
        Rect.fromCircle(center: p1, radius: r),
        angle,
        pi / 2,
        false,
      )
      ..close();
    canvas.drawPath(path, fill);

    final paint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawArc(
      Rect.fromCircle(center: p1, radius: r),
      angle,
      pi / 2,
      false,
      paint,
    );
    // Swing radius tick
    final end = Offset(
      p1.dx + r * cos(angle + pi / 2),
      p1.dy + r * sin(angle + pi / 2),
    );
    canvas.drawLine(
      p1,
      end,
      Paint()
        ..color = Colors.orange.withValues(alpha: 0.45)
        ..strokeWidth = 1.5,
    );
  }

  void _drawRailing(Canvas canvas, Path path) {
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const double interval = 10.0;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += interval) {
        final pos = metric.getTangentForOffset(d)?.position;
        final v = metric.getTangentForOffset(d)?.vector;
        if (pos != null && v != null) {
          final perp = Offset(-v.dy, v.dx) * 5.0;
          canvas.drawLine(pos, pos + perp, paint);
        }
      }
    }
  }

  void _drawMeasurements(Canvas canvas, StrokeModel stroke) {
    if (stroke.points.length < 2) return;
    for (var i = 0; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];
      final dist = (p1 - p2).distance;

      if (dist > pixelsPerFoot * 0.4) {
        final lengthInFeet = dist / pixelsPerFoot;
        final label = LengthFormat.formatFeet(lengthInFeet, unitSystem);
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final midPoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final bg = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: midPoint.translate(0, -10),
            width: textPainter.width + 8,
            height: textPainter.height + 4,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(bg, Paint()..color = Colors.black.withValues(alpha: 0.65));
        textPainter.paint(
          canvas,
          Offset(
            midPoint.dx - textPainter.width / 2,
            midPoint.dy - textPainter.height - 8,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(BlueprintPainter oldDelegate) {
    return true;
  }
}
