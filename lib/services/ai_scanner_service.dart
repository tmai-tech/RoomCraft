import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/local_room_scanner.dart';
import '../domain/scan_parser.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'free_vision_scanner.dart';

/// Room scanning: free offline (exact size) → free Groq vision → optional Gemini.
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

  /// Free offline scan with exact room proportions. No invented furniture unless preset.
  Future<ScanResult> scanRoomFree(
    List<File> images, {
    Map<File, double>? wallMeasurements,
    RoomLayoutType? layoutType,
    double? roomWidthFt,
    double? roomLengthFt,
  }) {
    return LocalRoomScanner.scan(
      images: images,
      wallMeasurementsFt: wallMeasurements,
      preferredLayout: layoutType,
      roomWidthFt: roomWidthFt,
      roomLengthFt: roomLengthFt,
    );
  }

  /// Resolve dimensions once for all scan backends.
  ({double widthFt, double lengthFt, List<String> notes}) resolveSize({
    double? roomWidthFt,
    double? roomLengthFt,
    Map<File, double>? wallMeasurements,
  }) {
    return LocalRoomScanner.resolveDimensions(
      roomWidthFt: roomWidthFt,
      roomLengthFt: roomLengthFt,
      wallMeasurementsFt: wallMeasurements,
    );
  }

  /// Scan photos.
  ///
  /// [preferFreeVision] uses Groq (free tier) for real furniture from photos.
  /// [preferGemini] uses Gemini when a Google key is set.
  /// Default offline path never invents beds / sofas and keeps exact W×L.
  Future<ScanResult> scanRoom(
    List<File> images, {
    Map<File, double>? wallMeasurements,
    bool preferGemini = false,
    bool preferFreeVision = false,
    RoomLayoutType? layoutType,
    double? roomWidthFt,
    double? roomLengthFt,
  }) async {
    if (images.isEmpty) {
      throw Exception('Add at least one room photo.');
    }

    final size = resolveSize(
      roomWidthFt: roomWidthFt,
      roomLengthFt: roomLengthFt,
      wallMeasurements: wallMeasurements,
    );
    final w = size.widthFt;
    final l = size.lengthFt;

    // 1) Free Groq vision — real furniture, locked proportions
    if (preferFreeVision) {
      final groqKey = await FreeVisionScanner.loadApiKey();
      if (groqKey != null && groqKey.isNotEmpty) {
        try {
          final vision = await FreeVisionScanner().scan(
            images: images,
            roomWidthFt: w,
            roomLengthFt: l,
            apiKey: groqKey,
          );
          return vision.copyWith(
            roomWidthFt: w,
            roomLengthFt: l,
            walls: _rectangleWalls(w, l, vision.walls),
          );
        } catch (e) {
          final free = await scanRoomFree(
            images,
            wallMeasurements: wallMeasurements,
            layoutType: layoutType ?? RoomLayoutType.empty,
            roomWidthFt: w,
            roomLengthFt: l,
          );
          return free.copyWith(
            warnings: [
              ...free.warnings,
              'Free AI unavailable ($e) — empty proportionate plan used',
            ],
          );
        }
      }
      final free = await scanRoomFree(
        images,
        wallMeasurements: wallMeasurements,
        layoutType: layoutType ?? RoomLayoutType.empty,
        roomWidthFt: w,
        roomLengthFt: l,
      );
      return free.copyWith(
        warnings: [
          ...free.warnings,
          'No free AI (Groq) key — used offline proportionate plan',
        ],
      );
    }

    // 2) Optional Gemini
    if (preferGemini) {
      final apiKey = await loadApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        final free = await scanRoomFree(
          images,
          wallMeasurements: wallMeasurements,
          layoutType: layoutType ?? RoomLayoutType.empty,
          roomWidthFt: w,
          roomLengthFt: l,
        );
        return free.copyWith(
          warnings: [
            ...free.warnings,
            'No Gemini key — used free offline scan',
          ],
        );
      }
      try {
        final gemini = await _scanWithGemini(images, apiKey, w, l);
        return gemini.copyWith(
          roomWidthFt: w,
          roomLengthFt: l,
          walls: _rectangleWalls(w, l, gemini.walls),
          warnings: [
            'Room locked to ${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft (your size)',
            ...gemini.warnings,
          ],
        );
      } catch (e) {
        final free = await scanRoomFree(
          images,
          wallMeasurements: wallMeasurements,
          layoutType: layoutType ?? RoomLayoutType.empty,
          roomWidthFt: w,
          roomLengthFt: l,
        );
        return free.copyWith(
          warnings: [
            ...free.warnings,
            'Gemini unavailable ($e) — used free offline scan instead',
          ],
        );
      }
    }

    // 3) Default offline — exact size, no invented furniture unless preset
    return scanRoomFree(
      images,
      wallMeasurements: wallMeasurements,
      layoutType: layoutType,
      roomWidthFt: w,
      roomLengthFt: l,
    );
  }

  /// Prefer a clean rectangle at exact size; keep door/window segments if present.
  List<ScanWallSegment> _rectangleWalls(
    double w,
    double l,
    List<ScanWallSegment> fromAi,
  ) {
    final outline = <ScanWallSegment>[
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset.zero,
        endFt: Offset(w, 0),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(w, 0),
        endFt: Offset(w, l),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(w, l),
        endFt: Offset(0, l),
      ),
      ScanWallSegment(
        type: StrokeType.wall,
        startFt: Offset(0, l),
        endFt: Offset.zero,
      ),
    ];
    final openings = fromAi
        .where((s) =>
            s.type == StrokeType.door ||
            s.type == StrokeType.window ||
            s.type == StrokeType.balcony)
        .toList();
    if (openings.isEmpty) {
      final doorLen = (3.0).clamp(1.0, w * 0.3);
      openings.addAll([
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(w * 0.35, 0),
          endFt: Offset(w * 0.35 + doorLen, 0),
        ),
        ScanWallSegment(
          type: StrokeType.window,
          startFt: Offset(w * 0.25, l),
          endFt: Offset(w * 0.55, l),
        ),
      ]);
    }
    return [...outline, ...openings];
  }

  Future<ScanResult> _scanWithGemini(
    List<File> images,
    String apiKey,
    double roomWidthFt,
    double roomLengthFt,
  ) async {
    final imageParts = <DataPart>[];
    for (final image in images) {
      final bytes = await image.readAsBytes();
      final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
      imageParts.add(DataPart(mimeType, bytes));
    }

    final prompt = '''You are an expert architectural assistant.
ROOM SIZE IS FIXED (do not change):
- roomWidth = $roomWidthFt feet
- roomLength = $roomLengthFt feet

Analyze these room photos and estimate a TOP-DOWN floor plan layout.
Include walls, doors, windows, balconies AND only furniture visible in photos.

Return ONLY JSON (no markdown):
{
  "roomWidth": $roomWidthFt,
  "roomLength": $roomLengthFt,
  "walls": [
    {"type": "wall", "start": {"x": 0, "y": 0}, "end": {"x": $roomWidthFt, "y": 0}},
    {"type": "door", "start": {"x": 5, "y": 0}, "end": {"x": 8, "y": 0}}
  ],
  "furniture": [
    {"type": "BED", "pos": {"x": 2, "y": 2}, "dim": {"w": 5, "l": 6.5}, "rot": 0}
  ]
}
Rules:
- Coordinates in feet, origin at a corner of the room.
- ALWAYS keep roomWidth=$roomWidthFt and roomLength=$roomLengthFt.
- Furniture type MUST be one of: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND.
- Only include furniture you can see. If unsure, use empty furniture array.
- NEVER invent a bed or sofa that is not in the photo.
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
        map['roomWidth'] = roomWidthFt;
        map['roomLength'] = roomLengthFt;
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
