import 'dart:math';

import 'package:flutter/material.dart';

import '../domain/layout/blueprint_openings.dart';
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
    // +113: never paint with zero/NaN scale (infinite grid loop → red screen)
    final pxf = (pixelsPerFoot.isFinite && pixelsPerFoot > 0.5)
        ? pixelsPerFoot
        : 20.0;
    if (!room.widthInFeet.isFinite ||
        !room.lengthInFeet.isFinite ||
        room.widthInFeet <= 0 ||
        room.lengthInFeet <= 0) {
      return;
    }
    try {
      _drawGrid(canvas, size, pxf);
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      _drawRoomOutline(canvas, pxf);
      if (showWalkwayHeatmap) {
        _drawWalkwayHeatmap(canvas, pxf);
      }

      for (final stroke in room.strokes) {
        _drawStroke(canvas, stroke);
        _drawMeasurements(canvas, stroke, pxf);
      }

      if (currentStroke != null) {
        _drawStroke(canvas, currentStroke!);
        _drawMeasurements(canvas, currentStroke!, pxf);
      }
      canvas.restore();
    } catch (_) {
      // Swallow paint errors — red ErrorWidget on blueprint was feedback 9bbf5b05
    }
  }

  void _drawWalkwayHeatmap(Canvas canvas, double pxf) {
    final cells = WalkwayHeatmap.compute(room, pxf);
    for (final c in cells) {
      final color = c.isBlocked
          ? Colors.red.withValues(alpha: 0.22)
          : c.isTight
              ? Colors.orange.withValues(alpha: 0.18)
              : Colors.green.withValues(alpha: 0.12);
      canvas.drawRect(c.rect, Paint()..color = color);
    }
  }

  void _drawRoomOutline(Canvas canvas, double pxf) {
    final w = room.widthInFeet * pxf;
    final h = room.lengthInFeet * pxf;
    final paint = Paint()
      ..color = room.isExterior
          ? Colors.green.withValues(alpha: 0.18)
          : Colors.blueGrey.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = room.isExterior
          ? Colors.green.shade700.withValues(alpha: 0.55)
          : Colors.blueGrey.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (room.isPolygonFloor) {
      final path =
          RoomGeometry.pathFromFt(room.floorPolygonFt!, pxf);
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
      // +148: closed walls with thickness + gaps at openings (Planner5D)
      _drawClosedWallsWithGaps(canvas, w, h, pxf);
    }

    // Room size label (footer)
    final shape = RoomGeometry.shapeLabel(room.floorPolygonFt);
    final label =
        '${LengthFormat.formatFeet(room.widthInFeet, unitSystem)} × '
        '${LengthFormat.formatFeet(room.lengthInFeet, unitSystem)} · '
        '$shape · ${room.spaceLabel}';
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

    // +147 Phase 3: edge dimension strings + wall letters A–D (Planner5D-class)
    if (!room.isPolygonFloor) {
      _drawEdgeDimensions(canvas, w, h, pxf);
    }
  }

  /// Double-line closed walls with door/window gaps (+148 Phase 3.5).
  void _drawClosedWallsWithGaps(
    Canvas canvas,
    double wPx,
    double hPx,
    double pxf,
  ) {
    final segments = BlueprintOpenings.perimeterWithGaps(
      wPx: wPx,
      hPx: hPx,
      strokes: room.strokes,
      padPx: max(2.0, pxf * 0.08),
    );

    final outer = Paint()
      ..color = Colors.blueGrey.shade800
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..strokeWidth = 7.0;
    final inner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeWidth = 3.0;

    for (final seg in segments) {
      canvas.drawLine(seg.$1, seg.$2, outer);
      canvas.drawLine(seg.$1, seg.$2, inner);
    }

    // Corner caps so gaps don't leave open miter holes when no openings nearby
    final corners = [
      Offset.zero,
      Offset(wPx, 0),
      Offset(wPx, hPx),
      Offset(0, hPx),
    ];
    final cap = Paint()..color = Colors.blueGrey.shade800;
    for (final c in corners) {
      canvas.drawCircle(c, 3.2, cap);
    }
  }

  void _drawEdgeDimensions(Canvas canvas, double wPx, double hPx, double pxf) {
    final wLabel = LengthFormat.formatFeet(room.widthInFeet, unitSystem);
    final lLabel = LengthFormat.formatFeet(room.lengthInFeet, unitSystem);
    final dimStyle = TextStyle(
      color: Colors.blueGrey.shade800,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    final wallStyle = TextStyle(
      color: Colors.blueGrey.shade500,
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );

    void paintCentered(String text, Offset center, {bool vertical = false}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: dimStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(center.dx, center.dy);
      if (vertical) canvas.rotate(-pi / 2);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }

    void paintWallLetter(String letter, Offset center) {
      final painter = TextPainter(
        text: TextSpan(text: letter, style: wallStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
      );
    }

    // Designer walk order (wall_relative_scan): A=south(y=0 top of canvas),
    // B=east, C=north(y=L bottom), D=west — matches field measure A→D.
    paintCentered(wLabel, Offset(wPx / 2, -12));
    paintWallLetter('A', Offset(wPx / 2, 10));
    paintCentered(lLabel, Offset(wPx + 14, hPx / 2), vertical: true);
    paintWallLetter('B', Offset(wPx - 12, hPx / 2));
    paintCentered(wLabel, Offset(wPx / 2, hPx + 18));
    paintWallLetter('C', Offset(wPx / 2, hPx - 12));
    paintCentered(lLabel, Offset(-14, hPx / 2), vertical: true);
    paintWallLetter('D', Offset(12, hPx / 2));
  }

  void _drawGrid(Canvas canvas, Size size, double pxf) {
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
    final step = pxf.clamp(4.0, 200.0);
    for (double i = ox; i <= size.width; i += step) {
      final isMajor = ((i - ox) / step).round() % 5 == 0;
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), isMajor ? major : paint);
    }
    for (double i = ox - step; i >= 0; i -= step) {
      final isMajor = ((ox - i) / step).round() % 5 == 0;
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), isMajor ? major : paint);
    }
    for (double i = oy; i <= size.height; i += step) {
      final isMajor = ((i - oy) / step).round() % 5 == 0;
      canvas.drawLine(Offset(0, i), Offset(size.width, i), isMajor ? major : paint);
    }
    for (double i = oy - step; i >= 0; i -= step) {
      final isMajor = ((oy - i) / step).round() % 5 == 0;
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
        // +148: rect rooms use gapped closed walls in outline; freehand walls still draw.
        if (!room.isPolygonFloor &&
            room.strokes.where((s) => s.type == StrokeType.wall).length >= 4) {
          // Skip full perimeter walls — already drawn with gaps. Keep partial freehand.
          final spxf = (pixelsPerFoot.isFinite && pixelsPerFoot > 0.5)
              ? pixelsPerFoot
              : 20.0;
          final wPx = room.widthInFeet * spxf;
          final hPx = room.lengthInFeet * spxf;
          final a = stroke.points.first;
          final b = stroke.points.last;
          final looksPerimeter = BlueprintOpenings.wallIndexForOpening(
                a,
                b,
                wPx: wPx,
                hPx: hPx,
                tol: 12,
              ) !=
              null;
          if (looksPerimeter) break;
        }
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
          ..color = Colors.orange.shade700
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 3.5;
        // Solid threshold line across the wall gap (not dashed on top of wall)
        canvas.drawPath(path, paint);
        _drawDoorArc(canvas, stroke.points.first, stroke.points.last);
        break;
      case StrokeType.window:
        final paint = Paint()
          ..color = Colors.blue.shade600
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 5.0;
        canvas.drawPath(path, paint);
        final innerPaint = Paint()
          ..color = Colors.lightBlue.shade100
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
    final wPx = room.widthInFeet *
        (pixelsPerFoot.isFinite && pixelsPerFoot > 0.5 ? pixelsPerFoot : 20);
    final hPx = room.lengthInFeet *
        (pixelsPerFoot.isFinite && pixelsPerFoot > 0.5 ? pixelsPerFoot : 20);
    final swing = BlueprintOpenings.bestInwardDoorSwing(
      p1,
      p2,
      roomWPx: wPx,
      roomHPx: hPx,
    );
    final hinge = swing.hinge;
    final r = swing.radius;
    final angle = swing.startAngle;
    final sweep = swing.sweep;

    // Filled swing sector (traffic-light keep-out visual, Phase 3.3)
    final fill = Paint()
      ..color = Colors.orange.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(hinge.dx, hinge.dy)
      ..arcTo(
        Rect.fromCircle(center: hinge, radius: r),
        angle,
        sweep,
        false,
      )
      ..close();
    canvas.drawPath(path, fill);

    final paint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawArc(
      Rect.fromCircle(center: hinge, radius: r),
      angle,
      sweep,
      false,
      paint,
    );
    // Open leaf edge
    final end = Offset(
      hinge.dx + r * cos(angle + sweep),
      hinge.dy + r * sin(angle + sweep),
    );
    canvas.drawLine(
      hinge,
      end,
      Paint()
        ..color = Colors.orange.shade800.withValues(alpha: 0.7)
        ..strokeWidth = 2.0,
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

  void _drawMeasurements(Canvas canvas, StrokeModel stroke, double pxf) {
    if (stroke.points.length < 2) return;
    // Perimeter wall strokes are dimmed via edge dims; skip noisy mid-wall labels
    if (stroke.type == StrokeType.wall &&
        !room.isPolygonFloor &&
        room.strokes.where((s) => s.type == StrokeType.wall).length >= 4) {
      return;
    }
    for (var i = 0; i < stroke.points.length - 1; i++) {
      final p1 = stroke.points[i];
      final p2 = stroke.points[i + 1];
      final dist = (p1 - p2).distance;

      if (dist > pxf * 0.4) {
        final lengthInFeet = dist / pxf;
        // +148: openings show type + width (Door 2.8′, Win 4.0′)
        final label = stroke.type == StrokeType.wall
            ? LengthFormat.formatFeet(lengthInFeet, unitSystem)
            : BlueprintOpenings.openingLabel(stroke.type, lengthInFeet);
        final textPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final midPoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final bgColor = switch (stroke.type) {
          StrokeType.door => Colors.orange.shade800.withValues(alpha: 0.85),
          StrokeType.window => Colors.blue.shade800.withValues(alpha: 0.85),
          StrokeType.balcony => Colors.green.shade800.withValues(alpha: 0.85),
          StrokeType.wall => Colors.black.withValues(alpha: 0.65),
        };
        final bg = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: midPoint.translate(0, -10),
            width: textPainter.width + 8,
            height: textPainter.height + 4,
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(bg, Paint()..color = bgColor);
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
