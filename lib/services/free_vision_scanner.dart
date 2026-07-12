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
import '../models/scan_result.dart';

/// Free multimodal scan via Groq (Llama 4 Scout vision).
///
/// Key resolution (first non-empty wins):
/// 1. Explicit [apiKey] argument
/// 2. User key in SharedPreferences (optional Settings)
/// 3. App-bundled [AppConfig.bundledGroqApiKey] from `--dart-define`
///
/// Room size always comes from user dimensions; AI may only propose furniture
/// and openings. Output is always run through [AccurateScan.enforce].
class FreeVisionScanner {
  static Future<String?> loadApiKey([SharedPreferences? prefsOverride]) async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    final key = prefs.getString(AppConfig.groqApiKeyPrefKey)?.trim();
    if (key != null && key.isNotEmpty) return key;
    return null;
  }

  static Future<void> saveApiKey(String key, [SharedPreferences? prefsOverride]) async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.groqApiKeyPrefKey, key.trim());
  }

  /// Resolve key without requiring the user to open Settings.
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

    // Cap images for free-tier latency / payload size.
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
              'You are a careful floor-plan assistant. Only report furniture '
              'you can see in the photos. Never invent a bed, sofa, or other '
              'item that is not visible. Return JSON only. '
              'Room size is fixed by the user and must not change.',
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

    final parsed = ScanParser.parse(jsonMap);

    // Dimensionally correct plan — never trust AI for room size.
    return AccurateScan.enforce(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: parsed.warnings,
      sourceLabel:
          'Free AI furniture (Groq Llama 4 Scout) — no user key required when app key is set',
    );
  }

  /// Resize / re-encode for smaller free-tier payloads.
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
      const maxSide = 768;
      if (frame.width > maxSide || frame.height > maxSide) {
        frame = frame.width >= frame.height
            ? img.copyResize(frame, width: maxSide)
            : img.copyResize(frame, height: maxSide);
      }
      final jpg = Uint8List.fromList(img.encodeJpg(frame, quality: 75));
      return 'data:image/jpeg;base64,${base64Encode(jpg)}';
    } catch (_) {
      return null;
    }
  }

  static String _prompt(double w, double l) => '''
Analyze these room photos for a TOP-DOWN floor plan.

ROOM SIZE IS FIXED (do not change):
- roomWidth = $w feet
- roomLength = $l feet
Origin is the near-left corner of the floor rectangle.

Return ONLY JSON:
{
  "roomWidth": $w,
  "roomLength": $l,
  "walls": [
    {"type": "wall", "start": {"x": 0, "y": 0}, "end": {"x": $w, "y": 0}},
    {"type": "wall", "start": {"x": $w, "y": 0}, "end": {"x": $w, "y": $l}},
    {"type": "wall", "start": {"x": $w, "y": $l}, "end": {"x": 0, "y": $l}},
    {"type": "wall", "start": {"x": 0, "y": $l}, "end": {"x": 0, "y": 0}}
  ],
  "furniture": [
    {"type": "SOFA", "pos": {"x": 2, "y": 3}, "dim": {"w": 7, "l": 3}, "rot": 0}
  ]
}

Rules:
- Coordinates in feet, origin at a room corner.
- ALWAYS keep roomWidth=$w and roomLength=$l.
- Include door/window segments on the walls only if you see them.
- furniture[]: ONLY items clearly visible in the photos.
- If the room looks empty or you are unsure, return "furniture": [].
- NEVER invent a BED, SOFA, or other piece that is not visible.
- Furniture type MUST be one of: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND.
- dim.w and dim.l are footprint width/length in feet; rot is degrees.
- Place furniture inside the $w × $l rectangle with realistic sizes.
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
