import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/local_room_scanner.dart';
import '../domain/scan_parser.dart';
import '../models/scan_result.dart';

/// Free multimodal scan via Groq (Llama 4 Scout vision).
///
/// Requires a free key from https://console.groq.com — stored on device only.
/// Room size always comes from user dimensions; AI may only propose furniture
/// and openings that appear in the photo.
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

  /// Detect furniture / openings from photos. [roomWidthFt]×[roomLengthFt] win.
  Future<ScanResult> scan({
    required List<File> images,
    required double roomWidthFt,
    required double roomLengthFt,
    String? apiKey,
  }) async {
    final key = apiKey ?? await loadApiKey();
    if (key == null || key.isEmpty) {
      throw Exception('No Groq API key — add a free key in Settings');
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
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) continue;
      // Downsize large photos to keep request small.
      final mime = lookupMimeType(image.path) ?? 'image/jpeg';
      final b64 = base64Encode(bytes);
      content.add({
        'type': 'image_url',
        'image_url': {
          'url': 'data:$mime;base64,$b64',
        },
      });
    }

    final body = {
      'model': AppConfig.groqVisionModel,
      'temperature': 0.1,
      'response_format': {'type': 'json_object'},
      'messages': [
        {
          'role': 'system',
          'content':
              'You are a careful floor-plan assistant. Only report furniture '
              'you can see in the photos. Never invent a bed, sofa, or other '
              'item that is not visible. Return JSON only.',
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
      throw Exception('Groq API key rejected — check Settings');
    }
    if (response.statusCode == 429) {
      throw Exception('Groq rate limit — try again in a minute');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Groq error ${response.statusCode}: ${_short(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('Groq returned no choices');
    }
    final message = (choices.first as Map)['message'];
    final text = message is Map ? message['content']?.toString() : null;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Groq returned empty content');
    }

    final jsonMap = _extractJsonMap(text);
    // Force user dimensions so AI cannot reshape the room.
    jsonMap['roomWidth'] = roomWidthFt;
    jsonMap['roomLength'] = roomLengthFt;

    final parsed = ScanParser.parse(jsonMap);
    return parsed.copyWith(
      roomWidthFt: roomWidthFt,
      roomLengthFt: roomLengthFt,
      warnings: [
        'Free AI (Groq Llama 4 Scout) — furniture only if visible in photos',
        'Room locked to ${roomWidthFt.toStringAsFixed(1)} × '
            '${roomLengthFt.toStringAsFixed(1)} ft (your size)',
        ...parsed.warnings,
      ],
    );
  }

  /// Offline rectangle with exact size + optional free-vision furniture.
  static Future<ScanResult> offlineShell({
    required List<File> images,
    required double roomWidthFt,
    required double roomLengthFt,
  }) {
    return LocalRoomScanner.scan(
      images: images,
      roomWidthFt: roomWidthFt,
      roomLengthFt: roomLengthFt,
      preferredLayout: null, // empty
    );
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
    throw Exception('Groq JSON was not an object');
  }

  static String _short(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 160) return t;
    return '${t.substring(0, 160)}…';
  }
}
