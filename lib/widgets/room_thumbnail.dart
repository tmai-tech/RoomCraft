import 'package:flutter/material.dart';

import '../models/room_model.dart';
import '../models/stroke_model.dart';

/// Compact top-down preview of a saved room for the home list.
class RoomThumbnail extends StatelessWidget {
  final RoomModel room;
  final double size;

  const RoomThumbnail({
    super.key,
    required this.room,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: size,
        height: size,
        color: Colors.blueGrey.shade50,
        child: CustomPaint(
          painter: _ThumbPainter(room: room),
          size: Size(size, size),
        ),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  final RoomModel room;
  _ThumbPainter({required this.room});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final rw = room.widthInFeet <= 0 ? 10.0 : room.widthInFeet;
    final rh = room.lengthInFeet <= 0 ? 10.0 : room.lengthInFeet;
    final scale = ((size.width - pad * 2) / rw)
        .clamp(0.0, (size.height - pad * 2) / rh);

    canvas.translate(pad, pad);

    final roomRect = Rect.fromLTWH(0, 0, rw * scale, rh * scale);
    canvas.drawRect(roomRect, Paint()..color = Colors.white);
    canvas.drawRect(
      roomRect,
      Paint()
        ..color = Colors.blueGrey.shade200
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Approximate strokes: stored in pixels at ~20 px/ft typically
    const pxf = 20.0;
    for (final s in room.strokes) {
      if (s.points.length < 2) continue;
      final p1 = Offset(
        (s.points.first.dx / pxf) * scale,
        (s.points.first.dy / pxf) * scale,
      );
      final p2 = Offset(
        (s.points.last.dx / pxf) * scale,
        (s.points.last.dy / pxf) * scale,
      );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = s.type == StrokeType.door
              ? Colors.orange
              : s.type == StrokeType.window
                  ? Colors.blue
                  : Colors.black87
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final f in room.furniture) {
      final cx = (f.position.dx / pxf) * scale;
      final cy = (f.position.dy / pxf) * scale;
      final w = f.widthInFeet * scale;
      final h = f.lengthInFeet * scale;
      final r = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
      canvas.drawRect(r, Paint()..color = Colors.teal.shade200);
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.teal.shade700
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter oldDelegate) =>
      oldDelegate.room != room;
}
