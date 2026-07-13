import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/accurate_scan.dart';
import '../domain/scan_parser.dart';
import '../domain/furniture_vision_filter.dart';
import '../models/scan_result.dart';
import 'secure_key_store.dart';

/// Free multimodal scan via Groq (Llama 4 Scout vision).
///
/// Strict policy: **only** furniture clearly visible in photos.
/// Prefer empty `furniture: []` over guessing a typical bedroom/living set.
///
/// Key resolution (first non-empty wins):
/// 1. Explicit [apiKey] argument
/// 2. User key in secure storage (optional Settings)
/// 3. App-bundled [AppConfig.bundledGroqApiKey] from `--dart-define`
class FreeVisionScanner {
  /// Drop model guesses below this confidence (0–1).
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

  /// Detect furniture / openings from photos. [roomWidthFt]×[roomLengthFt] win.
  Future<ScanResult> scan({
    required List<File> images,
    required double roomWidthFt,
    required double roomLengthFt,
    String? apiKey,
  }) async {
    final key = await resolveApiKey(apiKey: apiKey);
    if (key == null || key.isEmpty) {
      throw Exception('No free vision key available');
    }
    if (images.isEmpty) {
      throw Exception('Add at least one room photo.');
    }

    final content = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': _prompt(roomWidthFt, roomLengthFt),
      },
    ];

    final limited = images.take(3).toList();
    for (final image in limited) {
      final prepared = await _prepareImageDataUrl(image);
      if (prepared == null) continue;
      content.add({
        'type': 'image_url',
        'image_url': {'url': prepared},
      });
    }

    if (content.length < 2) {
      throw Exception('Could not read any room photos');
    }

    final body = {
      'model': AppConfig.groqVisionModel,
      'temperature': 0.0,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a strict visual inspector for floor plans. '
              'Your job is to report ONLY furniture that is clearly visible '
              'in the provided photos. '
              'If a bed, sofa, TV, bookshelf, or other piece is NOT clearly '
              'in the images, you MUST NOT list it. '
              'Empty rooms and sparse rooms are normal — return '
              '"furniture": [] when unsure. '
              'Never invent a typical bedroom or living-room set. '
              'Never copy example JSON furniture. '
              'Return JSON only. Room size is fixed by the user.',
        },
        {
          'role': 'user',
          'content': content,
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

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Free vision key rejected');
    }
    if (response.statusCode == 429) {
      throw Exception('Free vision rate limit — try again in a minute');
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

    final jsonMap = _extractJsonMap(text);
    jsonMap['roomWidth'] = roomWidthFt;
    jsonMap['roomLength'] = roomLengthFt;

    // Confidence filter before parse (raw list)
    final filtered = _filterByConfidence(jsonMap);
    final dropped = filtered.dropped;
    final parsed = ScanParser.parse(filtered.map);

    final extraWarnings = <String>[
      if (dropped > 0)
        'Dropped $dropped low-confidence guess(es) — only clear items kept',
      if (parsed.furniture.isEmpty)
        'No furniture clearly visible in photos — empty plan (add from catalog if needed)',
    ];

    return AccurateScan.enforce(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: [...parsed.warnings, ...extraWarnings],
      sourceLabel:
          'Free AI furniture (strict — only clearly visible items)',
    );
  }

  /// Keep only high-confidence items; strip example/hallucination-prone junk.
  static ({Map<String, dynamic> map, int dropped}) _filterByConfidence(
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
      // Slightly higher res for better object recognition
      const maxSide = 1024;
      if (frame.width > maxSide || frame.height > maxSide) {
        frame = frame.width >= frame.height
            ? img.copyResize(frame, width: maxSide)
            : img.copyResize(frame, height: maxSide);
      }
      final jpg = Uint8List.fromList(img.encodeJpg(frame, quality: 82));
      return 'data:image/jpeg;base64,${base64Encode(jpg)}';
    } catch (_) {
      return null;
    }
  }

  static String _prompt(double w, double l) => '''
Look at the attached room photo(s). Build a top-down plan with ONLY what you
can actually see.

ROOM SIZE IS FIXED (never change):
- roomWidth = $w feet
- roomLength = $l feet
Origin (0,0) = one corner; +x along width; +y along length.

Return ONLY this JSON shape (use empty furniture if nothing is clear):
{
  "roomWidth": $w,
  "roomLength": $l,
  "walls": [
    {"type": "wall", "start": {"x": 0, "y": 0}, "end": {"x": $w, "y": 0}},
    {"type": "wall", "start": {"x": $w, "y": 0}, "end": {"x": $w, "y": $l}},
    {"type": "wall", "start": {"x": $w, "y": $l}, "end": {"x": 0, "y": $l}},
    {"type": "wall", "start": {"x": 0, "y": $l}, "end": {"x": 0, "y": 0}}
  ],
  "furniture": []
}

Furniture object fields when an item IS clearly visible:
{
  "type": "TABLE",
  "pos": {"x": 4.0, "y": 5.0},
  "dim": {"w": 3.0, "l": 2.0},
  "rot": 0,
  "confidence": 0.9,
  "evidence": "brown wooden table in center of photo"
}

STRICT RULES:
1. Default to "furniture": []. Empty is correct when the room has no clear furniture.
2. Do NOT invent BED, SOFA, TV_UNIT, BOOKSHELF, WARDROBE, CHAIR, or NIGHTSTAND
   just because rooms often have them.
3. Include an item ONLY if you can point to it in the photo (describe in "evidence").
4. confidence is 0.0–1.0. Use >= 0.85 only when the object is obvious.
   If confidence would be under 0.75, OMIT the item entirely.
5. Allowed types only: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND.
   (desk→TABLE, couch→SOFA, dresser→WARDROBE, tv stand→TV_UNIT, shelf→BOOKSHELF)
6. "pos" = CENTER of the piece in feet. "rot" = degrees (prefer 0/90/180/270).
7. Doors/windows on walls only if you see them; optional.
8. NEVER copy sample furniture from prompts or training data.
9. If photos are blurry, dark, or partial — return empty furniture.
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
