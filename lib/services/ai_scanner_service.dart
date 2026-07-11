import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/stroke_model.dart';

class AIScannerService {
  /// Resolve Gemini API key (new key, then legacy key).
  static Future<String?> loadApiKey([SharedPreferences? prefsOverride]) async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    final modern = prefs.getString(AppConfig.apiKeyPrefKey)?.trim();
    if (modern != null && modern.isNotEmpty) return modern;
    final legacy = prefs.getString(AppConfig.apiKeyLegacyPrefKey)?.trim();
    if (legacy != null && legacy.isNotEmpty) {
      // Migrate to modern key
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
    return null; // Silent skip validation on error
  }

  Future<Map<String, dynamic>?> scanRoom(
    List<File> images, {
    Map<File, double>? wallMeasurements,
  }) async {
    final apiKey = await loadApiKey();

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not found. Please set it in Settings.');
    }

    final List<DataPart> imageParts = [];
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
          'The user has provided the following wall measurements for scale: $measurements.';
    }

    final prompt = '''You are an expert architectural assistant. $contextInfo
Analyze these room photos and estimate its layout.
Include walls, doors, windows, balconies AND furniture (bed, sofa, wardrobe, table, chair, etc.).

Return JSON:
{
  "roomWidth": 15.0,
  "roomLength": 12.0,
  "walls": [
    {"type": "wall", "start": {"x": 0, "y": 0}, "end": {"x": 15, "y": 0}},
    {"type": "door", "start": {"x": 5, "y": 0}, "end": {"x": 8, "y": 0}},
    {"type": "balcony", "start": {"x": 10, "y": 12}, "end": {"x": 15, "y": 12}}
  ],
  "furniture": [
    {"type": "BED", "pos": {"x": 2, "y": 2}, "dim": {"w": 5, "l": 6.5}, "rot": 0}
  ]
}
Coordinates are in feet. Furniture type MUST be exactly: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND.
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
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        throw Exception('AI returned unexpected JSON type');
      } catch (e) {
        lastError = e.toString();

        if (lastError.contains('429') ||
            lastError.contains('quota') ||
            lastError.contains('safety')) {
          throw Exception(
              'Gemini Limit Reached: Please wait a minute and try again. ($lastError)');
        }

        // Only continue to next model if it's a "Not Found" error
        if (!lastError.contains('not found') && !lastError.contains('404')) {
          throw Exception('Gemini Error: $lastError');
        }
      }
    }
    throw Exception(
        'All Gemini models are unavailable or not found. Please check your API key and region. Last error: $lastError');
  }

  List<StrokeModel> convertToStrokes(Map<String, dynamic> data, double pxf) {
    final List<StrokeModel> strokes = [];
    final walls = data['walls'] as List?;
    if (walls == null) return strokes;

    for (final w in walls) {
      if (w is! Map) continue;
      final map = Map<String, dynamic>.from(w);
      StrokeType type = StrokeType.wall;
      if (map['type'] == 'door') type = StrokeType.door;
      if (map['type'] == 'window') type = StrokeType.window;
      if (map['type'] == 'balcony') type = StrokeType.balcony;

      final start = map['start'];
      final end = map['end'];
      if (start is! Map || end is! Map) continue;

      strokes.add(StrokeModel(
        id: UniqueKey().toString(),
        type: type,
        points: [
          Offset(
            (start['x'] as num).toDouble() * pxf,
            (start['y'] as num).toDouble() * pxf,
          ),
          Offset(
            (end['x'] as num).toDouble() * pxf,
            (end['y'] as num).toDouble() * pxf,
          ),
        ],
      ));
    }
    return strokes;
  }

  List<dynamic> parseFurniture(Map<String, dynamic> data) {
    return data['furniture'] as List? ?? [];
  }
}
