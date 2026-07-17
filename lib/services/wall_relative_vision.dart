import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
    /// Shared multi-view inventory constraint (MUST / NO types).
    String inventoryHint = '',
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
              'Mirror is NOT a wardrobe. Desk monitors are NOT a TV unit. '
              'Never invent bed/sofa/TV if not clearly on this wall. JSON only.',
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': _wallPrompt(
                wall,
                wallLen,
                roomWidthFt,
                roomLengthFt,
                inventoryHint: inventoryHint,
              ),
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
    final parsed = _parseWallJson(json, wall, wallLen);
    // Apply inventory forbid list at wall level (+32)
    final furn = _filterFurnitureByInventory(parsed.furniture, inventoryHint);
    return (
      openings: parsed.openings,
      furniture: furn,
      notes: parsed.notes,
    );
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
    String inventoryHint = '',
  }) async {
    final openings = <WallOpeningHint>[];
    final furniture = <WallFurnitureHint>[];
    final notes = <String>[];
    if (inventoryHint.isNotEmpty) {
      notes.add('Wall inventory constraint: $inventoryHint');
    }

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
          inventoryHint: inventoryHint,
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

    // +37: wall-anchored photo-true fill for inventory MUST pieces / openings
    final filled = _photoTrueFill(
      openings: openings,
      furniture: merged,
      wallPhotos: wallPhotos,
      roomWidthFt: roomWidthFt,
      roomLengthFt: roomLengthFt,
      inventoryHint: inventoryHint,
      notes: notes,
    );

    return ScanRefine.refine(WallRelativeComposer.compose(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: filled.openings,
      furniture: filled.furniture,
      warnings: notes,
      wallPhotos: wallPhotos.length,
      overviewPhotos: overviewPhotos.length,
    ));
  }

  /// Ensure MUST wardrobe/TABLE and door/mesh openings as high-confidence wall anchors.
  static ({List<WallOpeningHint> openings, List<WallFurnitureHint> furniture})
      _photoTrueFill({
    required List<WallOpeningHint> openings,
    required List<WallFurnitureHint> furniture,
    required Map<WallSide, File> wallPhotos,
    required double roomWidthFt,
    required double roomLengthFt,
    required String inventoryHint,
    required List<String> notes,
  }) {
    if (inventoryHint.isEmpty) {
      return (openings: openings, furniture: furniture);
    }
    final furn = List<WallFurnitureHint>.from(furniture);
    final opens = List<WallOpeningHint>.from(openings);
    final types = furn.map((f) => f.type).toSet();
    final sidesWithPhoto = wallPhotos.keys.toList();
    if (sidesWithPhoto.isEmpty) {
      return (openings: opens, furniture: furn);
    }

    WallSide pickSide(List<WallSide> prefer) {
      for (final s in prefer) {
        if (sidesWithPhoto.contains(s)) return s;
      }
      return sidesWithPhoto.first;
    }

    if (inventoryHint.contains('MUST include WARDROBE') &&
        !types.contains(FurnitureType.wardrobe)) {
      // Prefer west/north (long storage walls in study-room feedback)
      final side = pickSide([
        WallSide.west,
        WallSide.north,
        WallSide.east,
        WallSide.south,
      ]);
      final wl = side.lengthFt(roomWidthFt, roomLengthFt);
      final along = math.min(6.7, wl * 0.75);
      furn.add(WallFurnitureHint.fromLeft(
        type: FurnitureType.wardrobe,
        wall: side,
        fromLeftFt: math.max(0.3, (wl - along) / 2),
        depthFt: 1.3,
        widthFt: along,
        lengthFt: 1.5,
        wallLengthFt: wl,
        confidence: 0.88,
        evidence: 'photo-true inventory seed WARDROBE (+37)',
      ));
      types.add(FurnitureType.wardrobe);
      notes.add('Photo-true: seeded WARDROBE on ${side.shortLabel} (+37)');
    }

    if (inventoryHint.contains('MUST include TABLE') &&
        !types.contains(FurnitureType.table)) {
      final side = pickSide([
        WallSide.south,
        WallSide.east,
        WallSide.north,
        WallSide.west,
      ]);
      final wl = side.lengthFt(roomWidthFt, roomLengthFt);
      furn.add(WallFurnitureHint.fromLeft(
        type: FurnitureType.table,
        wall: side,
        fromLeftFt: math.min(wl * 0.35, wl - 1),
        depthFt: 1.5,
        widthFt: 4.0,
        lengthFt: 2.0,
        wallLengthFt: wl,
        confidence: 0.88,
        evidence: 'photo-true inventory seed TABLE (+37)',
      ));
      types.add(FurnitureType.table);
      notes.add('Photo-true: seeded TABLE on ${side.shortLabel} (+37)');
    }

    final doorMatch = RegExp(r'about\s+(\d+)\s+door').firstMatch(inventoryHint);
    final wantDoors = doorMatch != null
        ? int.tryParse(doorMatch.group(1)!) ?? 0
        : (inventoryHint.contains('door opening') ? 1 : 0);
    final haveDoors = opens.where((o) => o.type == StrokeType.door).length;
    if (wantDoors > 0 && haveDoors < wantDoors) {
      final order = <WallSide>[
        ...sidesWithPhoto.where((s) =>
            s == WallSide.south ||
            s == WallSide.west ||
            s == WallSide.east ||
            s == WallSide.north),
        ...sidesWithPhoto,
      ];
      // Unique preserve order
      final seen = <WallSide>{};
      final unique = <WallSide>[];
      for (final s in order) {
        if (seen.add(s)) unique.add(s);
      }
      var added = 0;
      for (final use in unique) {
        if (haveDoors + added >= wantDoors) break;
        final wl = use.lengthFt(roomWidthFt, roomLengthFt);
        opens.add(WallOpeningHint.fromLeft(
          wall: use,
          type: StrokeType.door,
          fromLeftFt: 1.0 + added * 0.4,
          widthFt: 2.8,
          wallLengthFt: wl,
          confidence: 0.8,
          evidence: 'photo-true inventory door seed (+37)',
        ));
        added++;
      }
      if (added > 0) {
        notes.add('Photo-true: seeded $added door opening(s) (+37)');
      }
    }

    final wantMesh = inventoryHint.toLowerCase().contains('mesh') ||
        inventoryHint.toLowerCase().contains('glass') ||
        inventoryHint.contains('balcony');
    final hasWide = opens.any((o) =>
        o.type == StrokeType.balcony ||
        o.type == StrokeType.window ||
        (o.type == StrokeType.door &&
            o.widthAlongWallFt(o.wall.lengthFt(roomWidthFt, roomLengthFt)) >=
                4.5));
    if (wantMesh && !hasWide) {
      final side = pickSide([
        WallSide.east,
        WallSide.north,
        WallSide.south,
        WallSide.west,
      ]);
      final wl = side.lengthFt(roomWidthFt, roomLengthFt);
      final span = math.min(6.0, wl * 0.7);
      opens.add(WallOpeningHint.fromLeft(
        wall: side,
        type: StrokeType.balcony,
        fromLeftFt: math.max(0.5, (wl - span) / 2),
        widthFt: span,
        wallLengthFt: wl,
        confidence: 0.8,
        evidence: 'photo-true inventory mesh/glass seed (+37)',
      ));
      notes.add('Photo-true: seeded mesh/glass balcony on ${side.shortLabel} (+37)');
    }

    return (openings: opens, furniture: furn);
  }

  static String _wallPrompt(
    WallSide wall,
    double wallLenFt,
    double roomW,
    double roomL, {
    String inventoryHint = '',
  }) {
    final invBlock = inventoryHint.isEmpty
        ? ''
        : '\nROOM INVENTORY (whole room — respect when placing on THIS wall):\n$inventoryHint\n'
            '- Only place types that appear on THIS wall in the photo.\n'
            '- If inventory says NO BED/SOFA/TV_UNIT, never list those types.\n'
            '- Mirror alone ≠ WARDROBE. Monitors on a desk ≠ TV_UNIT.\n';

    return '''
This photo is ${wall.shortLabel} of a rectangular room (interior designer field survey).
Room size: ${roomW.toStringAsFixed(1)} ft (width) × ${roomL.toStringAsFixed(1)} ft (length).
THIS wall is EXACTLY ${wallLenFt.toStringAsFixed(1)} ft long (authoritative).
$invBlock
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
    {"type":"WARDROBE","from_left_ft":4.0,"depth_ft":1.5,"w_ft":6,"l_ft":2,"confidence":0.9,"evidence":"sliding wardrobe on this wall"},
    {"type":"TABLE","from_left_ft":2.0,"depth_ft":1.5,"w_ft":4,"l_ft":2,"confidence":0.85,"evidence":"desk against wall"}
  ]
}

Rules (critical for plan accuracy):
1. openings type: door | window | balcony only. from_left_ft = left edge of opening from LEFT corner while facing wall.
2. width_ft must be realistic: door 2.5–3.5 ft typical, window 2–6 ft, balcony/sliding 4–10 ft. Never a whole-wall door.
3. Only openings ON this wall (door frame / glass / sliding track clearly on THIS wall). Empty [] if none visible.
4. furniture only against THIS wall. from_left_ft = center of piece from left corner. depth_ft = how far it sticks into room (wardrobe ~1.5–2.5, desk ~1.5–2.5).
5. Types: BED,WARDROBE,SOFA,TABLE,CHAIR,TV_UNIT,BOOKSHELF,NIGHTSTAND
6. Never invent. If unsure about position, omit rather than guess. confidence ≥ 0.55 to include.
7. Balcony = large glazed door / outdoor opening (not a normal window).
8. If photo is not clearly this wall, return empty arrays.
9. Sliding cupboard/wardrobe with doors = WARDROBE. Computer desk = TABLE.
''';
  }

  static List<WallFurnitureHint> _filterFurnitureByInventory(
    List<WallFurnitureHint> items,
    String inventoryHint,
  ) {
    if (inventoryHint.isEmpty) return items;
    final forbid = <FurnitureType>{};
    if (inventoryHint.contains('NO BED')) forbid.add(FurnitureType.bed);
    if (inventoryHint.contains('NO SOFA')) forbid.add(FurnitureType.sofa);
    if (inventoryHint.contains('NO TV_UNIT')) forbid.add(FurnitureType.tvUnit);
    if (forbid.isEmpty) return items;
    return items.where((f) => !forbid.contains(f.type)).toList();
  }

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
        // +29: align with multi-view 0.55 floor for recall on 4-wall photos
        if (conf < 0.55) continue;
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
        // +29: lower floor so wardrobe/desk on wall photos are not dropped
        if (conf < 0.55) continue;
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
