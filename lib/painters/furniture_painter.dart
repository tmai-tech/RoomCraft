import 'package:flutter/material.dart';

import '../catalog/furniture_catalog.dart';
import '../domain/units.dart';
import '../models/furniture_item.dart';

class FurniturePainter extends CustomPainter {
  final List<FurnitureItem> furniture;
  final String? selectedId;
  final Set<String> selectedIds;
  final double pixelsPerFoot;
  final UnitSystem unitSystem;
  final Set<String> collisionIds;
  final bool showRotateHandle;
  /// Matches [BlueprintPainter.origin] — model (0,0) is at this offset.
  final Offset origin;

  FurniturePainter({
    required this.furniture,
    this.selectedId,
    this.selectedIds = const {},
    required this.pixelsPerFoot,
    this.unitSystem = UnitSystem.feet,
    this.collisionIds = const {},
    this.showRotateHandle = true,
    this.origin = Offset.zero,
  });

  bool _isSelected(String id) =>
      id == selectedId || selectedIds.contains(id);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    for (final item in furniture) {
      _drawFurnitureItem(
        canvas,
        item,
        _isSelected(item.id),
        collisionIds.contains(item.id),
        primary: item.id == selectedId,
      );
    }
    canvas.restore();
  }

  void _drawFurnitureItem(
    Canvas canvas,
    FurnitureItem item,
    bool isSelected,
    bool inCollision, {
    bool primary = false,
  }) {
    canvas.save();
    canvas.translate(item.position.dx, item.position.dy);
    canvas.rotate(item.rotationAngle);

    final itemWidth = item.widthInFeet * pixelsPerFoot;
    final itemLength = item.lengthInFeet * pixelsPerFoot;

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: itemWidth,
      height: itemLength,
    );

    final boxPaint = Paint()
      ..color = _getColorForType(item.type)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = inCollision ? Colors.red : Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = inCollision ? 3.0 : 2.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      boxPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      borderPaint,
    );

    _drawDetailsForType(canvas, rect, item.type);

    if (inCollision && !isSelected) {
      final err = Paint()
        ..color = Colors.red.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(3)),
        err,
      );
    }

    if (isSelected) {
      final highlightPaint = Paint()
        ..color = inCollision ? Colors.redAccent : Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(5), const Radius.circular(4)),
        highlightPaint,
      );
      final handle = Paint()..color = Colors.amber.shade700;
      for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
        canvas.drawCircle(c, 4, handle);
      }
      // Rotate handle (above item, local -Y)
      if (showRotateHandle && primary) {
        final hy = rect.top - 22;
        final stem = Paint()
          ..color = Colors.amber.shade800
          ..strokeWidth = 2;
        canvas.drawLine(Offset(0, rect.top), Offset(0, hy), stem);
        canvas.drawCircle(Offset(0, hy), 9, Paint()..color = Colors.amber.shade700);
        canvas.drawCircle(
          Offset(0, hy),
          9,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        // small curved arrow mark
        canvas.drawArc(
          Rect.fromCircle(center: Offset(0, hy), radius: 5),
          -2.2,
          2.5,
          false,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }

    final entry = item.catalogId != null
        ? (FurnitureCatalog.byId(item.catalogId!) ?? FurnitureCatalog.entryFor(item.type))
        : FurnitureCatalog.entryFor(item.type);
    final dim = '${LengthFormat.formatFeet(item.widthInFeet, unitSystem, decimals: 1)}'
        '×${LengthFormat.formatFeet(item.lengthInFeet, unitSystem, decimals: 1)}';
    final textPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '${entry.label}\n',
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: dim,
            style: const TextStyle(color: Colors.black54, fontSize: 9),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: itemWidth - 4);
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }

  Color _getColorForType(FurnitureType type) => type.planColor;

  void _drawDetailsForType(Canvas canvas, Rect rect, FurnitureType type) {
    final detailPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    switch (type) {
      case FurnitureType.bed:
        canvas.drawRect(
          Rect.fromLTWH(rect.left + 5, rect.top + 5, rect.width / 2 - 10, rect.height / 4 - 5),
          detailPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.center.dx + 5, rect.top + 5, rect.width / 2 - 10, rect.height / 4 - 5),
          detailPaint,
        );
        canvas.drawLine(
          Offset(rect.left, rect.top + rect.height / 3),
          Offset(rect.right, rect.top + rect.height / 3),
          detailPaint,
        );
        break;
      case FurnitureType.sofa:
        canvas.drawLine(
          Offset(rect.center.dx, rect.top + 5),
          Offset(rect.center.dx, rect.bottom),
          detailPaint,
        );
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
  bool shouldRepaint(FurniturePainter oldDelegate) => true;
}
