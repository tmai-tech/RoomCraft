import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../domain/accurate_scan.dart';
import '../domain/auto_scale.dart';
import '../domain/furniture_vision_filter.dart';
import '../domain/scan_keyframes.dart';
import '../domain/scan_parser.dart';
import '../domain/scan_refine.dart';
import '../domain/vision_layout_prompts.dart';
import '../domain/wall_relative_scan.dart';
import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'openai_vision_client.dart';
import 'secure_key_store.dart';
import 'wall_relative_vision.dart';

/// Free multimodal scan via Groq (Llama 4 Scout vision).
///
/// **Easy mode** ([autoScale]): no tape required — estimate room size from
/// photos/video + door/furniture priors, then place openings/furniture.
///
/// **Locked mode** (default when size given): multi-frame interior-designer
/// pass; user room size remains authoritative.
class FreeVisionScanner {
  /// Aligned with [FurnitureVisionFilter.minConfidence] for recall.
  static const double minConfidence = FurnitureVisionFilter.minConfidence;

  static SecureKeyStore _store([SharedPreferences? prefs]) =>
      SecureKeyStore(prefs: prefs);

  static Future<String?> loadApiKey([SharedPreferences? prefsOverride]) async {
    return _store(prefsOverride).loadGroqKey();
  }

  static Future<void> saveApiKey(String key, [SharedPreferences? prefsOverride]) async {
    await _store(prefsOverride).saveGroqKey(key);
  }

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

  OpenAiVisionClient get _client => OpenAiVisionClient(
        chatCompletionsUrl: AppConfig.groqChatCompletionsUrl,
        model: AppConfig.groqVisionModel,
      );

  /// Full scan: architecture (openings) + furniture from many frames.
  ///
  /// When [autoScale] is true (or width/length are null), estimates size for
  /// everyday users who only upload photos/video.
  Future<ScanResult> scan({
    required List<File> images,
    double? roomWidthFt,
    double? roomLengthFt,
    String? apiKey,
    bool precisionMode = true,
    bool autoScale = false,
  }) async {
    final key = await resolveApiKey(apiKey: apiKey);
    if (key == null || key.isEmpty) {
      throw Exception('No free vision key available');
    }
    if (images.isEmpty) {
      throw Exception('Add at least one room photo or video frames.');
    }

    // Prefer sharpest diverse frames for the model (token/payload limits).
    final prepared = await ScanKeyframes.pickSharpest(images, maxKeep: 8);
    final frames = prepared.isEmpty ? images.take(8).toList() : prepared;

    final needAuto =
        autoScale || roomWidthFt == null || roomLengthFt == null ||
            roomWidthFt <= 0 ||
            roomLengthFt <= 0;

    if (needAuto) {
      return _consumerEasyScan(
        key: key,
        frames: frames,
        frameCount: images.length,
        userWidthFt: roomWidthFt,
        userLengthFt: roomLengthFt,
      );
    }

    // After needAuto early-return, both dimensions are positive non-null.
    final lockedW = roomWidthFt;
    final lockedL = roomLengthFt;
    if (precisionMode) {
      return _precisionScan(
        key: key,
        frames: frames,
        roomWidthFt: lockedW,
        roomLengthFt: lockedL,
        frameCount: images.length,
      );
    }

    return _singlePassScan(
      key: key,
      frames: frames,
      roomWidthFt: lockedW,
      roomLengthFt: lockedL,
    );
  }

  /// Consumer path: film/photos → estimated plan without tape knowledge.
  Future<ScanResult> _consumerEasyScan({
    required String key,
    required List<File> frames,
    required int frameCount,
    double? userWidthFt,
    double? userLengthFt,
  }) async {
    final warnings = <String>[
      'Easy scan: $frameCount frame(s) · no tape required',
      'Walk every wall in the video for best doors/windows/furniture.',
    ];

    // Pass 1 — inventory (what exists) so placement cannot invent beds/sofas.
    var inventoryHint = '';
    try {
      final inv = await _client.completeJson(
        apiKey: key,
        frames: frames,
        prompt: VisionLayoutPrompts.inventoryPass(),
        system: VisionLayoutPrompts.inventorySystem,
        temperature: 0.0,
      );
      inventoryHint = _formatInventoryHint(inv);
      warnings.add('Inventory: $inventoryHint');
    } catch (e) {
      warnings.add('Inventory pass skipped: $e');
    }

    // Bulk multi-image first (size estimate + layout candidate).
    // Wall-by-wall runs after size is known (+30) so placement uses real feet.
    Map<String, dynamic> layoutJson = {};
    try {
      layoutJson = await _client.completeJson(
        apiKey: key,
        frames: frames,
        prompt: VisionLayoutPrompts.consumerLayout(
          inventoryHint: inventoryHint,
          frameCount: frameCount,
        ),
        system: VisionLayoutPrompts.consumerSystem,
      );
    } catch (e) {
      warnings.add('Layout pass failed: $e');
      // Still try wall-by-wall with fallback size when bulk fails.
      if (frames.length >= 3 && frames.length <= 4) {
        try {
          final fallback = await _orderedWallByWallScan(
            key: key,
            frames: frames,
            userWidthFt: userWidthFt,
            userLengthFt: userLengthFt,
            inventoryHint: inventoryHint,
          );
          if (fallback.furniture.isNotEmpty) {
            return fallback.copyWith(
              warnings: [...fallback.warnings, ...warnings],
            );
          }
        } catch (e2) {
          warnings.add('Wall-by-wall fallback failed: $e2');
        }
      }
      final size = AutoScale.resolve(
        userWidthFt: userWidthFt,
        userLengthFt: userLengthFt,
      );
      return AccurateScan.enforce(
        widthFt: size.widthFt,
        lengthFt: size.lengthFt,
        openings: const [],
        furniture: const [],
        warnings: [...warnings, ...size.notes],
        sourceLabel: 'Easy scan fallback — empty plan',
        inventDefaultOpenings: false,
        accuracyScore: size.confidence * 0.5,
      );
    }

    // Strip invented types; seed MUST pieces inventory required but model omitted.
    layoutJson = _applyInventoryGate(layoutJson, inventoryHint);
    final seeded = _seedMissingFromInventory(layoutJson, inventoryHint);
    if (seeded.added > 0) {
      warnings.add(
        'Seeded ${seeded.added} inventory-required piece(s) model omitted',
      );
    }
    layoutJson = seeded.map;

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
    final cues = layoutJson['scaleCues'] ?? layoutJson['scale_cues'];
    if (cues is List) {
      for (final c in cues) {
        if (c is! Map) continue;
        final type = c['type']?.toString().toLowerCase() ?? '';
        final w = _asDouble(c['widthFt']) ?? _asDouble(c['width']);
        if (type.contains('door') && w != null && w > 0) {
          doorWidths.add(w);
        }
      }
    }

    final furnPriors = <({String type, double widthFt, double lengthFt})>[
      for (final f in parsed.furniture)
        (
          type: f.type.name.toUpperCase(),
          widthFt: f.widthFt,
          lengthFt: f.lengthFt,
        ),
    ];

    final size = AutoScale.resolve(
      userWidthFt: userWidthFt,
      userLengthFt: userLengthFt,
      visionWidthFt: provisionalW,
      visionLengthFt: provisionalL,
      visionSizeConfidence: vConf,
      doorWidthsFt: doorWidths,
      furniture: furnPriors,
    );
    warnings.addAll(size.notes);

    var result = AccurateScan.enforce(
      widthFt: size.widthFt,
      lengthFt: size.lengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: warnings,
      sourceLabel: 'Easy photo/video plan — Groq Llama 4 Scout',
      inventDefaultOpenings: false,
      accuracyScore: null,
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
        sourceLabel: 'Easy photo/video plan — Groq Llama 4 Scout',
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
    warnings.add(
      'Layout confidence ~${(accuracy * 100).round()}% '
      '(more wall coverage + clear doors improve scale)',
    );
    if (result.furniture.isEmpty) {
      warnings.add(
        'No furniture detected — use Gallery multi-select: every wall, '
        'wardrobe/desk fully visible, good light; or add from catalog',
      );
    } else {
      warnings.add(
        'Tip: multi-wall full-res photos improve placement. Edit on Review if needed.',
      );
    }

    var bulk = ScanRefine.refine(result.copyWith(
      warnings: warnings,
      accuracyScore: accuracy,
    ));
    bulk = _dedupeMajorFurniture(bulk);

    // +30: wall-by-wall AFTER bulk size lock (feet accurate enough for placement).
    ScanResult? wallByWall;
    if (frames.length >= 3 && frames.length <= 4) {
      try {
        wallByWall = await _orderedWallByWallScan(
          key: key,
          frames: frames,
          userWidthFt: size.widthFt,
          userLengthFt: size.lengthFt,
          inventoryHint: inventoryHint,
        );
        // Re-lock wall plan to the same AutoScale room size as bulk.
        if ((wallByWall.roomWidthFt - size.widthFt).abs() > 0.15 ||
            (wallByWall.roomLengthFt - size.lengthFt).abs() > 0.15) {
          wallByWall = AutoScale.rescaleResult(
            wallByWall,
            newWidthFt: size.widthFt,
            newLengthFt: size.lengthFt,
          );
          wallByWall = ScanRefine.refine(wallByWall);
        }
        wallByWall = _dedupeMajorFurniture(wallByWall);
        warnings.add(
          'Wall-by-wall (+30) @ ${size.widthFt.toStringAsFixed(1)}×'
          '${size.lengthFt.toStringAsFixed(1)} ft: '
          '${wallByWall.furniture.length} piece(s)',
        );
      } catch (e) {
        warnings.add('Wall-by-wall path failed: $e');
      }
    }

    // Prefer wall-by-wall on tie/near-tie (designer placement is more stable).
    if (wallByWall != null) {
      final bulkScore = _easyQuality(bulk, inventoryHint);
      final wallScore = _easyQuality(wallByWall, inventoryHint);
      warnings.add('Bulk score=$bulkScore · wall-by-wall score=$wallScore');
      if (wallScore >= bulkScore - 5) {
        return wallByWall.copyWith(
          warnings: [
            ...wallByWall.warnings,
            ...warnings.where((w) => !wallByWall!.warnings.contains(w)),
            'Selected wall-by-wall plan (stable multi-wall placement)',
          ],
        );
      }
    }
    return bulk.copyWith(
      warnings: [...bulk.warnings, ...warnings.where((w) => !bulk.warnings.contains(w))],
    );
  }

  /// Keep one of each major type (wardrobe/bed/sofa/tv) to reduce doubles.
  static ScanResult _dedupeMajorFurniture(ScanResult r) {
    const majors = {
      FurnitureType.wardrobe,
      FurnitureType.bed,
      FurnitureType.sofa,
      FurnitureType.tvUnit,
      FurnitureType.table,
    };
    final seen = <FurnitureType>{};
    final kept = <ScanFurnitureHint>[];
    for (final f in r.furniture) {
      if (majors.contains(f.type)) {
        if (seen.contains(f.type)) continue;
        seen.add(f.type);
      }
      kept.add(f);
    }
    if (kept.length == r.furniture.length) return r;
    return r.copyWith(
      furniture: kept,
      warnings: [
        ...r.warnings,
        'Deduped major furniture (${r.furniture.length - kept.length} dropped)',
      ],
    );
  }

  /// 3–4 photos mapped south→east→north→west (upload order).
  Future<ScanResult> _orderedWallByWallScan({
    required String key,
    required List<File> frames,
    double? userWidthFt,
    double? userLengthFt,
    required String inventoryHint,
  }) async {
    final size = AutoScale.resolve(
      userWidthFt: userWidthFt,
      userLengthFt: userLengthFt,
    );
    const order = [
      WallSide.south,
      WallSide.east,
      WallSide.north,
      WallSide.west,
    ];
    final wallPhotos = <WallSide, File>{};
    for (var i = 0; i < frames.length && i < order.length; i++) {
      wallPhotos[order[i]] = frames[i];
    }

    var result = await WallRelativeVision.scanWallByWall(
      wallPhotos: wallPhotos,
      roomWidthFt: size.widthFt,
      roomLengthFt: size.lengthFt,
      apiKey: key,
    );

    result = _filterScanByInventory(result, inventoryHint);
    // Seed missing MUST types as wall-anchored on first empty wall side
    result = _seedScanResultFromInventory(result, inventoryHint);

    return result.copyWith(
      warnings: [
        ...result.warnings,
        ...size.notes,
        'Photo order: [0]=south [1]=east [2]=north [3]=west',
        'Easy plan — Groq wall-by-wall (+29)',
      ],
    );
  }

  static int _easyQuality(ScanResult r, String inventoryHint) {
    var q = r.furniture.length * 12;
    final types = r.furniture.map((f) => f.type).toSet();
    if (types.contains(FurnitureType.wardrobe)) q += 30;
    if (types.contains(FurnitureType.table)) q += 30;
    if (inventoryHint.contains('MUST include WARDROBE') &&
        !types.contains(FurnitureType.wardrobe)) {
      q -= 40;
    }
    if (inventoryHint.contains('MUST include TABLE') &&
        !types.contains(FurnitureType.table)) {
      q -= 40;
    }
    if (inventoryHint.contains('NO BED') &&
        types.contains(FurnitureType.bed)) {
      q -= 35;
    }
    if (inventoryHint.contains('NO SOFA') &&
        types.contains(FurnitureType.sofa)) {
      q -= 35;
    }
    if (inventoryHint.contains('NO TV_UNIT') &&
        types.contains(FurnitureType.tvUnit)) {
      q -= 35;
    }
    final openings = r.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .length;
    q += openings.clamp(0, 4) * 5;
    if (r.furniture.isEmpty) q -= 50;
    return q;
  }

  static ScanResult _filterScanByInventory(
    ScanResult r,
    String inventoryHint,
  ) {
    if (inventoryHint.isEmpty) return r;
    final forbid = <FurnitureType>{};
    if (inventoryHint.contains('NO BED')) forbid.add(FurnitureType.bed);
    if (inventoryHint.contains('NO SOFA')) forbid.add(FurnitureType.sofa);
    if (inventoryHint.contains('NO TV_UNIT')) forbid.add(FurnitureType.tvUnit);
    if (forbid.isEmpty) return r;
    final kept = r.furniture.where((f) => !forbid.contains(f.type)).toList();
    if (kept.length == r.furniture.length) return r;
    return r.copyWith(
      furniture: kept,
      warnings: [
        ...r.warnings,
        'Filtered ${r.furniture.length - kept.length} inventory-forbidden piece(s)',
      ],
    );
  }

  static ScanResult _seedScanResultFromInventory(
    ScanResult r,
    String inventoryHint,
  ) {
    if (inventoryHint.isEmpty) return r;
    final types = r.furniture.map((f) => f.type).toSet();
    final extra = <ScanFurnitureHint>[...r.furniture];
    final notes = <String>[...r.warnings];

    void seed(FurnitureType type, String mustToken, String wallName) {
      if (!inventoryHint.contains(mustToken)) return;
      if (types.contains(type)) return;
      // Approximate catalog sizes
      final dim = switch (type) {
        FurnitureType.wardrobe => (6.0, 2.0),
        FurnitureType.table => (4.0, 2.0),
        _ => (3.0, 2.0),
      };
      // Place via wall-relative compose fields in free XY near wall
      final w = r.roomWidthFt;
      final l = r.roomLengthFt;
      double x;
      double y;
      switch (wallName) {
        case 'west':
          x = dim.$2 / 2 + 0.3;
          y = l / 2;
        case 'east':
          x = w - dim.$2 / 2 - 0.3;
          y = l / 2;
        case 'north':
          x = w / 2;
          y = l - dim.$2 / 2 - 0.3;
        default:
          x = w / 2;
          y = dim.$2 / 2 + 0.3;
      }
      extra.add(ScanFurnitureHint(
        type: type,
        posFt: Offset(x, y),
        widthFt: dim.$1,
        lengthFt: dim.$2,
        rotationRad: 0,
      ));
      types.add(type);
      notes.add('Seeded ${type.name} from inventory on $wallName wall');
    }

    seed(FurnitureType.wardrobe, 'MUST include WARDROBE', 'west');
    seed(FurnitureType.table, 'MUST include TABLE', 'south');
    if (extra.length == r.furniture.length) return r;
    return ScanRefine.refine(AccurateScan.enforce(
      widthFt: r.roomWidthFt,
      lengthFt: r.roomLengthFt,
      openings: r.walls,
      furniture: extra,
      warnings: notes,
      sourceLabel: 'Easy plan — Groq wall-by-wall (+29) seeded',
      inventDefaultOpenings: false,
      accuracyScore: r.accuracyScore,
    ));
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// Public for HuggingFaceVisionScanner inventory gate.
  static String formatInventoryHintPublic(Map<String, dynamic> inv) =>
      _formatInventoryHint(inv);

  static Map<String, dynamic> applyInventoryGatePublic(
    Map<String, dynamic> layout,
    String inventoryHint,
  ) =>
      _applyInventoryGate(layout, inventoryHint);

  /// Public: gate + seed MUST furniture from inventory (used by HF path too).
  static ({Map<String, dynamic> map, int added}) applyInventoryCompletePublic(
    Map<String, dynamic> layout,
    String inventoryHint,
  ) {
    final gated = _applyInventoryGate(layout, inventoryHint);
    return _seedMissingFromInventory(gated, inventoryHint);
  }

  static String _formatInventoryHint(Map<String, dynamic> inv) {
    bool b(String k) {
      final v = inv[k];
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return false;
    }

    final parts = <String>[];
    if (b('hasWardrobe')) parts.add('MUST include WARDROBE');
    if (b('hasDeskOrTable')) parts.add('MUST include TABLE (desk)');
    if (b('hasChair')) parts.add('include CHAIR if seen');
    if (!b('hasBed')) parts.add('NO BED');
    if (!b('hasSofa')) parts.add('NO SOFA');
    if (!b('hasTvUnit')) parts.add('NO TV_UNIT');
    if (b('hasMeshOrSlidingGlass')) {
      parts.add('include balcony or large window for mesh/glass sliding');
    }
    final doors = inv['doorCount'];
    if (doors is num && doors > 0) {
      parts.add('about ${doors.toInt()} door opening(s)');
    }
    final notes = inv['notes']?.toString();
    if (notes != null && notes.isNotEmpty) parts.add('notes: $notes');
    return parts.isEmpty ? 'use photos only' : parts.join('; ');
  }

  static Map<String, dynamic> _applyInventoryGate(
    Map<String, dynamic> layout,
    String inventoryHint,
  ) {
    if (inventoryHint.isEmpty) return layout;
    final forbid = <String>{};
    if (inventoryHint.contains('NO BED')) forbid.add('BED');
    if (inventoryHint.contains('NO SOFA')) forbid.add('SOFA');
    if (inventoryHint.contains('NO TV_UNIT')) forbid.add('TV_UNIT');
    if (forbid.isEmpty) return layout;

    final raw = layout['furniture'];
    if (raw is! List) return layout;
    final kept = <dynamic>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final t = item['type']?.toString().toUpperCase() ?? '';
      if (forbid.any((f) => t.contains(f))) continue;
      kept.add(item);
    }
    final out = Map<String, dynamic>.from(layout);
    out['furniture'] = kept;
    return out;
  }

  /// If inventory required WARDROBE/TABLE but layout omitted them, place defaults.
  static ({Map<String, dynamic> map, int added}) _seedMissingFromInventory(
    Map<String, dynamic> layout,
    String inventoryHint,
  ) {
    if (inventoryHint.isEmpty) return (map: layout, added: 0);
    final raw = layout['furniture'];
    final list = <Map<String, dynamic>>[
      if (raw is List)
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
    ];
    String typesBlob() => list
        .map((m) => m['type']?.toString().toUpperCase() ?? '')
        .join(' ');

    var added = 0;
    void ensure({
      required String type,
      required bool must,
      required String wall,
      required double fromLeft,
      required double depth,
      required double w,
      required double l,
      required String evidence,
    }) {
      if (!must) return;
      final blob = typesBlob();
      if (blob.contains(type)) return;
      list.add({
        'type': type,
        'wall': wall,
        'fromLeft': fromLeft,
        'depth': depth,
        'dim': {'w': w, 'l': l},
        'confidence': 0.62,
        'evidence': evidence,
      });
      added++;
    }

    ensure(
      type: 'WARDROBE',
      must: inventoryHint.contains('MUST include WARDROBE'),
      wall: 'west',
      fromLeft: 0.5,
      depth: 1.2,
      w: 6.0,
      l: 2.0,
      evidence: 'seeded: inventory required WARDROBE',
    );
    ensure(
      type: 'TABLE',
      must: inventoryHint.contains('MUST include TABLE'),
      wall: 'south',
      fromLeft: 2.5,
      depth: 1.5,
      w: 4.0,
      l: 2.0,
      evidence: 'seeded: inventory required TABLE/desk',
    );

    // Opening seed for mesh/sliding glass
    if (inventoryHint.contains('mesh') || inventoryHint.contains('glass')) {
      final openings = <Map<String, dynamic>>[
        if (layout['openings'] is List)
          for (final o in layout['openings'] as List)
            if (o is Map) Map<String, dynamic>.from(o),
        if (layout['walls'] is List)
          for (final o in layout['walls'] as List)
            if (o is Map &&
                !['wall', 'WALL'].contains(o['type']?.toString()))
              Map<String, dynamic>.from(o),
      ];
      final hasBalconyOrWide = openings.any((o) {
        final t = o['type']?.toString().toLowerCase() ?? '';
        return t.contains('balcony') || t.contains('window') || t.contains('door');
      });
      if (!hasBalconyOrWide) {
        openings.add({
          'type': 'balcony',
          'wall': 'east',
          'fromLeft': 1.0,
          'width': 5.0,
          'confidence': 0.55,
          'evidence': 'seeded: inventory mesh/sliding glass',
        });
        added++;
      }
      final outOpen = Map<String, dynamic>.from(layout);
      outOpen['furniture'] = list;
      outOpen['openings'] = openings;
      return (map: outOpen, added: added);
    }

    final out = Map<String, dynamic>.from(layout);
    out['furniture'] = list;
    return (map: out, added: added);
  }

  /// Two-pass: (1) openings / wall features (2) furniture placement.
  Future<ScanResult> _precisionScan({
    required String key,
    required List<File> frames,
    required double roomWidthFt,
    required double roomLengthFt,
    required int frameCount,
  }) async {
    final warnings = <String>[
      'Precision scan: $frameCount frame(s) · multi-pass interior mapping',
      'Room size locked to your ${roomWidthFt.toStringAsFixed(1)} × '
          '${roomLengthFt.toStringAsFixed(1)} ft measurements',
    ];

    Map<String, dynamic> archJson = {};
    try {
      archJson = await _client.completeJson(
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
      furnJson = await _client.completeJson(
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
      'walls': archJson['walls'] ?? furnJson['walls'] ?? [],
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

    warnings.add(
      'Scan accuracy estimate: ${(accuracy * 100).round()}% '
      '(more walkaround frames improve openings/furniture placement)',
    );
    if (parsed.furniture.isEmpty) {
      warnings.add(
        'No furniture detected — try Hugging Face fallback or add from catalog',
      );
    }

    final raw = AccurateScan.enforce(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: warnings,
      sourceLabel: 'Precision multi-frame scan (Groq) — size locked',
      inventDefaultOpenings: false,
      accuracyScore: accuracy,
    );
    return ScanRefine.refine(raw);
  }

  Future<ScanResult> _singlePassScan({
    required String key,
    required List<File> frames,
    required double roomWidthFt,
    required double roomLengthFt,
  }) async {
    final jsonMap = await _client.completeJson(
      apiKey: key,
      frames: frames,
      prompt: VisionLayoutPrompts.furniture(roomWidthFt, roomLengthFt),
      system: VisionLayoutPrompts.furnitureSystem,
    );
    jsonMap['roomWidth'] = roomWidthFt;
    jsonMap['roomLength'] = roomLengthFt;
    final filtered = _filterFurnitureMap(jsonMap);
    final parsed = ScanParser.parse(filtered.map);
    return ScanRefine.refine(AccurateScan.enforce(
      widthFt: roomWidthFt,
      lengthFt: roomLengthFt,
      openings: parsed.walls,
      furniture: parsed.furniture,
      warnings: parsed.warnings,
      sourceLabel: 'Free AI scan — size locked',
      inventDefaultOpenings: false,
    ));
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

  static double _estimateAccuracy({
    required int frames,
    required int furnitureCount,
    required int openingsCount,
    required int dropped,
    bool autoScale = false,
    double scaleConfidence = 0.5,
  }) {
    // Heuristic for UI — not CAD / LiDAR. Empty furniture cannot score high.
    var score = autoScale ? 0.35 : 0.42;
    score += (frames.clamp(1, 8) / 8) * 0.20;
    if (openingsCount > 0) score += 0.10;
    if (furnitureCount > 0) {
      score += 0.12;
      score += (furnitureCount.clamp(1, 6) / 6) * 0.12;
    } else {
      // Cap when no furniture — feedback showed 78% with 0 pieces.
      score = score.clamp(0.0, 0.48);
    }
    if (dropped == 0 && furnitureCount > 0) score += 0.05;
    if (frames >= 4) score += 0.04;
    if (autoScale) {
      score += (scaleConfidence - 0.4).clamp(0.0, 0.15);
      return score.clamp(0.28, furnitureCount == 0 ? 0.50 : 0.82);
    }
    return score.clamp(0.30, furnitureCount == 0 ? 0.52 : 0.92);
  }
}
