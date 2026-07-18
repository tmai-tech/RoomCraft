import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../catalog/furniture_catalog.dart';
import '../domain/layout/layout_score.dart';
import '../domain/layout/walkway_heatmap.dart';
import '../domain/units.dart';
import '../models/room_model.dart';
import '../painters/blueprint_painter.dart';
import '../painters/furniture_painter.dart';
import '../painters/isometric_painter.dart';

/// Renders a room blueprint to PNG/PDF and shares it.
class ExportService {
  static Size exportSize(RoomModel room, double pixelsPerFoot) {
    final w = room.widthInFeet * pixelsPerFoot + 48;
    final h = room.lengthInFeet * pixelsPerFoot + 64;
    return Size(math.max(w, 320), math.max(h, 320));
  }

  static Future<Uint8List> renderPng(
    RoomModel room, {
    double pixelsPerFoot = 20,
    UnitSystem unitSystem = UnitSystem.feet,
    bool showWalkwayHeatmap = false,
  }) async {
    final size = exportSize(room, pixelsPerFoot);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF5F5F5),
    );

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
      showWalkwayHeatmap: showWalkwayHeatmap,
    ).paint(canvas, paintSize);

    FurniturePainter(
      furniture: room.furniture,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
    ).paint(canvas, paintSize);

    canvas.restore();

    final score = LayoutScore.evaluate(room, pixelsPerFoot).score;
    final freePct = (WalkwayHeatmap.freeFraction(
              WalkwayHeatmap.compute(room, pixelsPerFoot),
            ) *
            100)
        .round();
    final title =
        '${room.name} · ${room.spaceLabel} · score $score · walkways $freePct%';
    final tp = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 16);
    tp.paint(canvas, const Offset(8, 4));

    if (showWalkwayHeatmap) {
      final legend = TextPainter(
        text: const TextSpan(
          text: 'Walkways: green free · orange door · red blocked',
          style: TextStyle(color: Colors.black54, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 16);
      legend.paint(canvas, Offset(8, size.height - 18));
    }

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


  /// High-resolution 3D perspective snapshot (free HD product export).
  /// Not photoreal mesh — high-DPI walkthrough render of the measured plan.
  static Future<Uint8List> render3dPng(
    RoomModel room, {
    double pixelsPerFoot = 28,
    UnitSystem unitSystem = UnitSystem.feet,
    double yaw = 0.35,
    SceneLighting lighting = SceneLighting.day,
  }) async {
    const size = Size(1600, 1200);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    IsometricPainter(
      room: room,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
      yaw: yaw,
      perspective: true,
      wallHeightFt: 8.5,
      lighting: lighting,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw Exception('Failed to encode 3D PNG');
    return bytes.buffer.asUint8List();
  }

  static Future<void> share3dPng(
    RoomModel room, {
    double pixelsPerFoot = 28,
    UnitSystem unitSystem = UnitSystem.feet,
    SceneLighting lighting = SceneLighting.day,
  }) async {
    final bytes = await render3dPng(
      room,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
      lighting: lighting,
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/roomcraft_3d_${room.name.replaceAll(' ', '_')}.png',
    );
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'RoomCraft 3D walkthrough — ${room.name}',
    );
  }

  /// Phone-portrait marketing frame for Play store screenshots (free path).
  /// 1080×1920 with brand bar + 2D plan (optional walkway heatmap).
  static Future<Uint8List> renderStoreScreenshot(
    RoomModel room, {
    double pixelsPerFoot = 22,
    UnitSystem unitSystem = UnitSystem.feet,
    bool showWalkwayHeatmap = true,
  }) async {
    const size = Size(1080, 1920);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Brand gradient background
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D47A1),
            Color(0xFF00695C),
            Color(0xFF004D40),
          ],
        ).createShader(Offset.zero & size),
    );

    final title = TextPainter(
      text: const TextSpan(
        text: 'RoomCraft',
        style: TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 80);
    title.paint(canvas, const Offset(48, 64));

    final sub = TextPainter(
      text: TextSpan(
        text: '${room.name} · ${room.spaceLabel}',
        style: const TextStyle(color: Colors.white70, fontSize: 28),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 80);
    sub.paint(canvas, const Offset(48, 128));

    // Plan card
    const card = Rect.fromLTWH(40, 220, 1000, 1200);
    final rrect = RRect.fromRectAndRadius(card, const Radius.circular(28));
    canvas.drawRRect(rrect, Paint()..color = const Color(0xFFF5F7FA));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.translate(card.left + 40, card.top + 40);

    final planW = room.widthInFeet * pixelsPerFoot;
    final planH = room.lengthInFeet * pixelsPerFoot;
    final maxW = card.width - 80;
    final maxH = card.height - 80;
    final scale = (maxW / planW < maxH / planH) ? maxW / planW : maxH / planH;
    final pxf = pixelsPerFoot * scale.clamp(0.5, 3.0);
    final paintSize = Size(
      room.widthInFeet * pxf + 16,
      room.lengthInFeet * pxf + 40,
    );
    BlueprintPainter(
      room: room,
      pixelsPerFoot: pxf,
      unitSystem: unitSystem,
      showWalkwayHeatmap: showWalkwayHeatmap,
    ).paint(canvas, paintSize);
    FurniturePainter(
      furniture: room.furniture,
      pixelsPerFoot: pxf,
      unitSystem: unitSystem,
    ).paint(canvas, paintSize);
    canvas.restore();

    final footer = TextPainter(
      text: const TextSpan(
        text: 'AR measure · 10k free catalogue · 3D walkthrough',
        style: TextStyle(color: Colors.white70, fontSize: 22),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 80);
    footer.paint(canvas, Offset(48, size.height - 120));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw Exception('Failed to encode store screenshot');
    return bytes.buffer.asUint8List();
  }

  static Future<void> shareStoreScreenshot(
    RoomModel room, {
    double pixelsPerFoot = 22,
    UnitSystem unitSystem = UnitSystem.feet,
  }) async {
    final png = await renderStoreScreenshot(
      room,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
    );
    final dir = await getTemporaryDirectory();
    final safe = room.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/roomcraft_store_${safe}.png');
    await file.writeAsBytes(png, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png', name: '${safe}_store.png')],
      text: 'RoomCraft store screenshot — ${room.name}',
    );
  }

  /// Share 2D plan + 3D walkthrough PNGs together (Play-style plan pack).
  static Future<void> sharePlanPack(
    RoomModel room, {
    double pixelsPerFoot = 20,
    UnitSystem unitSystem = UnitSystem.feet,
    SceneLighting lighting = SceneLighting.day,
  }) async {
    final png2d = await renderPng(
      room,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
    );
    final png3d = await render3dPng(
      room,
      unitSystem: unitSystem,
      lighting: lighting,
    );
    final dir = await getTemporaryDirectory();
    final safe = room.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final f2 = File('${dir.path}/roomcraft_${safe}_2d.png');
    final f3 = File('${dir.path}/roomcraft_${safe}_3d.png');
    await f2.writeAsBytes(png2d, flush: true);
    await f3.writeAsBytes(png3d, flush: true);
    await Share.shareXFiles(
      [
        XFile(f2.path, mimeType: 'image/png', name: '${safe}_2d.png'),
        XFile(f3.path, mimeType: 'image/png', name: '${safe}_3d.png'),
      ],
      text: 'RoomCraft plan pack: ${room.name} (${room.spaceLabel})',
    );
  }

  /// Minimal one-page PDF: plan summary (dimensions + furniture list).
  /// Image embedding avoided to keep deps light (png share remains primary).
  static Uint8List buildPlanPdfBytes(
    RoomModel room, {
    UnitSystem unitSystem = UnitSystem.feet,
  }) {
    final dim =
        '${LengthFormat.formatFeet(room.widthInFeet, unitSystem)} × '
        '${LengthFormat.formatFeet(room.lengthInFeet, unitSystem)}';
    final shape = room.isPolygonFloor
        ? 'L-shape / polygon floor (${room.floorPolygonFt!.length} pts)'
        : 'Rectangle floor';
    final lines = <String>[
      'RoomCraft plan',
      room.name,
      'Size: $dim',
      'Shape: $shape',
      'Level: ${room.spaceLabel}',
      'Furniture: ${room.furniture.length} · Lines: ${room.strokes.length}',
      '',
      'Furniture list:',
    ];
    if (room.furniture.isEmpty) {
      lines.add('  (none)');
    } else {
      for (var i = 0; i < room.furniture.length; i++) {
        final f = room.furniture[i];
        final label = FurnitureCatalog.entryFor(f.type).label;
        final fs =
            '${LengthFormat.formatFeet(f.widthInFeet, unitSystem)} × '
            '${LengthFormat.formatFeet(f.lengthInFeet, unitSystem)}';
        lines.add('  ${i + 1}. $label — $fs');
      }
    }
    lines.add('');
    lines.add('Generated by RoomCraft · measured layout sketch');
    return _simpleTextPdf(lines);
  }

  static Future<void> sharePng(
    RoomModel room, {
    double pixelsPerFoot = 20,
    UnitSystem unitSystem = UnitSystem.feet,
    bool showWalkwayHeatmap = false,
  }) async {
    final png = await renderPng(
      room,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
      showWalkwayHeatmap: showWalkwayHeatmap,
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

  static Future<void> sharePdf(
    RoomModel room, {
    UnitSystem unitSystem = UnitSystem.feet,
  }) async {
    final pdf = buildPlanPdfBytes(room, unitSystem: unitSystem);
    final dir = await getTemporaryDirectory();
    final safeName = room.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/roomcraft_${safeName}_${room.id.substring(0, 6)}.pdf');
    await file.writeAsBytes(pdf, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: '$safeName.pdf')],
      text: 'RoomCraft plan PDF: ${room.name}',
    );
  }

  /// Minimal PDF 1.4 with Helvetica text lines (Latin-1 safe).
  static Uint8List _simpleTextPdf(List<String> lines) {
    final sanitized = lines.map(_pdfSafe).toList();
    final content = StringBuffer('BT /F1 12 Tf 50 780 Td 14 TL\n');
    for (var i = 0; i < sanitized.length; i++) {
      if (i == 0) {
        content.writeln('/F1 16 Tf (${sanitized[i]}) Tj');
        content.writeln('/F1 12 Tf T*');
      } else {
        content.writeln('(${sanitized[i]}) Tj T*');
      }
    }
    content.write('ET');
    final stream = content.toString();

    // Build with byte offsets
    final parts = <List<int>>[];
    void add(String s) => parts.add(utf8.encode(s));

    add('%PDF-1.4\n');
    final offsets = <int>[];
    var pos = utf8.encode('%PDF-1.4\n').length;

    void addObj(String body) {
      offsets.add(pos);
      final b = utf8.encode(body);
      parts.add(b);
      pos += b.length;
    }

    addObj('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n');
    addObj('2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n');
    addObj(
      '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>endobj\n',
    );
    final streamBytes = utf8.encode(stream);
    addObj(
      '4 0 obj<< /Length ${streamBytes.length} >>stream\n$stream\nendstream\nendobj\n',
    );
    addObj('5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj\n');

    final xrefPos = pos;
    final xref = StringBuffer('xref\n0 ${offsets.length + 1}\n');
    xref.writeln('0000000000 65535 f ');
    for (final o in offsets) {
      xref.writeln('${o.toString().padLeft(10, '0')} 00000 n ');
    }
    xref.writeln('trailer<< /Size ${offsets.length + 1} /Root 1 0 R >>');
    xref.writeln('startxref');
    xref.writeln('$xrefPos');
    xref.write('%%EOF');
    parts.add(utf8.encode(xref.toString()));

    final out = BytesBuilder();
    for (final p in parts) {
      out.add(p);
    }
    return out.toBytes();
  }

  static String _pdfSafe(String s) {
    return s
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
  }
}
