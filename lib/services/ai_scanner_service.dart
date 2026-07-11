import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/local_room_scanner.dart';
import '../domain/scan_parser.dart';
import '../models/scan_result.dart';

/// Room scanning: free offline estimator by default; optional Gemini if key works.
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

  /// Always succeeds offline — checks image is readable.
  Future<String?> validateImage(File image) async {
    try {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return 'Empty image file';
      if (bytes.length < 1000) return 'Image seems too small — retake closer to the room';
      return null; // OK
    } catch (e) {
      return 'Could not read image: $e';
    }
  }

  /// Free offline scan (no API). Preferred path when Gemini is limited/unavailable.
  Future<ScanResult> scanRoomFree(
    List<File> images, {
    Map<File, double>? wallMeasurements,
    RoomLayoutType? layoutType,
  }) {
    return LocalRoomScanner.scan(
      images: images,
      wallMeasurementsFt: wallMeasurements,
      preferredLayout: layoutType,
    );
  }

  /// Scan photos. Uses free offline estimator first; optional Gemini if [preferGemini].
  Future<ScanResult> scanRoom(
    List<File> images, {
    Map<File, double>? wallMeasurements,
    bool preferGemini = false,
    RoomLayoutType? layoutType,
  }) async {
    if (images.isEmpty) {
      throw Exception('Add at least one room photo.');
    }

    // Default: free offline (no quota limits)
    if (!preferGemini) {
      return scanRoomFree(
        images,
        wallMeasurements: wallMeasurements,
        layoutType: layoutType,
      );
    }

    final apiKey = await loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      // Fall back to free
      final free = await scanRoomFree(
        images,
        wallMeasurements: wallMeasurements,
        layoutType: layoutType,
      );
      return free.copyWith(
        warnings: [
          ...free.warnings,
          'No Gemini key — used free offline scan',
        ],
      );
    }

    try {
      return await _scanWithGemini(images, apiKey, wallMeasurements);
    } catch (e) {
      // Quota / network / model errors → free fallback
      final free = await scanRoomFree(
        images,
        wallMeasurements: wallMeasurements,
        layoutType: layoutType,
      );
      return free.copyWith(
        warnings: [
          ...free.warnings,
          'Gemini unavailable ($e) — used free offline scan instead',
        ],
      );
    }
  }

  Future<ScanResult> _scanWithGemini(
    List<File> images,
    String apiKey,
    Map<File, double>? wallMeasurements,
  ) async {
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
        final map = decoded is Map<String, dynamic>
            ? decoded
            : Map<String, dynamic>.from(decoded as Map);
        return ScanParser.parse(map);
      } catch (e) {
        lastError = e.toString();
        if (lastError.contains('429') ||
            lastError.contains('quota') ||
            lastError.contains('limit') ||
            lastError.contains('Resource exhausted')) {
          throw Exception('Gemini quota exceeded');
        }
        if (!lastError.contains('not found') && !lastError.contains('404')) {
          if (lastError.contains('empty') || lastError.contains('JSON')) {
            continue;
          }
          rethrow;
        }
      }
    }
    throw Exception('Gemini models unavailable: $lastError');
  }
}
