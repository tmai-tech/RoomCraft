import 'package:flutter/material.dart';
import '../models/furniture_item.dart';

class FurniturePainter extends CustomPainter {
  final List<FurnitureItem> furniture;
  final String? selectedId;
  final double pixelsPerFoot;

  FurniturePainter({
    required this.furniture,
    this.selectedId,
    required this.pixelsPerFoot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var item in furniture) {
      _drawFurnitureItem(canvas, item, item.id == selectedId);
    }
  }

  void _drawFurnitureItem(Canvas canvas, FurnitureItem item, bool isSelected) {
    canvas.save();
    
    // Move to item position
    canvas.translate(item.position.dx, item.position.dy);
    canvas.rotate(item.rotationAngle);

    final itemWidth = item.widthInFeet * pixelsPerFoot;
    final itemLength = item.lengthInFeet * pixelsPerFoot;

    // Draw base rectangle
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: itemWidth,
      height: itemLength,
    );

    final boxPaint = Paint()
      ..color = _getColorForType(item.type)
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(rect, boxPaint);
    canvas.drawRect(rect, borderPaint);

    // Draw specific details based on type (Top down symbols)
    _drawDetailsForType(canvas, rect, item.type);

    // Draw selection highlights
    if (isSelected) {
      final highlightPaint = Paint()
        ..color = Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRect(rect.inflate(4.0), highlightPaint);
    }

    // Draw string representing dimensions.
    final textSpan = TextSpan(
      text: '${item.widthInFeet.toStringAsFixed(1)}x${item.lengthInFeet.toStringAsFixed(1)}',
      style: const TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));

    canvas.restore();
  }

  Color _getColorForType(FurnitureType type) {
    switch (type) {
      case FurnitureType.bed: return Colors.blue.shade100;
      case FurnitureType.sofa: return Colors.teal.shade100;
      case FurnitureType.table: return Colors.brown.shade200;
      case FurnitureType.chair: return Colors.brown.shade300;
      case FurnitureType.wardrobe: return Colors.brown.shade400;
      case FurnitureType.tvUnit: return Colors.grey.shade400;
      case FurnitureType.bookshelf: return Colors.orange.shade200;
      case FurnitureType.nightstand: return Colors.brown.shade100;
    }
  }

  void _drawDetailsForType(Canvas canvas, Rect rect, FurnitureType type) {
    final detailPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    switch (type) {
      case FurnitureType.bed:
        // Pillows
        canvas.drawRect(Rect.fromLTWH(rect.left + 5, rect.top + 5, rect.width / 2 - 10, rect.height / 4 - 5), detailPaint);
        canvas.drawRect(Rect.fromLTWH(rect.center.dx + 5, rect.top + 5, rect.width / 2 - 10, rect.height / 4 - 5), detailPaint);
        // Blanket line
        canvas.drawLine(Offset(rect.left, rect.top + rect.height / 3), Offset(rect.right, rect.top + rect.height / 3), detailPaint);
        break;
      case FurnitureType.sofa:
        // Cushions
        canvas.drawLine(Offset(rect.center.dx, rect.top + 5), Offset(rect.center.dx, rect.bottom), detailPaint);
        // Armrests
        canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, 10, rect.height), detailPaint);
        canvas.drawRect(Rect.fromLTWH(rect.right - 10, rect.top, 10, rect.height), detailPaint);
        break;
      case FurnitureType.table:
        canvas.drawLine(rect.topLeft, rect.bottomRight, detailPaint);
        canvas.drawLine(rect.topRight, rect.bottomLeft, detailPaint);
        break;
      default:
        break; 
    }
  }

  @override
  bool shouldRepaint(FurniturePainter oldDelegate) {
    return true; 
  }
}
