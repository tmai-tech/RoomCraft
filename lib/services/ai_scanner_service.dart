import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:mime/mime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/accurate_scan.dart';
import '../domain/furniture_vision_filter.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/local_room_scanner.dart';
import '../domain/photo_true_layout.dart';
import '../domain/scan_parser.dart';
import '../domain/scan_refine.dart';
import '../domain/vision_layout_prompts.dart';
import '../domain/wall_relative_scan.dart';
import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'free_vision_scanner.dart';
import 'huggingface_vision_scanner.dart';
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
  /// Backend race (+27): run candidates and **pick best layout quality**, not
  /// first non-empty only.
  /// 1. Groq Llama 4 Scout
  /// 2. Hugging Face Qwen2.5-VL when empty / thin / weak score
  /// 3. Gemini Flash when still weak
  /// 4. Offline empty rectangle
  ///
  /// When [autoScale] is true, room size is estimated from photos (everyday
  /// users). When false, size is locked to measurements / defaults.
  Future<ScanResult> scanRoomAccurateFree(
    List<File> images, {
    Map<File, double>? wallMeasurements,
    RoomLayoutType? layoutType,
    double? roomWidthFt,
    double? roomLengthFt,
    bool tryVision = true,
    bool autoScale = false,
    /// User-labeled wall photos (3–4 walls). Improves exact 4-image plans.
    Map<WallSide, File>? wallPhotoMap,
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
      ScanResult? best;
      final notes = <String>[
        'Scan engines +40: photo-true polish on winner; labeled walls preferred',
      ];
      if (wallPhotoMap != null && wallPhotoMap.length >= 3) {
        notes.add(
          'User wall map: ${wallPhotoMap.keys.map((k) => k.name).join(", ")}',
        );
      } else if (images.length >= 3 && images.length <= 4) {
        notes.add(
          'Default wall order: 0=south 1=east 2=north 3=west '
          '(${images.length} photos)',
        );
      } else if (images.length >= 3 && images.length <= 6) {
        notes.add(
          'Multi-wall mode: ${images.length} photos — cross-check walls for placement',
        );
      }

      // 1) Groq free vision
      if (await FreeVisionScanner.isAvailable()) {
        try {
          best = await FreeVisionScanner().scan(
            images: images,
            roomWidthFt: autoScale ? roomWidthFt : w,
            roomLengthFt: autoScale ? roomLengthFt : l,
            autoScale: autoScale,
            wallPhotoMap: wallPhotoMap,
          );
          notes.add(
            'Groq quality=${_layoutQuality(best)} '
            'furniture=${best.furniture.length}',
          );
        } catch (e) {
          notes.add('Groq vision unavailable: $e');
        }
      }

      // 2) Hugging Face — not only when empty: also when thin/weak Groq plan
      if (await HuggingFaceVisionScanner.isAvailable()) {
        final needHf = best == null || _isWeakLayout(best);
        if (needHf) {
          try {
            final hf = await HuggingFaceVisionScanner().scan(
              images: images,
              roomWidthFt: autoScale ? roomWidthFt : w,
              roomLengthFt: autoScale ? roomLengthFt : l,
              autoScale: autoScale,
            );
            final hfTagged = hf.copyWith(
              warnings: [
                ...hf.warnings,
                'Used Hugging Face open VLM for furniture layout',
              ],
            );
            notes.add(
              'HF quality=${_layoutQuality(hfTagged)} '
              'furniture=${hfTagged.furniture.length}',
            );
            best = _preferLayout(best, hfTagged);
          } catch (e) {
            notes.add('Hugging Face vision unavailable: $e');
          }
        } else {
          notes.add(
            'HF skipped — Groq layout quality=${_layoutQuality(best!)} '
            '(furniture=${best.furniture.length})',
          );
        }
      }

      // 3) Gemini when still weak
      if (best == null || _isWeakLayout(best)) {
        final geminiKey = await resolveGeminiApiKey();
        if (geminiKey != null && geminiKey.isNotEmpty) {
          try {
            final gemini = await _scanWithGemini(
              images,
              geminiKey,
              autoScale ? (best?.roomWidthFt ?? w) : w,
              autoScale ? (best?.roomLengthFt ?? l) : l,
            );
            final enforced = ScanRefine.refine(AccurateScan.enforce(
              widthFt: autoScale ? gemini.roomWidthFt : w,
              lengthFt: autoScale ? gemini.roomLengthFt : l,
              openings: gemini.walls,
              furniture: gemini.furniture,
              warnings: gemini.warnings,
              sourceLabel: 'Free Gemini furniture assist — room size locked',
            ));
            notes.add(
              'Gemini quality=${_layoutQuality(enforced)} '
              'furniture=${enforced.furniture.length}',
            );
            best = _preferLayout(best, enforced);
          } catch (e) {
            notes.add('Gemini assist unavailable: $e');
          }
        }
      }

      if (best != null) {
        // +40: always gold-quality polish the winning backend layout
        best = PhotoTrueLayout.polish(best);
        final winnerNotes = [
          ...best.warnings,
          ...notes.where((n) => !best!.warnings.contains(n)),
          if (PhotoTrueLayout.isPhotoTrue(best))
            'Winner photo-true gold-quality (+40)'
          else
            'Winner polished (+40) — edit openings/furniture on Review if needed',
        ];
        return best.copyWith(warnings: winnerNotes);
      }
    }

    // 4) Offline accurate — always works, zero keys
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
              'Add Groq / Hugging Face / Gemini key in Settings, or pieces from catalog.',
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

    final prompt = VisionLayoutPrompts.lockedSinglePass(roomWidthFt, roomLengthFt);

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
        // Apply same furniture filter as free vision backends.
        final rawFurn = map['furniture'];
        final filtered = FurnitureVisionFilter.filter(
          rawFurn is List ? rawFurn : null,
        );
        map['furniture'] = filtered.kept;
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

  /// +27: weak plan → try next backend (not only empty furniture).
  static bool _isWeakLayout(ScanResult r) {
    if (r.furniture.isEmpty) return true;
    if (r.furniture.length < 2) return true;
    // +40: missing openings is weak (gold plan always has doors)
    final openings = r.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .length;
    if (openings == 0) return true;
    final score = r.accuracyScore;
    if (score != null && score < 0.48) return true;
    // Not photo-true (no wardrobe+table) → still try next backend
    if (!PhotoTrueLayout.isPhotoTrue(r) && r.furniture.length < 3) {
      return true;
    }
    return _layoutQuality(r) < 45;
  }

  /// Higher is better. Favors photo-true inventory (wardrobe/desk + openings).
  static int _layoutQuality(ScanResult r) {
    var q = 0;
    final types = r.furniture.map((f) => f.type).toSet();
    q += r.furniture.length * 10;
    q += types.length * 6;
    if (types.contains(FurnitureType.wardrobe)) q += 28;
    if (types.contains(FurnitureType.table)) q += 28;
    if (types.contains(FurnitureType.bed)) q += 8;
    if (types.contains(FurnitureType.sofa)) q += 8;
    final openings = r.walls
        .where(
          (w) =>
              w.type == StrokeType.door ||
              w.type == StrokeType.window ||
              w.type == StrokeType.balcony,
        )
        .length;
    q += openings.clamp(0, 4) * 6;
    if (openings == 0 && r.furniture.isNotEmpty) q -= 25;
    // +40: gold-quality photo-true bundle
    if (PhotoTrueLayout.isPhotoTrue(r)) q += 50;
    if (r.furniture.isEmpty) q -= 60;
    // Single floating piece is often a bad guess
    if (r.furniture.length == 1) q -= 10;
    final acc = r.accuracyScore;
    if (acc != null) q += (acc * 20).round();
    return q;
  }

  /// Keep the higher-quality layout; ties keep [current].
  /// +40: polish candidates before compare so seeded wardrobe/doors count.
  static ScanResult? _preferLayout(ScanResult? current, ScanResult candidate) {
    final polished = PhotoTrueLayout.polish(candidate);
    if (current == null) return polished;
    final polishedCurrent = PhotoTrueLayout.isPhotoTrue(current)
        ? current
        : PhotoTrueLayout.polish(current);
    final a = _layoutQuality(polishedCurrent);
    final b = _layoutQuality(polished);
    if (b > a) return polished;
    return polishedCurrent;
  }
}
