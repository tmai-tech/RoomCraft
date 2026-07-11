import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/scan_parser.dart';
import '../models/scan_result.dart';

class AIScannerService {
  static Future<String?> loadApiKey([SharedPreferences? prefsOverride]) async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    final modern = prefs.getString(AppConfig.apiKeyPrefKey)?.trim();
    if (modern != null && modern.isNotEmpty) return modern;
    final legacy = prefs.getString(AppConfig.apiKeyLegacyPrefKey)?.trim();
    if (legacy != null && legacy.isNotEmpty) {
      await prefs.setString(AppConfig.apiKeyPrefKey, legacy);
      return legacy;
    }
    return null;
  }

  static Future<void> saveApiKey(String key, [SharedPreferences? prefsOverride]) async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.apiKeyPrefKey, key.trim());
  }

  Future<String?> validateImage(File image) async {
    final apiKey = await loadApiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    final bytes = await image.readAsBytes();
    final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';

    const prompt =
        'Analyze this room photo. Is it clear enough for architectural blueprinting? '
        'Can you see the floor-to-wall junction? Return strictly JSON: '
        '{"valid": bool, "reason": "Short explanation"}';

    for (final modelName in AppConfig.geminiModelCandidates) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(responseMimeType: 'application/json'),
        );
        final response = await model.generateContent([
          Content.multi([TextPart(prompt), DataPart(mimeType, bytes)]),
        ]);
        final text = response.text;
        if (text == null || text.isEmpty) continue;
        final result = jsonDecode(text) as Map<String, dynamic>;
        return result['valid'] == true ? null : result['reason'] as String?;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Scan photos and return a validated [ScanResult].
  Future<ScanResult> scanRoom(
    List<File> images, {
    Map<File, double>? wallMeasurements,
  }) async {
    final apiKey = await loadApiKey();

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not found. Please set it in Settings.');
    }
    if (images.isEmpty) {
      throw Exception('Add at least one room photo.');
    }

    final imageParts = <DataPart>[];
    for (final image in images) {
      final bytes = await image.readAsBytes();
      final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
      imageParts.add(DataPart(mimeType, bytes));
    }

    var contextInfo = '';
    if (wallMeasurements != null && wallMeasurements.isNotEmpty) {
      final measurements = wallMeasurements.entries
          .map((e) =>
              'Photo ${e.key.path.split(Platform.pathSeparator).last}: ${e.value}ft')
          .join(', ');
      contextInfo =
          'The user provided wall measurements for scale: $measurements. Use them.';
    }

    final prompt = '''You are an expert architectural assistant. $contextInfo
Analyze these room photos and estimate a TOP-DOWN floor plan layout.
Include walls, doors, windows, balconies AND furniture.

Return ONLY JSON (no markdown):
{
  "roomWidth": 15.0,
  "roomLength": 12.0,
  "walls": [
    {"type": "wall", "start": {"x": 0, "y": 0}, "end": {"x": 15, "y": 0}},
    {"type": "door", "start": {"x": 5, "y": 0}, "end": {"x": 8, "y": 0}}
  ],
  "furniture": [
    {"type": "BED", "pos": {"x": 2, "y": 2}, "dim": {"w": 5, "l": 6.5}, "rot": 0}
  ]
}
Rules:
- Coordinates in feet, origin at a corner of the room.
- Walls should form a reasonable closed outline when possible.
- Furniture type MUST be one of: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND.
- rot is rotation in degrees.
''';

    String? lastError;
    for (final modelName in AppConfig.geminiModelCandidates) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(responseMimeType: 'application/json'),
        );
        final response = await model.generateContent([
          Content.multi([TextPart(prompt), ...imageParts]),
        ]);

        if (response.text == null || response.text!.isEmpty) {
          throw Exception('AI returned empty response');
        }

        final decoded = jsonDecode(response.text!);
        Map<String, dynamic> map;
        if (decoded is Map<String, dynamic>) {
          map = decoded;
        } else if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        } else {
          throw Exception('AI returned unexpected JSON type');
        }

        return ScanParser.parse(map);
      } catch (e) {
        lastError = e.toString();

        if (lastError.contains('429') ||
            lastError.contains('quota') ||
            lastError.contains('safety')) {
          throw Exception(
              'Gemini Limit Reached: Please wait a minute and try again.');
        }

        if (e is FormatException) {
          throw Exception('Could not understand AI layout: ${e.message}');
        }

        if (!lastError.contains('not found') && !lastError.contains('404')) {
          // Non-model-not-found: still try next model for empty/parse issues
          if (lastError.contains('empty') || lastError.contains('JSON')) {
            continue;
          }
          throw Exception('Gemini Error: $lastError');
        }
      }
    }
    throw Exception(
        'All Gemini models unavailable. Check API key/region. Last: $lastError');
  }
}
