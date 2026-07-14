import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';

import '../config/app_config.dart';
import '../domain/scan_refine.dart';
import '../domain/wall_relative_scan.dart';
import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'free_vision_scanner.dart';

/// Per-wall vision: analyze ONE wall photo for openings + furniture on that wall.
///
/// Matches how competitors / designers work: measure room → capture each wall
/// → place features relative to that wall — not freeform LLM coordinates.
class WallRelativeVision {
  /// Analyze a single wall photo.
  static Future<({List<WallOpeningHint> openings, List<WallFurnitureHint> furniture, List<String> notes})>
      analyzeWall({
    required File image,
    required WallSide wall,
    required double roomWidthFt,
    required double roomLengthFt,
    String? apiKey,
  }) async {
    final key = await FreeVisionScanner.resolveApiKey(apiKey: apiKey);
    if (key == null || key.isEmpty) {
      throw Exception('No free vision key');
    }

    final wallLen = wall.lengthFt(roomWidthFt, roomLengthFt);
    final dataUrl = await _prepare(image);
    if (dataUrl == null) throw Exception('Could not read wall photo');

    final body = {
      'model': AppConfig.groqVisionModel,
      'temperature': 0.0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a surveyor assisting an interior designer. '
              'This photo shows ONE wall of a rectangular room. '
              'Report only openings and freestanding furniture on or against THIS wall. '
              'Use fractions 0–1 left-to-right as you face the wall. '
              'Never invent items. JSON only.',
        },
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': _wallPrompt(wall, wallLen, roomWidthFt, roomLengthFt)},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ],
    };

    final response = await http
        .post(
          Uri.parse(AppConfig.groqChatCompletionsUrl),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Wall vision ${response.statusCode}: ${_short(response.body)}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('Empty vision response');
    }
    final msg = (choices.first as Map)['message'];
    final text = msg is Map ? msg['content']?.toString() : null;
    if (text == null || text.isEmpty) throw Exception('Empty content');

    final json = _jsonMap(text);
    return _parseWallJson(json, wall, wallLen);
  }

  /// Overview photo: free furniture positions as fractions of room (0–1).
  static Future<List<WallFurnitureHint>> analyzeOverview({
    required File image,
    required double roomWidthFt,
    required double roomLengthFt,
    String? apiKey,
  }) async {
    final key = await FreeVisionScanner.resolveApiKey(apiKey: apiKey);
    if (key == null || key.isEmpty) return [];

    final dataUrl = await _prepare(image);
    if (dataUrl == null) return [];

    final body = {
      'model': AppConfig.groqVisionModel,
      'temperature': 0.0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content':
              'Interior designer overview. List freestanding furniture only if clearly visible. '
              'Positions as fractions of room: x_frac 0=left wall, 1=right; y_frac 0=near/first wall, 1=far. '
              'Never invent. JSON only.',
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': '''
Room is ${roomWidthFt.toStringAsFixed(1)} ft wide × ${roomLengthFt.toStringAsFixed(1)} ft long.
Return JSON:
{"furniture":[{"type":"TABLE","x_frac":0.5,"y_frac":0.4,"w_ft":3,"l_ft":2,"rot_deg":0,"confidence":0.9,"evidence":"..."}]}
Types: BED,WARDROBE,SOFA,TABLE,CHAIR,TV_UNIT,BOOKSHELF,NIGHTSTAND
Empty furniture [] if unsure. confidence>=0.8 to include.
''',
            },
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ],
    };

    final response = await http
        .post(
          Uri.parse(AppConfig.groqChatCompletionsUrl),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return [];
    final msg = (choices.first as Map)['message'];
    final text = msg is Map ? msg['content']?.toString() : null;
    if (text == null) return [];
    final json = _jsonMap(text);
    final list = json['furniture'];
    if (list is! List) return [];

    final out = <WallFurnitureHint>[];
    for (final item in list) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final conf = _num(m['confidence']) ?? 0;
      if (conf < 0.75) continue;
      final type = _type(m['type']?.toString());
      if (type == null) continue;
      final xf = (_num(m['x_frac']) ?? 0.5).clamp(0.05, 0.95);
      final yf = (_num(m['y_frac']) ?? 0.5).clamp(0.05, 0.95);
      out.add(WallFurnitureHint(
        type: type,
        freePlace: true,
        freeXFt: xf * roomWidthFt,
        freeYFt: yf * roomLengthFt,
        widthFt: (_num(m['w_ft']) ?? 3).clamp(0.5, 12),
        lengthFt: (_num(m['l_ft']) ?? 2).clamp(0.5, 12),
        rotDeg: _num(m['rot_deg']) ?? 0,
        confidence: conf,
        evidence: m['evidence']?.toString() ?? '',
      ));
    }
    return out;
  }

  /// Full wall-by-wall pipeline.
  static Future<ScanResult> scanWallByWall({
    required Map<WallSide, File> wallPhotos,
    required double roomWidthFt,
    required double roomLengthFt,
    List<File> overviewPhotos = const [],
    String? apiKey,
  }) async {
    final openings = <WallOpeningHint>[];
    final furniture = <WallFurnitureHint>[];
    final notes = <String>[];

    for (final side in WallSide.values) {
      final photo = wallPhotos[side];
      if (photo == null) {
        notes.add('${side.shortLabel}: no photo — openings/furniture on that wall skipped');
        continue;
      }
      try {
        final r = await analyzeWall(
          image: photo,
          wall: side,
          roomWidthFt: roomWidthFt,
          roomLengthFt: roomLengthFt,
          apiKey: apiKey,
        );
        openings.addAll(r.openings);
        furniture.addAll(r.furniture);
        notes.addAll(r.notes);
        notes.add(
          '${side.shortLabel}: ${r.openings.length} opening(s), '
          '${r.furniture.length} piece(s)',
        );
      } catch (e) {
        notes.add('${side.shortLabel} failed: $e');
      }
    }

    for (final ov in overviewPhotos.take(2)) {
      try {
        final free = await analyzeOverview(
          image: ov,
          roomWidthFt: roomWidthFt,
          roomLengthFt: roomLengthFt,
          apiKey: apiKey,
        );
        // Prefer wall-anchored; add free only if not redundant type near wall
        furniture.addAll(free);
        notes.add('Overview: +${free.length} free-placed piece(s)');
      } catch (e) {
        notes.add('Overview skip: $e');
      }
    }

    // Dedupe free vs wall furniture of same type close together — simple: keep all wall-anchored first
    final wallAnchored = furniture.where((f) => !f.freePlace).toList();
    final freeOnly = furniture.where((f) => f.freePlace).toList();
    // Drop free items if we already have same type from a wall
    final wallTypes = wallAnchored.map((f) => f.type).toSet();
    final merged = [
      ...wallAnchored,
      ...freeOnly.where((f) => !wallTypes.contains(f.type)),
    ];

    return ScanRefine.refine(WallRelativeComposer.compose(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: openings,
      furniture: merged,
      warnings: notes,
      wallPhotos: wallPhotos.length,
      overviewPhotos: overviewPhotos.length,
    ));
  }

  static String _wallPrompt(
    WallSide wall,
    double wallLenFt,
    double roomW,
    double roomL,
  ) =>
      '''
This photo is ${wall.shortLabel} of a rectangular room (interior designer field survey).
Room size: ${roomW.toStringAsFixed(1)} ft (width) × ${roomL.toStringAsFixed(1)} ft (length).
THIS wall is EXACTLY ${wallLenFt.toStringAsFixed(1)} ft long (authoritative).

You are facing THIS wall from inside the room.
- Left side of the image = LEFT as you face the wall = t=0 / from_left_ft=0
- Right side of the image = RIGHT as you face the wall = t=1 / from_left_ft=${wallLenFt.toStringAsFixed(1)}

Prefer FEET along the wall (more accurate than pure fractions):
Return ONLY JSON:
{
  "openings": [
    {"type":"door","from_left_ft":2.5,"width_ft":3.0,"confidence":0.9,"evidence":"single door near left"}
  ],
  "furniture": [
    {"type":"SOFA","from_left_ft":5.0,"depth_ft":3.0,"w_ft":7,"l_ft":3,"confidence":0.9,"evidence":"sofa centered on wall"}
  ]
}

Rules (critical for plan accuracy):
1. openings type: door | window | balcony only. from_left_ft = left edge of opening from LEFT corner while facing wall.
2. width_ft must be realistic: door 2.5–3.5 ft typical, window 2–6 ft, balcony/sliding 4–10 ft. Never a whole-wall door.
3. Only openings ON this wall (door frame / glass / sliding track clearly on THIS wall). Empty [] if none visible.
4. furniture only against THIS wall. from_left_ft = center of piece from left corner. depth_ft = how far it sticks into room (bed ~6–7, sofa ~3, nightstand ~1.5).
5. Types: BED,WARDROBE,SOFA,TABLE,CHAIR,TV_UNIT,BOOKSHELF,NIGHTSTAND
6. Never invent. confidence < 0.75 → omit. If unsure about position, omit rather than guess.
7. Balcony = large glazed door / outdoor opening (not a normal window).
8. If photo is not clearly this wall, return empty arrays.
''';

  static ({List<WallOpeningHint> openings, List<WallFurnitureHint> furniture, List<String> notes})
      _parseWallJson(Map<String, dynamic> json, WallSide wall, double wallLen) {
    final notes = <String>[];
    final openings = <WallOpeningHint>[];
    final furniture = <WallFurnitureHint>[];

    final oRaw = json['openings'];
    if (oRaw is List) {
      for (final item in oRaw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final conf = _num(m['confidence']) ?? 0.8;
        if (conf < 0.68) continue;
        final type = _stroke(m['type']?.toString());
        if (type == null) continue;

        // Prefer feet-based (designer method); fall back to fractions.
        final fromLeft = _num(m['from_left_ft']);
        final widthFt = _num(m['width_ft']);
        if (fromLeft != null && widthFt != null) {
          openings.add(WallOpeningHint.fromLeft(
            wall: wall,
            type: type,
            fromLeftFt: fromLeft,
            widthFt: widthFt,
            wallLengthFt: wallLen,
            confidence: conf,
            evidence: m['evidence']?.toString() ?? 'vision feet',
          ));
          continue;
        }

        var t0 = (_num(m['t0']) ?? 0).clamp(0.0, 1.0);
        var t1 = (_num(m['t1']) ?? 0).clamp(0.0, 1.0);
        if (t1 < t0) {
          final tmp = t0;
          t0 = t1;
          t1 = tmp;
        }
        // Convert fraction span → feet then re-clamp with priors
        var span = (t1 - t0) * wallLen;
        if (span < 1.5) {
          span = OpeningPriors.defaultWidth(type);
        }
        span = OpeningPriors.clampWidth(type, span, wallLen);
        final mid = (t0 + t1) / 2;
        final fromL = (mid * wallLen - span / 2).clamp(0.0, wallLen - span);
        openings.add(WallOpeningHint.fromLeft(
          wall: wall,
          type: type,
          fromLeftFt: fromL,
          widthFt: span,
          wallLengthFt: wallLen,
          confidence: conf,
          evidence: m['evidence']?.toString() ?? 'vision frac',
        ));
      }
    }

    final fRaw = json['furniture'];
    if (fRaw is List) {
      for (final item in fRaw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final conf = _num(m['confidence']) ?? 0.8;
        if (conf < 0.72) continue;
        final type = _type(m['type']?.toString());
        if (type == null) continue;
        final fromLeft = _num(m['from_left_ft']);
        final wFt = (_num(m['w_ft']) ?? 3).clamp(0.5, 12).toDouble();
        final lFt = (_num(m['l_ft']) ?? 2).clamp(0.5, 12).toDouble();
        final depth = (_num(m['depth_ft']) ?? 1.5).clamp(0.5, 8).toDouble();
        if (fromLeft != null) {
          furniture.add(WallFurnitureHint.fromLeft(
            type: type,
            wall: wall,
            fromLeftFt: fromLeft,
            depthFt: depth,
            widthFt: wFt,
            lengthFt: lFt,
            wallLengthFt: wallLen,
            confidence: conf,
            evidence: m['evidence']?.toString() ?? '',
          ));
        } else {
          furniture.add(WallFurnitureHint(
            type: type,
            wall: wall,
            t: (_num(m['t']) ?? 0.5).clamp(0.05, 0.95),
            depthFt: depth,
            widthFt: wFt,
            lengthFt: lFt,
            confidence: conf,
            evidence: m['evidence']?.toString() ?? '',
          ));
        }
      }
    }

    return (openings: openings, furniture: furniture, notes: notes);
  }

  static StrokeType? _stroke(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'door':
        return StrokeType.door;
      case 'window':
        return StrokeType.window;
      case 'balcony':
        return StrokeType.balcony;
      default:
        return null;
    }
  }

  static FurnitureType? _type(String? raw) {
    if (raw == null) return null;
    final k = raw.trim().toUpperCase().replaceAll(' ', '_').replaceAll('-', '_');
    const map = {
      'BED': FurnitureType.bed,
      'WARDROBE': FurnitureType.wardrobe,
      'SOFA': FurnitureType.sofa,
      'COUCH': FurnitureType.sofa,
      'TABLE': FurnitureType.table,
      'DESK': FurnitureType.table,
      'CHAIR': FurnitureType.chair,
      'TV_UNIT': FurnitureType.tvUnit,
      'TV': FurnitureType.tvUnit,
      'BOOKSHELF': FurnitureType.bookshelf,
      'NIGHTSTAND': FurnitureType.nightstand,
      'DRESSER': FurnitureType.wardrobe,
    };
    return map[k];
  }

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static Map<String, dynamic> _jsonMap(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final d = jsonDecode(t);
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    throw Exception('JSON not object');
  }

  static Future<String?> _prepare(File image) async {
    try {
      final bytes = await image.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        final mime = lookupMimeType(image.path) ?? 'image/jpeg';
        return 'data:$mime;base64,${base64Encode(bytes)}';
      }
      var frame = decoded;
      const maxSide = 1280;
      if (frame.width > maxSide || frame.height > maxSide) {
        frame = frame.width >= frame.height
            ? img.copyResize(frame, width: maxSide)
            : img.copyResize(frame, height: maxSide);
      }
      final jpg = Uint8List.fromList(img.encodeJpg(frame, quality: 90));
      return 'data:image/jpeg;base64,${base64Encode(jpg)}';
    } catch (_) {
      return null;
    }
  }

  static String _short(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 120 ? t : '${t.substring(0, 120)}…';
  }
}
