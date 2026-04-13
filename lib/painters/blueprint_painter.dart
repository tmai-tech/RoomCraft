import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/stroke_model.dart';
import '../models/room_model.dart';

class BlueprintPainter extends CustomPainter {
  final RoomModel room;
  final StrokeModel? currentStroke;
  final double pixelsPerFoot;

  BlueprintPainter({
    required this.room,
    this.currentStroke,
    required this.pixelsPerFoot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);

    // Draw saved strokes
    for (var stroke in room.strokes) {
      _drawStroke(canvas, stroke);
      _drawMeasurements(canvas, stroke);
    }

    // Draw current active stroke
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
      _drawMeasurements(canvas, currentStroke!);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (double i = 0; i <= size.width; i += pixelsPerFoot) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i <= size.height; i += pixelsPerFoot) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
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

    Paint paint;
    switch (stroke.type) {
      case StrokeType.wall:
        paint = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 8.0;
        canvas.drawPath(path, paint);
        break;
      case StrokeType.door:
        // Draw dashed orange line for wall opening
        paint = Paint()
          ..color = Colors.orange
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 4.0;
        
        _drawDashedPath(canvas, path, paint);
        // Draw the door arc swinging
        _drawDoorArc(canvas, stroke.points.first, stroke.points.last);
        break;
      case StrokeType.window:
        // Draw blue double line
        paint = Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 6.0;
        canvas.drawPath(path, paint);
        // Inner white line
        final innerPaint = Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
        canvas.drawPath(path, innerPaint);
        break;
    }
  }

  void _drawPoint(Canvas canvas, Offset p, StrokeType type) {
    final paint = Paint()
      ..style = PaintingStyle.fill;
    
    if (type == StrokeType.wall) {
      paint.color = Colors.black;
      canvas.drawCircle(p, 4.0, paint);
    } else if (type == StrokeType.door) {
      paint.color = Colors.orange;
      canvas.drawCircle(p, 2.0, paint);
    } else if (type == StrokeType.window) {
      paint.color = Colors.blue;
      canvas.drawCircle(p, 3.0, paint);
    }
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    const double dashWidth = 10, dashSpace = 5;
    double distance = 0.0;
    for (PathMetric pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        final Path extractPath = pathMetric.extractPath(distance, distance + dashWidth);
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
    
    final paint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawArc(
      Rect.fromCircle(center: p1, radius: r),
      angle,
      pi / 2, // 90 degree swing
      false,
      paint,
    );
  }

  void _drawMeasurements(Canvas canvas, StrokeModel stroke) {
    if (stroke.points.length < 2) return;
    for (var i = 0; i < stroke.points.length - 1; i++) {
       final p1 = stroke.points[i];
       final p2 = stroke.points[i+1];
       final dist = (p1 - p2).distance;

       // Only draw measurement for significant segments
       if (dist > pixelsPerFoot * 0.5) {
         final lengthInFeet = dist / pixelsPerFoot;
         final textSpan = TextSpan(
           text: '${lengthInFeet.toStringAsFixed(1)} ft',
           style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, backgroundColor: Colors.black54),
         );
         final textPainter = TextPainter(
           text: textSpan,
           textDirection: TextDirection.ltr,
         );
         textPainter.layout();
         
         final midPoint = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
         textPainter.paint(canvas, Offset(midPoint.dx - textPainter.width/2, midPoint.dy - textPainter.height - 5));
       }
    }
  }

  @override
  bool shouldRepaint(BlueprintPainter oldDelegate) {
    // For simplicity, always repaint.
    return true; 
  }
}
