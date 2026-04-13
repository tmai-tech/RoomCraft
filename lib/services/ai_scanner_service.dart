import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../models/stroke_model.dart';

class AIScannerService {
  static const String _apiKeyPrefKey = 'openai_api_key'; // Persistence key

  static const List<String> _modelCandidates = [
    'gemini-3.1-flash',
    'gemini-2.5-flash',
    'gemini-1.5-flash-latest',
  ];

  Future<String?> validateImage(File image) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_apiKeyPrefKey)?.trim();
    if (apiKey == null || apiKey.isEmpty) return null;

    final model = GenerativeModel(model: 'gemini-3.1-flash', apiKey: apiKey);
    final bytes = await image.readAsBytes();
    final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';

    final prompt = "Analyze this room photo. Is it clear enough for architectural blueprinting? "
        "Can you see the floor-to-wall junction? Return strictly JSON: "
        "{\"valid\": bool, \"reason\": \"Short explanation\"}";

    try {
      final response = await model.generateContent([
        Content.multi([TextPart(prompt), DataPart(mimeType, bytes)])
      ]);
      final result = jsonDecode(response.text!);
      return result['valid'] == true ? null : result['reason'] as String;
    } catch (_) {
      return null; // Silent skip validation on error
    }
  }

  Future<Map<String, dynamic>?> scanRoom(List<File> images, {Map<File, double>? wallMeasurements}) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_apiKeyPrefKey)?.trim();

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Gemini API Key not found. Please set it in Settings.');
    }

    final List<DataPart> imageParts = [];
    for (var image in images) {
      final bytes = await image.readAsBytes();
      final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
      imageParts.add(DataPart(mimeType, bytes));
    }

    String contextInfo = "";
    if (wallMeasurements != null && wallMeasurements.isNotEmpty) {
      final measurements = wallMeasurements.entries
          .map((e) => "Photo ${e.key.path.split(Platform.pathSeparator).last}: ${e.value}ft")
          .join(", ");
      contextInfo = "The user has provided the following wall measurements for scale: $measurements.";
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
    for (var modelName in _modelCandidates) {
      try {
        final model = GenerativeModel(
          model: modelName,
          apiKey: apiKey,
          generationConfig: GenerationConfig(responseMimeType: 'application/json'),
        );
        final response = await model.generateContent([
          Content.multi([TextPart(prompt), ...imageParts])
        ]);
        
        if (response.text == null || response.text!.isEmpty) {
          throw Exception('AI returned empty response');
        }
        
        return jsonDecode(response.text!);
      } catch (e) {
        lastError = e.toString();
        
        // If the error is a Quota/Rate limit (429) or Blocked (Safety), 
        // don't bother trying other models as they share the same quota.
        if (lastError.contains('429') || lastError.contains('quota') || lastError.contains('safety')) {
          throw Exception('Gemini Limit Reached: Please wait a minute and try again. ($lastError)');
        }
        
        // Only continue to next model if it's a "Not Found" error
        if (!lastError.contains('not found') && !lastError.contains('404')) {
          throw Exception('Gemini Error: $lastError');
        }
      }
    }
    throw Exception('All Gemini models are unavailable or not found. Please check your API key and region. Last error: $lastError');
  }

  List<StrokeModel> convertToStrokes(Map<String, dynamic> data, double pxf) {
    final List<StrokeModel> strokes = [];
    final walls = data['walls'] as List?;
    if (walls == null) return strokes;

    for (var w in walls) {
      StrokeType type = StrokeType.wall;
      if (w['type'] == 'door') type = StrokeType.door;
      if (w['type'] == 'window') type = StrokeType.window;

      strokes.add(StrokeModel(
        id: UniqueKey().toString(),
        type: type,
        points: [
          Offset(w['start']['x'].toDouble() * pxf, w['start']['y'].toDouble() * pxf),
          Offset(w['end']['x'].toDouble() * pxf, w['end']['y'].toDouble() * pxf),
        ],
      ));
    }
    return strokes;
  }

  List<dynamic> parseFurniture(Map<String, dynamic> data) {
    return data['furniture'] ?? [];
  }
}
