import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/accurate_scan.dart';
import '../domain/auto_scale.dart';
import '../domain/furniture_vision_filter.dart';
import '../domain/photo_true_layout.dart';
import '../domain/scan_keyframes.dart';
import '../domain/scan_parser.dart';
import '../domain/scan_refine.dart';
import '../domain/vision_layout_prompts.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'free_vision_scanner.dart';
import 'openai_vision_client.dart';
import 'secure_key_store.dart';

/// Free serverless multimodal scan via Hugging Face Inference Providers.
///
/// Uses OpenAI-compatible router + open VLMs (Qwen2.5-VL by default).
/// Token: user Settings key or `ROOMCRAFT_HF_TOKEN` dart-define.
///
/// Depth / Grounding DINO are **not** free on HF Providers — those stay
/// dedicated endpoints. This path is VLM layout JSON only.
class HuggingFaceVisionScanner {
  static const double minConfidence = FurnitureVisionFilter.minConfidence;

  static SecureKeyStore _store([SharedPreferences? prefs]) =>
      SecureKeyStore(prefs: prefs);

  static Future<String?> loadApiKey([SharedPreferences? prefsOverride]) async {
    return _store(prefsOverride).loadHfToken();
  }

  static Future<void> saveApiKey(String key, [SharedPreferences? prefsOverride]) async {
    await _store(prefsOverride).saveHfToken(key);
  }

  static Future<String?> resolveApiKey({
    String? apiKey,
    SharedPreferences? prefsOverride,
  }) async {
    final explicit = apiKey?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final user = await loadApiKey(prefsOverride);
    if (user != null && user.isNotEmpty) return user;
    final bundled = AppConfig.bundledHfToken.trim();
    if (bundled.isNotEmpty) return bundled;
    return null;
  }

  static Future<bool> isAvailable({SharedPreferences? prefsOverride}) async {
    final key = await resolveApiKey(prefsOverride: prefsOverride);
    return key != null && key.isNotEmpty;
  }

  Future<ScanResult> scan({
    required List<File> images,
    double? roomWidthFt,
    double? roomLengthFt,
    String? apiKey,
    bool autoScale = false,
  }) async {
    final key = await resolveApiKey(apiKey: apiKey);
    if (key == null || key.isEmpty) {
      throw Exception('No Hugging Face token available');
    }
    if (images.isEmpty) {
      throw Exception('Add at least one room photo or video frames.');
    }

    final prepared = await ScanKeyframes.pickSharpest(images, maxKeep: 6);
    final frames = prepared.isEmpty ? images.take(6).toList() : prepared;

    final needAuto = autoScale ||
        roomWidthFt == null ||
        roomLengthFt == null ||
        roomWidthFt <= 0 ||
        roomLengthFt <= 0;

    Object? lastError;
    for (final model in AppConfig.hfVisionModelCandidates) {
      try {
        final client = OpenAiVisionClient(
          chatCompletionsUrl: AppConfig.hfChatCompletionsUrl,
          model: model,
          timeout: const Duration(seconds: 120),
        );
        if (needAuto) {
          return await _easyScan(
            client: client,
            key: key,
            frames: frames,
            frameCount: images.length,
            userWidthFt: roomWidthFt,
            userLengthFt: roomLengthFt,
            modelLabel: model,
          );
        }
        return await _lockedScan(
          client: client,
          key: key,
          frames: frames,
          roomWidthFt: roomWidthFt,
          roomLengthFt: roomLengthFt,
          modelLabel: model,
        );
      } catch (e) {
        lastError = e;
        // Try next model on 404 / not found / provider errors.
        continue;
      }
    }
    throw Exception('Hugging Face vision failed: $lastError');
  }

  Future<ScanResult> _easyScan({
    required OpenAiVisionClient client,
    required String key,
    required List<File> frames,
    required int frameCount,
    double? userWidthFt,
    double? userLengthFt,
    required String modelLabel,
  }) async {
    final warnings = <String>[
      'Easy scan: $frameCount frame(s) · Hugging Face serverless',
      'Model: $modelLabel',
    ];

    var inventoryHint = '';
    try {
      final inv = await client.completeJson(
        apiKey: key,
        frames: frames,
        prompt: VisionLayoutPrompts.inventoryPass(),
        system: VisionLayoutPrompts.inventorySystem,
        temperature: 0.0,
      );
      inventoryHint = FreeVisionScanner.formatInventoryHintPublic(inv);
      warnings.add('Inventory: $inventoryHint');
    } catch (_) {}

    var layoutJson = await client.completeJson(
      apiKey: key,
      frames: frames,
      prompt: VisionLayoutPrompts.consumerLayout(
        inventoryHint: inventoryHint,
        frameCount: frameCount,
      ),
      system: VisionLayoutPrompts.consumerSystem,
    );
    final gated = FreeVisionScanner.applyInventoryCompletePublic(
      layoutJson,
      inventoryHint,
    );
    layoutJson = gated.map;
    if (gated.added > 0) {
      warnings.add(
        'Seeded ${gated.added} inventory-required piece(s) model omitted',
      );
    }

    final vW = _asDouble(layoutJson['roomWidth']) ??
        _asDouble(layoutJson['room_width']);
    final vL = _asDouble(layoutJson['roomLength']) ??
        _asDouble(layoutJson['room_length']);
    final vConf = _asDouble(layoutJson['sizeConfidence']) ??
        _asDouble(layoutJson['size_confidence']) ??
        0.5;

    final provisionalW =
        (vW != null && vW > 0) ? vW : AutoScale.fallbackWidthFt;
    final provisionalL =
        (vL != null && vL > 0) ? vL : AutoScale.fallbackLengthFt;
    layoutJson['roomWidth'] = provisionalW;
    layoutJson['roomLength'] = provisionalL;

    final filtered = _filterFurnitureMap(layoutJson);
    if (filtered.dropped > 0) {
      warnings.add(
        'Dropped ${filtered.dropped} low-confidence furniture guess(es)',
      );
    }
    final parsed = ScanParser.parse(filtered.map);

    final doorWidths = AutoScale.doorWidthsFromWalls(parsed.walls);
    final size = AutoScale.resolve(
      userWidthFt: userWidthFt,
      userLengthFt: userLengthFt,
      visionWidthFt: provisionalW,
      visionLengthFt: provisionalL,
      visionSizeConfidence: vConf,
      doorWidthsFt: doorWidths,
      furniture: [
        for (final f in parsed.furniture)
          (
            type: f.type.name.toUpperCase(),
            widthFt: f.widthFt,
            lengthFt: f.lengthFt,
          ),
      ],
    );
    warnings.addAll(size.notes);

    var result = AccurateScan.enforce(
      widthFt: size.widthFt,
      lengthFt: size.lengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: warnings,
      sourceLabel: 'Easy plan — HF $modelLabel',
      inventDefaultOpenings: false,
    );

    if ((provisionalW - size.widthFt).abs() > 0.4 ||
        (provisionalL - size.lengthFt).abs() > 0.4) {
      final scaled = AutoScale.rescaleResult(
        ScanResult(
          roomWidthFt: provisionalW,
          roomLengthFt: provisionalL,
          walls: parsed.walls,
          furniture: parsed.furniture,
          warnings: const [],
        ),
        newWidthFt: size.widthFt,
        newLengthFt: size.lengthFt,
      );
      result = AccurateScan.enforce(
        widthFt: size.widthFt,
        lengthFt: size.lengthFt,
        openings: scaled.walls,
        furniture: scaled.furniture,
        warnings: warnings,
        sourceLabel: 'Easy plan — HF $modelLabel',
        inventDefaultOpenings: false,
      );
    }

    final openingsCount = result.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .length;
    final accuracy = _estimateAccuracy(
      frames: frames.length,
      furnitureCount: result.furniture.length,
      openingsCount: openingsCount,
      dropped: filtered.dropped,
      autoScale: !size.usedUserSize,
      scaleConfidence: size.confidence,
    );
    if (result.furniture.isEmpty) {
      warnings.add('HF returned no furniture — check photos or add from catalog');
    }

    // +40: gold-quality polish (wall-hug, openings spread, score bar)
    return PhotoTrueLayout.polish(ScanRefine.refine(result.copyWith(
      warnings: warnings,
      accuracyScore: accuracy,
    )));
  }

  Future<ScanResult> _lockedScan({
    required OpenAiVisionClient client,
    required String key,
    required List<File> frames,
    required double roomWidthFt,
    required double roomLengthFt,
    required String modelLabel,
  }) async {
    final warnings = <String>[
      'HF multi-frame scan · size locked '
          '${roomWidthFt.toStringAsFixed(1)}×${roomLengthFt.toStringAsFixed(1)} ft',
      'Model: $modelLabel',
    ];

    Map<String, dynamic> archJson = {};
    try {
      archJson = await client.completeJson(
        apiKey: key,
        frames: frames,
        prompt: VisionLayoutPrompts.architecture(roomWidthFt, roomLengthFt),
        system: VisionLayoutPrompts.architectureSystem,
      );
    } catch (e) {
      warnings.add('Architecture pass partial: $e');
    }

    Map<String, dynamic> furnJson = {};
    try {
      furnJson = await client.completeJson(
        apiKey: key,
        frames: frames,
        prompt: VisionLayoutPrompts.furniture(roomWidthFt, roomLengthFt),
        system: VisionLayoutPrompts.furnitureSystem,
      );
    } catch (e) {
      warnings.add('Furniture pass partial: $e');
    }

    final merged = <String, dynamic>{
      'roomWidth': roomWidthFt,
      'roomLength': roomLengthFt,
      'walls': archJson['walls'] ?? [],
      'furniture': furnJson['furniture'] ?? [],
      'openings': archJson['openings'] ?? archJson['walls'] ?? [],
    };
    if (archJson['openings'] is List &&
        (archJson['openings'] as List).isNotEmpty) {
      merged['walls'] = archJson['openings'];
    }

    final filtered = _filterFurnitureMap(merged);
    if (filtered.dropped > 0) {
      warnings.add(
        'Dropped ${filtered.dropped} low-confidence furniture guess(es)',
      );
    }
    final parsed = ScanParser.parse(filtered.map);
    final accuracy = _estimateAccuracy(
      frames: frames.length,
      furnitureCount: parsed.furniture.length,
      openingsCount: parsed.walls
          .where((w) =>
              w.type == StrokeType.door ||
              w.type == StrokeType.window ||
              w.type == StrokeType.balcony)
          .length,
      dropped: filtered.dropped,
    );

    return PhotoTrueLayout.polish(ScanRefine.refine(AccurateScan.enforce(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: warnings,
      sourceLabel: 'HF $modelLabel — size locked',
      inventDefaultOpenings: false,
      accuracyScore: accuracy,
    )));
  }

  static ({Map<String, dynamic> map, int dropped}) _filterFurnitureMap(
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

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static double _estimateAccuracy({
    required int frames,
    required int furnitureCount,
    required int openingsCount,
    required int dropped,
    bool autoScale = false,
    double scaleConfidence = 0.5,
  }) {
    var score = autoScale ? 0.35 : 0.42;
    score += (frames.clamp(1, 8) / 8) * 0.20;
    if (openingsCount > 0) score += 0.10;
    if (furnitureCount > 0) {
      score += 0.12;
      score += (furnitureCount.clamp(1, 6) / 6) * 0.12;
    } else {
      score = score.clamp(0.0, 0.48);
    }
    if (dropped == 0 && furnitureCount > 0) score += 0.05;
    if (autoScale) {
      score += (scaleConfidence - 0.4).clamp(0.0, 0.15);
      return score.clamp(0.28, furnitureCount == 0 ? 0.50 : 0.82);
    }
    return score.clamp(0.30, furnitureCount == 0 ? 0.52 : 0.92);
  }
}
