import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/accurate_scan.dart';
import '../domain/auto_scale.dart';
import '../domain/furniture_vision_filter.dart';
import '../domain/scan_keyframes.dart';
import '../domain/scan_parser.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'secure_key_store.dart';

/// Free multimodal scan via Groq (Llama 4 Scout vision).
///
/// **Easy mode** ([autoScale]): no tape required — estimate room size from
/// photos/video + door/furniture priors, then place openings/furniture.
///
/// **Locked mode** (default when size given): multi-frame interior-designer
/// pass; user room size remains authoritative.
class FreeVisionScanner {
  static const double minConfidence = 0.72;

  static SecureKeyStore _store([SharedPreferences? prefs]) =>
      SecureKeyStore(prefs: prefs);

  static Future<String?> loadApiKey([SharedPreferences? prefsOverride]) async {
    return _store(prefsOverride).loadGroqKey();
  }

  static Future<void> saveApiKey(String key, [SharedPreferences? prefsOverride]) async {
    await _store(prefsOverride).saveGroqKey(key);
  }

  static Future<String?> resolveApiKey({
    String? apiKey,
    SharedPreferences? prefsOverride,
  }) async {
    final explicit = apiKey?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final user = await loadApiKey(prefsOverride);
    if (user != null && user.isNotEmpty) return user;
    final bundled = AppConfig.bundledGroqApiKey.trim();
    if (bundled.isNotEmpty) return bundled;
    return null;
  }

  static Future<bool> isAvailable({SharedPreferences? prefsOverride}) async {
    final key = await resolveApiKey(prefsOverride: prefsOverride);
    return key != null && key.isNotEmpty;
  }

  /// Full scan: architecture (openings) + furniture from many frames.
  ///
  /// When [autoScale] is true (or width/length are null), estimates size for
  /// everyday users who only upload photos/video.
  Future<ScanResult> scan({
    required List<File> images,
    double? roomWidthFt,
    double? roomLengthFt,
    String? apiKey,
    bool precisionMode = true,
    bool autoScale = false,
  }) async {
    final key = await resolveApiKey(apiKey: apiKey);
    if (key == null || key.isEmpty) {
      throw Exception('No free vision key available');
    }
    if (images.isEmpty) {
      throw Exception('Add at least one room photo or video frames.');
    }

    // Prefer sharpest diverse frames for the model (token/payload limits).
    final prepared = await ScanKeyframes.pickSharpest(images, maxKeep: 8);
    final frames = prepared.isEmpty ? images.take(8).toList() : prepared;

    final needAuto =
        autoScale || roomWidthFt == null || roomLengthFt == null ||
            roomWidthFt <= 0 ||
            roomLengthFt <= 0;

    if (needAuto) {
      return _consumerEasyScan(
        key: key,
        frames: frames,
        frameCount: images.length,
        userWidthFt: roomWidthFt,
        userLengthFt: roomLengthFt,
      );
    }

    // needAuto already returned — size is locked for precision path.
    final lockedW = roomWidthFt!;
    final lockedL = roomLengthFt!;
    if (precisionMode) {
      return _precisionScan(
        key: key,
        frames: frames,
        roomWidthFt: lockedW,
        roomLengthFt: lockedL,
        frameCount: images.length,
      );
    }

    return _singlePassScan(
      key: key,
      frames: frames,
      roomWidthFt: lockedW,
      roomLengthFt: lockedL,
    );
  }

  /// Consumer path: film/photos → estimated plan without tape knowledge.
  Future<ScanResult> _consumerEasyScan({
    required String key,
    required List<File> frames,
    required int frameCount,
    double? userWidthFt,
    double? userLengthFt,
  }) async {
    final warnings = <String>[
      'Easy scan: $frameCount frame(s) · no tape required',
      'Walk every wall in the video for best doors/windows/furniture.',
    ];

    Map<String, dynamic> layoutJson = {};
    try {
      layoutJson = await _callVision(
        key: key,
        frames: frames,
        prompt: _consumerLayoutPrompt(),
        system:
            'You map rooms for everyday people who do NOT know measurements. '
            'Estimate a realistic top-down floor plan in feet using multi-view '
            'cues and standard object sizes (doors ~2.5–3 ft, queen bed ~5×6.5 ft, '
            'sofa ~6–8 ft). Never invent furniture that is not visible. '
            'Prefer empty furniture [] over guesses. JSON only.',
      );
    } catch (e) {
      warnings.add('Layout pass failed: $e');
      final size = AutoScale.resolve(
        userWidthFt: userWidthFt,
        userLengthFt: userLengthFt,
      );
      return AccurateScan.enforce(
        widthFt: size.widthFt,
        lengthFt: size.lengthFt,
        openings: const [],
        furniture: const [],
        warnings: [...warnings, ...size.notes],
        sourceLabel: 'Easy scan fallback — empty plan',
        inventDefaultOpenings: false,
        accuracyScore: size.confidence * 0.5,
      );
    }

    final vW = _asDouble(layoutJson['roomWidth']) ??
        _asDouble(layoutJson['room_width']);
    final vL = _asDouble(layoutJson['roomLength']) ??
        _asDouble(layoutJson['room_length']);
    final vConf = _asDouble(layoutJson['sizeConfidence']) ??
        _asDouble(layoutJson['size_confidence']) ??
        0.5;

    // Parse with provisional size so relative positions exist
    final provisionalW = (vW != null && vW > 0) ? vW : AutoScale.fallbackWidthFt;
    final provisionalL = (vL != null && vL > 0) ? vL : AutoScale.fallbackLengthFt;
    layoutJson['roomWidth'] = provisionalW;
    layoutJson['roomLength'] = provisionalL;

    final filtered = _filterFurnitureMap(layoutJson);
    if (filtered.dropped > 0) {
      warnings.add(
        'Dropped ${filtered.dropped} low-confidence furniture guess(es)',
      );
    }
    final parsed = ScanParser.parse(filtered.map);

    final doorWidths = AutoScale.doorWidthsFromWalls(parsed.walls);
    // Also read explicit scale cues from model
    final cues = layoutJson['scaleCues'] ?? layoutJson['scale_cues'];
    if (cues is List) {
      for (final c in cues) {
        if (c is! Map) continue;
        final type = c['type']?.toString().toLowerCase() ?? '';
        final w = _asDouble(c['widthFt']) ?? _asDouble(c['width']);
        if (type.contains('door') && w != null && w > 0) {
          doorWidths.add(w);
        }
      }
    }

    final furnPriors = <({String type, double widthFt, double lengthFt})>[
      for (final f in parsed.furniture)
        (
          type: f.type.name.toUpperCase(),
          widthFt: f.widthFt,
          lengthFt: f.lengthFt,
        ),
    ];

    final size = AutoScale.resolve(
      userWidthFt: userWidthFt,
      userLengthFt: userLengthFt,
      visionWidthFt: provisionalW,
      visionLengthFt: provisionalL,
      visionSizeConfidence: vConf,
      doorWidthsFt: doorWidths,
      furniture: furnPriors,
    );
    warnings.addAll(size.notes);

    // Enforce final size (reprojects openings onto clean rectangle)
    var result = AccurateScan.enforce(
      widthFt: size.widthFt,
      lengthFt: size.lengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: warnings,
      sourceLabel:
          'Easy photo/video plan — size estimated for everyday use',
      inventDefaultOpenings: false,
      accuracyScore: null,
    );

    // If provisional size differed a lot, re-map furniture positions
    if ((provisionalW - size.widthFt).abs() > 0.4 ||
        (provisionalL - size.lengthFt).abs() > 0.4) {
      final scaled = AutoScale.rescaleResult(
        ScanResult(
          roomWidthFt: provisionalW,
          roomLengthFt: provisionalL,
          walls: parsed.walls,
          furniture: parsed.furniture,
          warnings: const [],
        ),
        newWidthFt: size.widthFt,
        newLengthFt: size.lengthFt,
      );
      result = AccurateScan.enforce(
        widthFt: size.widthFt,
        lengthFt: size.lengthFt,
        openings: scaled.walls,
        furniture: scaled.furniture,
        warnings: warnings,
        sourceLabel:
            'Easy photo/video plan — size estimated for everyday use',
        inventDefaultOpenings: false,
      );
    }

    final openingsCount = result.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .length;
    final accuracy = _estimateAccuracy(
      frames: frames.length,
      furnitureCount: result.furniture.length,
      openingsCount: openingsCount,
      dropped: filtered.dropped,
      autoScale: !size.usedUserSize,
      scaleConfidence: size.confidence,
    );
    warnings.add(
      'Layout confidence ~${(accuracy * 100).round()}% '
      '(more wall coverage + clear doors improve scale)',
    );

    return result.copyWith(
      warnings: warnings,
      accuracyScore: accuracy,
    );
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// Two-pass: (1) openings / wall features (2) furniture placement.
  Future<ScanResult> _precisionScan({
    required String key,
    required List<File> frames,
    required double roomWidthFt,
    required double roomLengthFt,
    required int frameCount,
  }) async {
    final warnings = <String>[
      'Precision scan: $frameCount frame(s) · multi-pass interior mapping',
      'Room size locked to your ${roomWidthFt.toStringAsFixed(1)} × '
          '${roomLengthFt.toStringAsFixed(1)} ft measurements',
    ];

    // Pass 1 — architecture (doors, windows, built-ins as openings)
    Map<String, dynamic> archJson = {};
    try {
      archJson = await _callVision(
        key: key,
        frames: frames,
        prompt: _architecturePrompt(roomWidthFt, roomLengthFt),
        system:
            'You are an interior architect surveying a room for a measured '
            'floor plan. Report ONLY openings and built-in wall features you '
            'clearly see (doors, windows, sliding doors, French doors, alcoves). '
            'Do NOT invent openings. Do NOT list freestanding furniture. '
            'JSON only. Room size is fixed by the user.',
      );
    } catch (e) {
      warnings.add('Architecture pass partial: $e');
    }

    // Pass 2 — furniture (strict, no invention)
    Map<String, dynamic> furnJson = {};
    try {
      furnJson = await _callVision(
        key: key,
        frames: frames,
        prompt: _furniturePrompt(roomWidthFt, roomLengthFt),
        system:
            'You are an interior designer documenting freestanding furniture '
            'exactly as placed in the photos/video frames. '
            'List ONLY items clearly visible across the frames. '
            'Never invent a bed, sofa, TV, or bookshelf that is not visible. '
            'Empty furniture is correct if the room is empty. JSON only.',
      );
    } catch (e) {
      warnings.add('Furniture pass partial: $e');
    }

    // Merge JSON
    final merged = <String, dynamic>{
      'roomWidth': roomWidthFt,
      'roomLength': roomLengthFt,
      'walls': archJson['walls'] ?? furnJson['walls'] ?? [],
      'furniture': furnJson['furniture'] ?? [],
      'openings': archJson['openings'] ?? archJson['walls'] ?? [],
    };

    // Prefer openings array if provided separately
    if (archJson['openings'] is List && (archJson['openings'] as List).isNotEmpty) {
      merged['walls'] = archJson['openings'];
    }

    final filtered = _filterFurnitureMap(merged);
    if (filtered.dropped > 0) {
      warnings.add(
        'Dropped ${filtered.dropped} low-confidence furniture guess(es)',
      );
    }

    final parsed = ScanParser.parse(filtered.map);
    final accuracy = _estimateAccuracy(
      frames: frames.length,
      furnitureCount: parsed.furniture.length,
      openingsCount: parsed.walls
          .where((w) =>
              w.type == StrokeType.door ||
              w.type == StrokeType.window ||
              w.type == StrokeType.balcony)
          .length,
      dropped: filtered.dropped,
    );

    warnings.add(
      'Scan accuracy estimate: ${(accuracy * 100).round()}% '
      '(more walkaround frames improve openings/furniture placement)',
    );

    return AccurateScan.enforce(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: warnings,
      sourceLabel:
          'Precision multi-frame scan (interior designer lens) — size locked',
      inventDefaultOpenings: false,
      accuracyScore: accuracy,
    );
  }

  Future<ScanResult> _singlePassScan({
    required String key,
    required List<File> frames,
    required double roomWidthFt,
    required double roomLengthFt,
  }) async {
    final jsonMap = await _callVision(
      key: key,
      frames: frames,
      prompt: _furniturePrompt(roomWidthFt, roomLengthFt),
      system:
          'Strict visual inspector. Only visible furniture. JSON only. '
          'Room size fixed by user.',
    );
    jsonMap['roomWidth'] = roomWidthFt;
    jsonMap['roomLength'] = roomLengthFt;
    final filtered = _filterFurnitureMap(jsonMap);
    final parsed = ScanParser.parse(filtered.map);
    return AccurateScan.enforce(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: parsed.warnings,
      sourceLabel: 'Free AI scan — size locked',
      inventDefaultOpenings: false,
    );
  }

  Future<Map<String, dynamic>> _callVision({
    required String key,
    required List<File> frames,
    required String prompt,
    required String system,
  }) async {
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
    ];

    for (final image in frames) {
      final prepared = await _prepareImageDataUrl(image);
      if (prepared == null) continue;
      content.add({
        'type': 'image_url',
        'image_url': {'url': prepared},
      });
    }
    if (content.length < 2) {
      throw Exception('Could not read any frames');
    }

    final body = {
      'model': AppConfig.groqVisionModel,
      'temperature': 0.0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': content},
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
        .timeout(const Duration(seconds: 90));

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Free vision key rejected');
    }
    if (response.statusCode == 429) {
      throw Exception('Free vision rate limit — try again shortly');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Free vision error ${response.statusCode}: ${_short(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('Free vision returned no choices');
    }
    final message = (choices.first as Map)['message'];
    final text = message is Map ? message['content']?.toString() : null;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Free vision returned empty content');
    }
    return _extractJsonMap(text);
  }

  static ({Map<String, dynamic> map, int dropped}) _filterFurnitureMap(
    Map<String, dynamic> jsonMap,
  ) {
    final raw = jsonMap['furniture'];
    final result = FurnitureVisionFilter.filter(
      raw is List ? raw : null,
      minConfidence: minConfidence,
    );
    final out = Map<String, dynamic>.from(jsonMap);
    out['furniture'] = result.kept;
    return (map: out, dropped: result.dropped);
  }

  static double _estimateAccuracy({
    required int frames,
    required int furnitureCount,
    required int openingsCount,
    required int dropped,
    bool autoScale = false,
    double scaleConfidence = 0.5,
  }) {
    // Heuristic score for UI — not CAD / LiDAR precision.
    var score = autoScale ? 0.38 : 0.45;
    score += (frames.clamp(1, 8) / 8) * 0.25;
    if (openingsCount > 0) score += 0.12;
    if (furnitureCount > 0) score += 0.12;
    if (dropped == 0 && furnitureCount > 0) score += 0.06;
    if (frames >= 4) score += 0.05;
    if (autoScale) {
      score += (scaleConfidence - 0.4).clamp(0.0, 0.2);
      // Cap: photo-only auto-scale never claims "survey grade"
      return score.clamp(0.30, 0.82);
    }
    return score.clamp(0.35, 0.92);
  }

  /// Consumer prompt: estimate size + openings + furniture in one multi-view pass.
  static String _consumerLayoutPrompt() => '''
You help regular people map a room from phone photos/video. They do NOT know
the room measurements. Estimate a realistic top-down plan in FEET.

Cross-check the SAME room across all frames (walkaround). Prefer multi-view
agreement. Use standard object sizes as your ruler:
- Interior door clear width ≈ 2.5–3.0 ft (use this as primary scale)
- Queen bed ≈ 5.0 × 6.5–7.0 ft, twin ≈ 3.2 × 6.5 ft
- 3-seat sofa ≈ 6.5–8.0 ft long
- Ceiling in most homes 8–9 ft (depth cue only)

Return ONLY JSON:
{
  "roomWidth": 12.0,
  "roomLength": 14.0,
  "sizeConfidence": 0.6,
  "scaleCues": [
    {"type": "door", "widthFt": 2.8, "note": "main door visible"}
  ],
  "openings": [
    {
      "type": "door",
      "start": {"x": 1.0, "y": 0},
      "end": {"x": 3.8, "y": 0},
      "confidence": 0.85,
      "evidence": "door on near wall"
    }
  ],
  "furniture": []
}

Coordinate system:
- roomWidth = X (left–right), roomLength = Y (near–far)
- Origin (0,0) = one corner of the rectangle
- Place openings ON outer walls (y=0, y=roomLength, x=0, or x=roomWidth)
- furniture pos = CENTER of piece in feet; dim = footprint feet; rot degrees

STRICT rules:
1. furniture default []. Never invent bed/sofa/TV/bookshelf not clearly visible.
2. openings: door | window | balcony only. Empty [] if unsure.
3. confidence >= 0.75 required or omit item.
4. sizeConfidence 0–1 honesty about room size estimate.
5. Prefer a clean rectangular room unless photos clearly show L-shape (still use outer bounds).
6. If only one wall is visible, still estimate full room but lower sizeConfidence.
7. Types for furniture: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND
''';

  static Future<String?> _prepareImageDataUrl(File image) async {
    try {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return null;
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
      final jpg = Uint8List.fromList(img.encodeJpg(frame, quality: 88));
      return 'data:image/jpeg;base64,${base64Encode(jpg)}';
    } catch (_) {
      return null;
    }
  }

  static String _architecturePrompt(double w, double l) => '''
You are surveying this room like an interior architect preparing a floor plan.

ROOM SIZE IS FIXED (never change):
- roomWidth = $w feet (X axis)
- roomLength = $l feet (Y axis)
Origin (0,0) = one corner; +x = width; +y = length.

These images/video frames show the SAME room from multiple angles.
Cross-check corners, doors, and windows across frames.

Return ONLY JSON:
{
  "roomWidth": $w,
  "roomLength": $l,
  "openings": [
    {
      "type": "door",
      "start": {"x": 1.0, "y": 0},
      "end": {"x": 3.5, "y": 0},
      "confidence": 0.9,
      "evidence": "door on near wall in frame"
    }
  ]
}

Rules:
1. openings types: door | window | balcony only.
2. Place each opening ON the perimeter walls (y=0, y=$l, x=0, or x=$w).
3. Estimate position along the wall from what you see (left/right of frame).
4. Only report openings you can see. Empty openings: [] is valid.
5. Do NOT invent a front door if none is visible.
6. Note sliding doors, French doors as type "door".
7. confidence 0–1; omit under 0.75.
8. No freestanding furniture in this pass.
''';

  static String _furniturePrompt(double w, double l) => '''
Document freestanding furniture as an interior designer would for a layout plan.

ROOM SIZE FIXED:
- roomWidth = $w ft, roomLength = $l ft
- Origin corner (0,0); pos is CENTER of each piece in feet.

Use ALL frames: same object seen from two angles = one entry (best position).

Return ONLY JSON:
{
  "roomWidth": $w,
  "roomLength": $l,
  "furniture": []
}

When an item is CLEARLY visible:
{
  "type": "TABLE",
  "pos": {"x": 4.0, "y": 5.0},
  "dim": {"w": 3.0, "l": 2.0},
  "rot": 0,
  "confidence": 0.9,
  "evidence": "wooden table center of room, visible in multiple frames"
}

STRICT:
1. Default furniture: [].
2. Never invent BED/SOFA/TV_UNIT/BOOKSHELF not in the frames.
3. Types: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND
   (desk→TABLE, couch→SOFA, dresser→WARDROBE, tv stand→TV_UNIT).
4. Place relative to walls using multi-view cues (against which wall).
5. confidence >= 0.75 required; else omit.
6. dim = realistic footprint in feet.
7. rot degrees (0/90/180/270 preferred).
8. Blurry / partial view → omit item.
''';

  static Map<String, dynamic> _extractJsonMap(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final decoded = jsonDecode(t);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('Free vision JSON was not an object');
  }

  static String _short(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 160) return t;
    return '${t.substring(0, 160)}…';
  }
}
