import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/units.dart';
import '../models/room_model.dart';
import '../painters/blueprint_painter.dart';
import '../painters/furniture_painter.dart';

/// Renders a room blueprint to PNG and shares it.
class ExportService {
  /// Pixel size of export canvas (includes padding).
  static Size exportSize(RoomModel room, double pixelsPerFoot) {
    final w = room.widthInFeet * pixelsPerFoot + 48;
    final h = room.lengthInFeet * pixelsPerFoot + 64;
    return Size(math.max(w, 320), math.max(h, 320));
  }

  static Future<Uint8List> renderPng(
    RoomModel room, {
    double pixelsPerFoot = 20,
    UnitSystem unitSystem = UnitSystem.feet,
  }) async {
    final size = exportSize(room, pixelsPerFoot);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF5F5F5),
    );

    // Offset content with padding
    canvas.save();
    canvas.translate(24, 24);

    final paintSize = Size(
      room.widthInFeet * pixelsPerFoot + 8,
      room.lengthInFeet * pixelsPerFoot + 24,
    );

    BlueprintPainter(
      room: room,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
    ).paint(canvas, paintSize);

    FurniturePainter(
      furniture: room.furniture,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
    ).paint(canvas, paintSize);

    canvas.restore();

    // Title
    final tp = TextPainter(
      text: TextSpan(
        text: room.name,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);
    tp.paint(canvas, const Offset(8, 4));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.ceil(),
      size.height.ceil(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw Exception('Failed to encode PNG');
    }
    return bytes.buffer.asUint8List();
  }

  static Future<void> sharePng(
    RoomModel room, {
    double pixelsPerFoot = 20,
    UnitSystem unitSystem = UnitSystem.feet,
  }) async {
    final png = await renderPng(
      room,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
    );
    final dir = await getTemporaryDirectory();
    final safeName = room.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/roomcraft_${safeName}_${room.id.substring(0, 6)}.png');
    await file.writeAsBytes(png, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png', name: '$safeName.png')],
      text: 'RoomCraft plan: ${room.name}',
    );
  }
}
