import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/accurate_scan.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/local_room_scanner.dart';
import '../domain/scan_parser.dart';
import '../models/scan_result.dart';
import 'free_vision_scanner.dart';
import 'secure_key_store.dart';

/// Room scanning with free accurate default (no user API key required).
///
/// Accuracy contract:
/// - Room width × length always come from user measurements.
/// - Walls are a clean rectangle at that size (measured layout sketch, not LiDAR).
/// - Optional free vision only proposes furniture / openings; never resizes room.
class AIScannerService {
  static SecureKeyStore _store([SharedPreferences? prefs]) =>
      SecureKeyStore(prefs: prefs);

  static Future<String?> loadApiKey([SharedPreferences? prefsOverride]) async {
    return _store(prefsOverride).loadGeminiKey();
  }

  static Future<void> saveApiKey(String key, [SharedPreferences? prefsOverride]) async {
    await _store(prefsOverride).saveGeminiKey(key);
  }

  /// Gemini key: secure user key, then bundled dart-define.
  static Future<String?> resolveGeminiApiKey([
    SharedPreferences? prefsOverride,
  ]) async {
    final user = await loadApiKey(prefsOverride);
    if (user != null && user.isNotEmpty) return user;
    final bundled = AppConfig.bundledGeminiApiKey.trim();
    if (bundled.isNotEmpty) return bundled;
    return null;
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

  /// Free offline accurate plan (exact size, no invented furniture unless preset).
  Future<ScanResult> scanRoomFree(
    List<File> images, {
    Map<File, double>? wallMeasurements,
    RoomLayoutType? layoutType,
    double? roomWidthFt,
    double? roomLengthFt,
  }) async {
    final size = resolveSize(
      roomWidthFt: roomWidthFt,
      roomLengthFt: roomLengthFt,
      wallMeasurements: wallMeasurements,
    );
    final raw = await LocalRoomScanner.scan(
      images: images,
      wallMeasurementsFt: wallMeasurements,
      preferredLayout: layoutType,
      roomWidthFt: size.widthFt,
      roomLengthFt: size.lengthFt,
    );
    return AccurateScan.enforce(
      widthFt: size.widthFt,
      lengthFt: size.lengthFt,
      openings: raw.walls,
      furniture: raw.furniture,
      warnings: raw.warnings.where((w) => !w.startsWith('Exact room')).toList(),
      sourceLabel: 'Free accurate offline plan — no API key needed',
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

  /// Primary free path: accurate geometry + optional free vision furniture.
  ///
  /// Does **not** require the user to paste a key. Uses app-bundled keys when
  /// present (`ROOMCRAFT_GROQ_API_KEY` / `ROOMCRAFT_GEMINI_API_KEY`), then user
  /// keys, then offline empty plan. Room size is always locked.
  Future<ScanResult> scanRoomAccurateFree(
    List<File> images, {
    Map<File, double>? wallMeasurements,
    RoomLayoutType? layoutType,
    double? roomWidthFt,
    double? roomLengthFt,
    bool tryVision = true,
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

    if (tryVision) {
      // 1) Free Groq vision (bundled or user key)
      if (await FreeVisionScanner.isAvailable()) {
        try {
          return await FreeVisionScanner().scan(
            images: images,
            roomWidthFt: w,
            roomLengthFt: l,
          );
        } catch (e) {
          // Fall through — accuracy preserved via offline path
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
              'Free vision unavailable ($e) — kept exact empty plan',
            ],
          );
        }
      }

      // 2) Bundled / user Gemini as free-tier alternative
      final geminiKey = await resolveGeminiApiKey();
      if (geminiKey != null && geminiKey.isNotEmpty) {
        try {
          final gemini = await _scanWithGemini(images, geminiKey, w, l);
          return AccurateScan.enforce(
            widthFt: w,
            lengthFt: l,
            openings: gemini.walls,
            furniture: gemini.furniture,
            warnings: gemini.warnings,
            sourceLabel: 'Free Gemini furniture assist — room size locked',
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
              'Gemini assist unavailable ($e) — kept exact empty plan',
            ],
          );
        }
      }
    }

    // 3) Offline accurate — always works, zero keys
    final offline = await scanRoomFree(
      images,
      wallMeasurements: wallMeasurements,
      layoutType: layoutType,
      roomWidthFt: w,
      roomLengthFt: l,
    );
    if (offline.furniture.isEmpty && tryVision) {
      return offline.copyWith(
        warnings: [
          ...offline.warnings,
          'No free vision key on this build — furniture list empty. '
              'Room size is still exact; add pieces from the catalog.',
        ],
      );
    }
    return offline;
  }

  /// Scan photos.
  ///
  /// [preferFreeVision] / [preferGemini] force a backend when keys exist.
  /// Default uses [scanRoomAccurateFree] (no user key required).
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

    // Explicit free vision only
    if (preferFreeVision) {
      return scanRoomAccurateFree(
        images,
        wallMeasurements: wallMeasurements,
        layoutType: layoutType,
        roomWidthFt: w,
        roomLengthFt: l,
        tryVision: true,
      );
    }

    // Explicit Gemini only
    if (preferGemini) {
      final apiKey = await resolveGeminiApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        return scanRoomAccurateFree(
          images,
          wallMeasurements: wallMeasurements,
          layoutType: layoutType ?? RoomLayoutType.empty,
          roomWidthFt: w,
          roomLengthFt: l,
          tryVision: false,
        );
      }
      try {
        final gemini = await _scanWithGemini(images, apiKey, w, l);
        return AccurateScan.enforce(
          widthFt: w,
          lengthFt: l,
          openings: gemini.walls,
          furniture: gemini.furniture,
          warnings: gemini.warnings,
          sourceLabel: 'Gemini scan — room size locked to your measurements',
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
            'Gemini unavailable ($e) — used free accurate offline scan',
          ],
        );
      }
    }

    // Default: free accurate (vision if app/user key, else offline)
    return scanRoomAccurateFree(
      images,
      wallMeasurements: wallMeasurements,
      layoutType: layoutType,
      roomWidthFt: w,
      roomLengthFt: l,
      tryVision: true,
    );
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

    final prompt = '''You are a strict visual inspector for floor plans.
ROOM SIZE IS FIXED (do not change):
- roomWidth = $roomWidthFt feet
- roomLength = $roomLengthFt feet

Look at the photos. Return a top-down plan. Default furniture to EMPTY.
Only list furniture that is CLEARLY visible. Do not invent a typical bedroom/living set.

Return ONLY JSON (no markdown). Prefer empty furniture:
{
  "roomWidth": $roomWidthFt,
  "roomLength": $roomLengthFt,
  "walls": [
    {"type": "wall", "start": {"x": 0, "y": 0}, "end": {"x": $roomWidthFt, "y": 0}},
    {"type": "wall", "start": {"x": $roomWidthFt, "y": 0}, "end": {"x": $roomWidthFt, "y": $roomLengthFt}},
    {"type": "wall", "start": {"x": $roomWidthFt, "y": $roomLengthFt}, "end": {"x": 0, "y": $roomLengthFt}},
    {"type": "wall", "start": {"x": 0, "y": $roomLengthFt}, "end": {"x": 0, "y": 0}}
  ],
  "furniture": []
}
If an item is clearly visible, add objects like:
{"type": "TABLE", "pos": {"x": 4, "y": 5}, "dim": {"w": 3, "l": 2}, "rot": 0, "confidence": 0.9, "evidence": "table visible center"}
Rules:
- ALWAYS keep roomWidth=$roomWidthFt and roomLength=$roomLengthFt.
- Types only: BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND.
- NEVER invent BED/SOFA/TV/BOOKSHELF that is not in the photo.
- If unsure or blurry, furniture must be [].
- confidence 0-1; omit items under 0.75.
- pos is CENTER in feet; rot in degrees.
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
