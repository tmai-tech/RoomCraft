import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../catalog/furniture_catalog.dart';
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
    ).paint(canvas, paintSize);

    FurniturePainter(
      furniture: room.furniture,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
    ).paint(canvas, paintSize);

    canvas.restore();

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


  /// High-resolution 3D perspective snapshot (free HD product export).
  /// Not photoreal mesh — high-DPI walkthrough render of the measured plan.
  static Future<Uint8List> render3dPng(
    RoomModel room, {
    double pixelsPerFoot = 28,
    UnitSystem unitSystem = UnitSystem.feet,
    double yaw = 0.35,
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
  }) async {
    final bytes = await render3dPng(
      room,
      pixelsPerFoot: pixelsPerFoot,
      unitSystem: unitSystem,
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

  /// Minimal one-page PDF: plan summary (dimensions + furniture list).
  /// Image embedding avoided to keep deps light (png share remains primary).
  static Uint8List buildPlanPdfBytes(
    RoomModel room, {
    UnitSystem unitSystem = UnitSystem.feet,
  }) {
    final dim =
        '${LengthFormat.formatFeet(room.widthInFeet, unitSystem)} × '
        '${LengthFormat.formatFeet(room.lengthInFeet, unitSystem)}';
    final lines = <String>[
      'RoomCraft plan',
      room.name,
      'Size: $dim',
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
