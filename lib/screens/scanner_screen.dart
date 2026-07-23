import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../catalog/furniture_catalog.dart';
import '../config/app_config.dart';
import '../domain/accurate_scan.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/photo_true_layout.dart';
import '../domain/plan_accuracy_metrics.dart';
import '../domain/scan_keyframes.dart';
import '../domain/scan_refine.dart';
import '../domain/units.dart';
import '../domain/wall_relative_scan.dart';
import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import '../providers/room_provider.dart';
import '../services/ai_scanner_service.dart';
import '../services/analytics_service.dart';
import '../services/ar_measure_service.dart';
import '../services/free_vision_scanner.dart';
import '../services/wall_relative_vision.dart';
import 'ar_place_layout_screen.dart';
import 'blueprint_screen.dart';
import 'scan_review_screen.dart';
import 'settings_screen.dart';

/// Editable opening row for field measure (tape from left while facing wall).
class _OpeningDraft {
  StrokeType type;
  final TextEditingController fromLeft;
  final TextEditingController width;

  _OpeningDraft({
    this.type = StrokeType.door,
    String fromLeftText = '2',
    String widthText = '3',
  })  : fromLeft = TextEditingController(text: fromLeftText),
        width = TextEditingController(text: widthText);

  void dispose() {
    fromLeft.dispose();
    width.dispose();
  }
}

class _FurnDraft {
  FurnitureType type;
  WallSide wall;
  final TextEditingController fromLeft;
  final TextEditingController depth;
  final TextEditingController w;
  final TextEditingController l;

  _FurnDraft({
    this.type = FurnitureType.sofa,
    this.wall = WallSide.south,
    String fromLeftText = '5',
    String depthText = '3',
    String wText = '7',
    String lText = '3',
  })  : fromLeft = TextEditingController(text: fromLeftText),
        depth = TextEditingController(text: depthText),
        w = TextEditingController(text: wText),
        l = TextEditingController(text: lText);

  void dispose() {
    fromLeft.dispose();
    depth.dispose();
    w.dispose();
    l.dispose();
  }
}

/// Guided field-measure (designer tape) + wall photos + free multi-frame scan.
class ScannerScreen extends ConsumerStatefulWidget {
  /// When set (e.g. `ar_guided`), opens that mode instead of easy photo scan.
  final String? initialScanMode;
  /// Expand advanced/AR options on open (used by AR Room Planner entry).
  final bool openAdvanced;

  const ScannerScreen({
    super.key,
    this.initialScanMode,
    this.openAdvanced = false,
  });

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final AIScannerService _aiService = AIScannerService();

  final _widthController = TextEditingController(text: '12');
  final _lengthController = TextEditingController(text: '14');

  /// Primary path is always simple photo/video scan.
  /// Advanced modes live under "More options".
  late String _scanMode;

  /// When false (default), size is estimated from photos.
  bool _knowRoomSize = false;

  /// Show AR / tape / advanced modes (hidden by default — user feedback).
  late bool _showAdvanced;

  ArAvailability? _arStatus;
  ArRoomMeasure? _arMeasure;
  /// AR mode: quick (W×L) or chain (4 walls).
  /// +123: default multi-dot polygon (4 floor corners). Toggle for legacy chain.
  bool _arChainMode = false;
  bool _arPolygonMode = true;

  final Map<WallSide, File> _wallPhotos = {};
  final Map<WallSide, List<_OpeningDraft>> _wallOpenings = {
    for (final s in WallSide.values) s: <_OpeningDraft>[],
  };
  final List<_FurnDraft> _furnitureDrafts = [];
  final List<File> _overviewPhotos = [];
  final List<File> _freeFrames = [];

  bool _isLoading = false;
  String _loadingDetail = '';
  bool? _freeVisionReady;
  final RoomLayoutType _layoutType = RoomLayoutType.empty;

  @override
  void initState() {
    super.initState();
    _scanMode = widget.initialScanMode ?? 'easy_scan';
    _showAdvanced = widget.openAdvanced || widget.initialScanMode == 'ar_guided';
    if (_scanMode == 'ar_guided') {
      // Ensure AR status is probed immediately for AR Room Planner entry.
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshArStatus());
    }
    _refreshVisionStatus();
    _refreshArStatus();
  }

  Future<void> _refreshArStatus() async {
    try {
      final s = await ArMeasureService.isAvailable();
      if (!mounted) return;
      setState(() => _arStatus = s);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _arStatus = ArAvailability(
          supported: false,
          installNeeded: false,
          message: 'AR unavailable ($e)',
        );
      });
    }
  }


  String get _arMeasureMode {
    if (_arPolygonMode) return 'polygon';
    if (_arChainMode) return 'chain';
    return 'quick';
  }

  Future<void> _runArMeasure() async {
    setState(() {
      _isLoading = true;
      _loadingDetail = switch (_arMeasureMode) {
        'polygon' => 'AR multi-dot map… mark 4 floor corners',
        'chain' => 'AR 4-wall chain… walk each wall',
        _ => 'Starting AR quick measure…',
      };
    });
    try {
      final m = await ArMeasureService.measureRoom(mode: _arMeasureMode);
      if (!mounted) return;
      setState(() {
        _arMeasure = m;
        _widthController.text = m.widthFt.toStringAsFixed(1);
        _lengthController.text = m.lengthFt.toStringAsFixed(1);
        _knowRoomSize = true;
        _isLoading = false;
        _loadingDetail = '';
      });
      final warn = m.oppositeWallError > 0.08
          ? ' Opposite walls differ — room may not be rectangular.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${m.summaryLabel}.$warn Add photos for furniture (optional)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadingDetail = '';
      });
      final msg = e.toString().replaceFirst('PlatformException', '');
      if (!msg.contains('CANCELLED') && !msg.contains('cancelled')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AR measure: $msg')),
        );
      }
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _lengthController.dispose();
    for (final list in _wallOpenings.values) {
      for (final o in list) {
        o.dispose();
      }
    }
    for (final f in _furnitureDrafts) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshVisionStatus() async {
    final ready = await FreeVisionScanner.isAvailable() ||
        AppConfig.hasBundledFreeVision ||
        ((await AIScannerService.resolveGeminiApiKey())?.isNotEmpty ?? false);
    if (mounted) setState(() => _freeVisionReady = ready);
  }

  (double, double)? _parseRoomSize() {
    final unit = ref.read(roomProvider).unitSystem;
    final wDisp = double.tryParse(_widthController.text.trim());
    final lDisp = double.tryParse(_lengthController.text.trim());
    if (wDisp == null || lDisp == null || wDisp <= 0 || lDisp <= 0) {
      return null;
    }
    return (
      LengthFormat.displayToFeet(wDisp, unit),
      LengthFormat.displayToFeet(lDisp, unit),
    );
  }

  double _toFeet(String raw) {
    final unit = ref.read(roomProvider).unitSystem;
    final v = double.tryParse(raw.trim()) ?? 0;
    return LengthFormat.displayToFeet(v, unit);
  }

  Future<File?> _capturePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 92,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<File?> _galleryPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 92,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<void> _setWallPhoto(WallSide side, {required bool camera}) async {
    final f = camera ? await _capturePhoto() : await _galleryPhoto();
    if (f == null || !mounted) return;
    setState(() => _wallPhotos[side] = f);
  }

  Future<void> _addOverview({required bool camera}) async {
    if (_overviewPhotos.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max 3 overview photos')),
      );
      return;
    }
    final f = camera ? await _capturePhoto() : await _galleryPhoto();
    if (f == null || !mounted) return;
    setState(() => _overviewPhotos.add(f));
  }

  Future<void> _addFreeFrame({required bool camera}) async {
    if (_freeFrames.length >= 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Max 8 photos — remove some to add more')),
        );
      }
      return;
    }
    final f = camera ? await _capturePhoto() : await _galleryPhoto();
    if (f == null || !mounted) return;
    setState(() => _freeFrames.add(f));
  }

  /// Multi-select from gallery — primary consumer path for room photos.
  Future<void> _addGalleryMultiPhotos() async {
    final room = 8 - _freeFrames.length;
    if (room <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Max 8 photos — remove some to add more')),
        );
      }
      return;
    }
    try {
      final picked = await _picker.pickMultiImage(
        // Keep more detail for wall furniture (+31)
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
        limit: room,
      );
      if (picked.isEmpty || !mounted) return;
      final files = picked.take(room).map((x) => File(x.path)).toList();
      setState(() => _freeFrames.addAll(files));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${files.length} photo${files.length == 1 ? '' : 's'} '
              '(${_freeFrames.length}/8). Cover every wall for best results.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery pick failed: $e')),
        );
      }
    }
  }

  Future<void> _addVideoToFreeFrames({required bool fromCamera}) async {
    try {
      setState(() {
        _isLoading = true;
        _loadingDetail = 'Extracting keyframes…';
      });
      final picked = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(seconds: 90),
      );
      if (picked == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final frames = await ScanKeyframes.fromVideo(File(picked.path), maxFrames: 8);
      final best = await ScanKeyframes.pickSharpest(frames, maxKeep: 8);
      if (!mounted) return;
      setState(() {
        _freeFrames
          ..clear()
          ..addAll(best);
        _isLoading = false;
        _loadingDetail = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingDetail = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video failed: $e')),
        );
      }
    }
  }

  /// Vision fills drafts for one wall — user keeps/edits tape numbers.
  Future<void> _visionAssistWall(WallSide side) async {
    final size = _parseRoomSize();
    if (size == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter room size first')),
      );
      return;
    }
    final photo = _wallPhotos[side];
    if (photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture ${side.shortLabel} photo first')),
      );
      return;
    }
    if (_freeVisionReady != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vision offline — enter tape numbers manually')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingDetail = 'AI assist on ${side.shortLabel} (suggestions only)…';
    });
    try {
      final unit = ref.read(roomProvider).unitSystem;
      final r = await WallRelativeVision.analyzeWall(
        image: photo,
        wall: side,
        roomWidthFt: size.$1,
        roomLengthFt: size.$2,
      );
      final wallLen = side.lengthFt(size.$1, size.$2);
      if (!mounted) return;

      // Clear previous drafts for this wall and replace with suggestions
      for (final o in _wallOpenings[side]!) {
        o.dispose();
      }
      final newOpenings = <_OpeningDraft>[];
      for (final o in r.openings) {
        final fromL = o.fromLeftFt(wallLen);
        final w = o.widthAlongWallFt(wallLen);
        newOpenings.add(_OpeningDraft(
          type: o.type,
          fromLeftText: LengthFormat.feetToDisplay(fromL, unit).toStringAsFixed(1),
          widthText: LengthFormat.feetToDisplay(w, unit).toStringAsFixed(1),
        ));
      }
      for (final f in r.furniture) {
        final fromL = f.t * wallLen;
        final cat = FurnitureCatalog.entryFor(f.type);
        _furnitureDrafts.add(_FurnDraft(
          type: f.type,
          wall: side,
          fromLeftText: LengthFormat.feetToDisplay(fromL, unit).toStringAsFixed(1),
          depthText: LengthFormat.feetToDisplay(f.depthFt, unit).toStringAsFixed(1),
          wText: LengthFormat.feetToDisplay(f.widthFt > 0 ? f.widthFt : cat.defaultWidthFt, unit)
              .toStringAsFixed(1),
          lText: LengthFormat.feetToDisplay(f.lengthFt > 0 ? f.lengthFt : cat.defaultLengthFt, unit)
              .toStringAsFixed(1),
        ));
      }
      setState(() {
        _wallOpenings[side] = newOpenings;
        _isLoading = false;
        _loadingDetail = '';
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${side.shortLabel}: ${newOpenings.length} opening(s), '
            '${r.furniture.length} furniture suggestion(s). '
            'Verify with tape — AI is approximate.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingDetail = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assist failed: $e')),
        );
      }
    }
  }

  ScanResult _composeFieldMeasure(double wFt, double lFt) {
    final openings = <WallOpeningHint>[];
    for (final side in WallSide.values) {
      final wallLen = side.lengthFt(wFt, lFt);
      for (final draft in _wallOpenings[side]!) {
        final fromL = _toFeet(draft.fromLeft.text);
        final width = _toFeet(draft.width.text);
        if (width <= 0) continue;
        openings.add(WallOpeningHint.fromLeft(
          wall: side,
          type: draft.type,
          fromLeftFt: fromL,
          widthFt: width,
          wallLengthFt: wallLen,
          confidence: 1.0,
          evidence: 'user tape',
        ));
      }
    }

    final furniture = <WallFurnitureHint>[];
    for (final d in _furnitureDrafts) {
      final wallLen = d.wall.lengthFt(wFt, lFt);
      furniture.add(WallFurnitureHint.fromLeft(
        type: d.type,
        wall: d.wall,
        fromLeftFt: _toFeet(d.fromLeft.text),
        depthFt: _toFeet(d.depth.text),
        widthFt: _toFeet(d.w.text),
        lengthFt: _toFeet(d.l.text),
        wallLengthFt: wallLen,
        confidence: 1.0,
        evidence: 'user measure',
      ));
    }

    return WallRelativeComposer.compose(
      widthFt: wFt,
      lengthFt: lFt,
      openings: openings,
      furniture: furniture,
      warnings: const [
        'Positions from your tape measurements (left corner while facing each wall).',
        'This is how interior designers field-measure — more accurate than photo-only AI.',
      ],
      fromTapeMeasure: true,
    );
  }

  /// Assign each of 3–4 photos to a wall (south/east/north/west).
  /// Returns null if the user cancels.
  Future<Map<WallSide, File>?> _promptWallAssignments(List<File> frames) async {
    const order = [
      WallSide.south,
      WallSide.east,
      WallSide.north,
      WallSide.west,
    ];
    // Default: walk order by index
    final assign = <int, WallSide>{
      for (var i = 0; i < frames.length && i < order.length; i++) i: order[i],
    };

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Label each wall photo',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Match photos to walls as you stand inside the room. '
                    'Defaults assume walk order: near → right → far → left.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: ListView.separated(
                      itemCount: frames.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final side = assign[i] ?? order[i % 4];
                        return Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                frames[i],
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Photo ${i + 1}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  DropdownButtonFormField<WallSide>(
                                    value: side,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                    ),
                                    items: [
                                      for (final s in order)
                                        DropdownMenuItem(
                                          value: s,
                                          child: Text(
                                            '${s.name[0].toUpperCase()}${s.name.substring(1)} wall'
                                            '${s == WallSide.south ? " (near)" : s == WallSide.north ? " (far)" : s == WallSide.east ? " (right)" : " (left)"}',
                                          ),
                                        ),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setLocal(() => assign[i] = v);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          final used = assign.values.toSet();
                          if (used.length < frames.length) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Each photo needs a different wall',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Continue'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // +42: Cancel / dismiss → still scan with default walk order (near→right→far→left)
    final map = <WallSide, File>{};
    for (final e in assign.entries) {
      if (e.key < frames.length) map[e.value] = frames[e.key];
    }
    if (map.length < 3) {
      // rebuild pure index order
      map.clear();
      for (var i = 0; i < frames.length && i < order.length; i++) {
        map[order[i]] = frames[i];
      }
    }
    if (ok != true) {
      // User dismissed — keep defaults so scan is not aborted
      return map.length >= 3 ? map : null;
    }
    if (map.length < 3) return null;
    return map;
  }

  Future<void> _process() async {
    final needsExactSize =
        _scanMode == 'ar_guided' ||
        _scanMode == 'field_measure' ||
        _scanMode == 'wall_walk' ||
        _scanMode == 'offline_only' ||
        (_scanMode == 'easy_scan' && _knowRoomSize) ||
        (_scanMode == 'free_frames' && _knowRoomSize) ||
        (_scanMode == 'gemini' && _knowRoomSize);

    final size = _parseRoomSize();
    if (_scanMode == 'ar_guided' && _arMeasure == null && size == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap “Measure with AR” first')),
      );
      return;
    }
    if (needsExactSize && size == null && _arMeasure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter room width × length first')),
      );
      return;
    }

    if (_scanMode == 'field_measure') {
      // No photo required — tape numbers are truth
    } else if (_scanMode == 'ar_guided') {
      // Size from AR; photos optional for furniture
    } else if (_scanMode == 'wall_walk') {
      if (_wallPhotos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Capture at least Wall A (and ideally all 4 walls)'),
          ),
        );
        return;
      }
    } else if (_scanMode != 'offline_only' && _freeFrames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Record a walkthrough video or add room photos'),
        ),
      );
      return;
    }

    if (_scanMode != 'offline_only' &&
        _scanMode != 'field_measure' &&
        _freeVisionReady != true) {
      if (!mounted) return;
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vision offline'),
          content: const Text(
            'AI room mapping needs a free vision key on this build. '
            'Add Groq in Settings, or use Field measure if you have a tape.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Settings'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue offline'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (cont == false) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        await _refreshVisionStatus();
        return;
      }
      if (cont != true) return;
    }

    final resolvedSize = size ??
        (_arMeasure != null
            ? (_arMeasure!.widthFt, _arMeasure!.lengthFt)
            : null);

    setState(() {
      _isLoading = true;
      _loadingDetail = switch (_scanMode) {
        'ar_guided' => 'Building plan from AR measurements…',
        'easy_scan' => 'Mapping your room from photos/video…',
        'field_measure' => 'Building plan from tape measurements…',
        'wall_walk' => 'Analyzing each wall (designer method)…',
        _ => 'Running multi-frame scan…',
      };
    });

    final mode = _scanMode;
    // +31: for 3–4 easy-scan photos, confirm wall labels before vision.
    Map<WallSide, File>? easyWallMap;
    if ((mode == 'easy_scan' || mode == 'free_frames') &&
        _freeFrames.length >= 3 &&
        _freeFrames.length <= 4) {
      easyWallMap = await _promptWallAssignments(_freeFrames);
      // +42: null only if fewer than 3 frames; cancel uses default wall order
      if (easyWallMap == null && _freeFrames.length >= 3) {
        const order = [
          WallSide.south,
          WallSide.east,
          WallSide.north,
          WallSide.west,
        ];
        easyWallMap = {
          for (var i = 0; i < _freeFrames.length && i < order.length; i++)
            order[i]: _freeFrames[i],
        };
      }
    }

    await AnalyticsService.instance.scanStart(mode: mode);

    try {
      late ScanResult result;
      if (mode == 'ar_guided') {
        final w = resolvedSize!.$1;
        final l = resolvedSize.$2;
        final frames = _freeFrames;
        if (frames.isNotEmpty && _freeVisionReady == true) {
          final raw = await _aiService.scanRoomAccurateFree(
            frames,
            roomWidthFt: w,
            roomLengthFt: l,
            tryVision: true,
            autoScale: false,
            layoutType: RoomLayoutType.empty,
          );
          final poly = _arMeasure?.isPolygon == true;
          final chain = _arMeasure?.isChain == true;
          final oppErr = _arMeasure?.oppositeWallError ?? 0;
          final src = poly
              ? ScaleSource.arPolygon
              : chain
                  ? ScaleSource.arChain
                  : ScaleSource.arQuick;
          result = ScanRefine.refine(raw.copyWith(
            warnings: [
              ...raw.warnings,
              poly
                  ? 'Room size from AR 4-corner multi-dot map '
                      '(${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft)'
                  : 'Room size from ARCore floor measure '
                      '(${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft)',
              'Scale lock (+108/+123): ${ScaleLockConfidence.sourceLabel(src)}',
            ],
            accuracyScore: ScaleLockConfidence.blend(
              layoutScore: raw.accuracyScore ?? 0.72,
              source: src,
              oppositeWallError: oppErr,
            ),
          ));
        } else {
          // AR size only — exact rectangle; add furniture from catalog or photos later
          final poly = _arMeasure?.isPolygon == true;
          final chain = _arMeasure?.isChain == true;
          final oppErr = _arMeasure?.oppositeWallError ?? 0;
          final src = poly
              ? ScaleSource.arPolygon
              : chain
                  ? ScaleSource.arChain
                  : ScaleSource.arQuick;
          final floor = ScaleLockConfidence.sourceFloor(
            src,
            oppositeWallError: oppErr,
          );
          // +119/+123: pure AR-measured empty room = 100% metric geometry when tight
          final arScore = ScaleLockConfidence.blend(
            layoutScore: 1.0,
            source: src,
            oppositeWallError: oppErr,
          );
          result = AccurateScan.enforce(
            widthFt: w,
            lengthFt: l,
            openings: const [],
            furniture: const [],
            warnings: [
              if (poly)
                'Room size from AR 4-corner multi-dot map '
                    '(${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft)'
              else if (chain)
                'Room size from AR 4-wall chain '
                    '(${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft, opposite walls averaged)'
              else
                'Room size from ARCore floor measure '
                    '(${w.toStringAsFixed(1)} × ${l.toStringAsFixed(1)} ft)',
              if (oppErr > 0.08)
                'Opposite edges differ by ${(oppErr * 100).round()}% — edit in Review if needed',
              if (frames.isEmpty)
                'No photos yet — add openings/furniture in Review or Place furniture in AR',
              'Scale lock (+108/+119/+123): ${ScaleLockConfidence.sourceLabel(src)} '
                  'floor ${(floor * 100).round()}%',
              if (arScore >= 0.99)
                '100% AR measured room geometry (+123 multi-dot)',
            ],
            sourceLabel: poly
                ? 'ARCore 4-corner multi-dot map'
                : chain
                    ? 'ARCore 4-wall chain'
                    : 'ARCore guided measure',
            inventDefaultOpenings: false,
            accuracyScore: arScore,
          );
        }
      } else if (mode == 'field_measure') {
        result = ScanRefine.refine(
          _composeFieldMeasure(resolvedSize!.$1, resolvedSize.$2),
        );
      } else if (mode == 'wall_walk') {
        if (_freeVisionReady == true) {
          result = await WallRelativeVision.scanWallByWall(
            wallPhotos: Map<WallSide, File>.from(_wallPhotos),
            roomWidthFt: resolvedSize!.$1,
            roomLengthFt: resolvedSize.$2,
            overviewPhotos: List<File>.from(_overviewPhotos),
          );
        } else {
          result = await _aiService.scanRoomAccurateFree(
            _wallPhotos.values.toList(),
            roomWidthFt: resolvedSize!.$1,
            roomLengthFt: resolvedSize.$2,
            tryVision: false,
            layoutType: RoomLayoutType.empty,
          );
        }
      } else if (mode == 'offline_only') {
        result = await _aiService.scanRoomAccurateFree(
          _freeFrames.isEmpty ? _wallPhotos.values.toList() : _freeFrames,
          layoutType: _layoutType,
          roomWidthFt: resolvedSize!.$1,
          roomLengthFt: resolvedSize.$2,
          tryVision: false,
        );
      } else if (mode == 'gemini') {
        result = await _aiService.scanRoom(
          _freeFrames,
          preferGemini: true,
          roomWidthFt: resolvedSize?.$1,
          roomLengthFt: resolvedSize?.$2,
        );
      } else if (mode == 'easy_scan') {
        result = await _aiService.scanRoomAccurateFree(
          _freeFrames,
          layoutType: RoomLayoutType.empty,
          roomWidthFt: _knowRoomSize ? resolvedSize?.$1 : null,
          roomLengthFt: _knowRoomSize ? resolvedSize?.$2 : null,
          tryVision: true,
          autoScale: !_knowRoomSize,
          wallPhotoMap: easyWallMap,
        );
      } else {
        result = await _aiService.scanRoomAccurateFree(
          _freeFrames,
          layoutType: RoomLayoutType.empty,
          roomWidthFt: resolvedSize?.$1,
          roomLengthFt: resolvedSize?.$2,
          tryVision: true,
          autoScale: resolvedSize == null,
          wallPhotoMap: easyWallMap,
        );
      }

      final included = result.furniture.where((f) => f.included).length;
      await AnalyticsService.instance.scanSuccess(
        mode: mode,
        furnitureCount: included,
        emptyFurniture: included == 0,
      );
      if (!mounted) return;
      // +119: AR path MUST keep the measured plan. Previously we discarded
      // ScanResult and only opened empty ArPlaceLayoutScreen — that broke
      // metric accuracy (openings/furniture/AR scale notes never reached Review).
      // Primary: Review with AR-locked plan. Secondary button already offers
      // "Place furniture at AR size" after measure.
      if (mode == 'ar_guided' && _arMeasure != null) {
        final arPlan = PhotoTrueLayout.resolveForReview(result);
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('AR room ready'),
            content: Text(
              'Room locked at ${_arMeasure!.widthFt.toStringAsFixed(1)} × '
              '${_arMeasure!.lengthFt.toStringAsFixed(1)} ft from AR.\n\n'
              '• Review plan — edit doors/windows, then open 2D/3D editor\n'
              '• Place furniture — catalogue / live AR camera at real size',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'place'),
                child: const Text('Place furniture'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'review'),
                child: const Text('Review plan'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (choice == 'place') {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArPlaceLayoutScreen(
                measure: _arMeasure!,
                roomName: 'AR Room',
              ),
            ),
          );
        } else {
          // Default / review — preserve AR-measured plan
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ScanReviewScreen(initial: arPlan),
            ),
          );
        }
      } else {
        await Navigator.of(context).push(
          // +116: resolve before Review so first paint is door-clear / gold
          MaterialPageRoute(
            builder: (_) => ScanReviewScreen(
              initial: PhotoTrueLayout.resolveForReview(result),
            ),
          ),
        );
      }
    } catch (e) {
      await AnalyticsService.instance.scanFail(mode: mode, reason: e.toString());
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Scan failed'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref.invalidate(roomProvider);
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const BlueprintScreen()),
                );
              },
              child: const Text('Draw manually'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingDetail = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(roomProvider).unitSystem;
    final wallsDone = _wallPhotos.length;
    final size = _parseRoomSize();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan room'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              await _refreshVisionStatus();
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      _loadingDetail.isEmpty ? 'Scanning…' : _loadingDetail,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // —— Simple primary path (feedback: too many options) ——
                if (_scanMode == 'easy_scan' && !_showAdvanced) ...[
                  Text(
                    'Scan room',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add photos of every wall (or a short walkaround video). '
                    'Then tap Generate plan.\n\n'
                    'Best accuracy (4 walls): multi-select photos in walk order — '
                    '1 near/south wall, 2 right/east, 3 far/north, 4 left/west. '
                    'Use full-resolution photos, not screenshots.',
                    style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _addGalleryMultiPhotos,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery photos'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _addFreeFrame(camera: true),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _addVideoToFreeFrames(fromCamera: true),
                          icon: const Icon(Icons.videocam),
                          label: const Text('Video'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        _addVideoToFreeFrames(fromCamera: false),
                    child: const Text('Or pick a video from gallery'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _freeFrames.isEmpty
                        ? 'No photos yet'
                        : '${_freeFrames.length} photo(s) ready',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _freeFrames.isEmpty
                          ? Colors.grey
                          : Colors.teal.shade800,
                    ),
                  ),
                  if (_freeFrames.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _freeFrames.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                _freeFrames[i],
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _freeFrames.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _freeFrames.isEmpty ? null : _process,
                      child: const Text('Generate plan'),
                    ),
                  ),
                  if (_freeVisionReady != true)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'AI key not ready — set Groq in Settings, or continue offline.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade900),
                      ),
                    ),
                  TextButton(
                    onPressed: () {
                      ref.invalidate(roomProvider);
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const BlueprintScreen()),
                      );
                    },
                    child: const Text('Skip — draw manually'),
                  ),
                  const Divider(height: 32),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _showAdvanced = true;
                      if (_scanMode == 'easy_scan') _scanMode = 'ar_guided';
                    }),
                    icon: const Icon(Icons.tune),
                    label: const Text('More options (AR, tape measure…)'),
                  ),
                ] else ...[
                // —— Advanced modes (hidden by default) ——
                if (_showAdvanced)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _showAdvanced = false;
                        _scanMode = 'easy_scan';
                      }),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to simple scan'),
                    ),
                  ),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Advanced scan mode',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: (_scanMode == 'easy_scan' ||
                              _scanMode == 'free_frames' ||
                              _scanMode == 'gemini')
                          ? 'ar_guided'
                          : _scanMode,
                      items: const [
                        DropdownMenuItem(
                          value: 'ar_guided',
                          child: Text('AR measure'),
                        ),
                        DropdownMenuItem(
                          value: 'field_measure',
                          child: Text('Field measure (tape)'),
                        ),
                        DropdownMenuItem(
                          value: 'wall_walk',
                          child: Text('Wall photos + AI'),
                        ),
                        DropdownMenuItem(
                          value: 'offline_only',
                          child: Text('Offline rectangle only'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _scanMode = v);
                      },
                    ),
                  ),
                ),
                if (_scanMode != 'easy_scan' && _scanMode != 'ar_guided' ||
                    (_scanMode == 'easy_scan' && _knowRoomSize) ||
                    (_scanMode == 'ar_guided' && _arMeasure != null)) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Width (${unit.label})',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            helperText: 'Wall A / C',
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('×', style: TextStyle(fontSize: 20)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _lengthController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Length (${unit.label})',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            helperText: 'Wall B / D',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                if (_scanMode == 'ar_guided') ...[
                  Card(
                    color: Colors.teal.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Gallery photos alone cannot measure real feet. '
                        'AR multi-dot map (4 floor corners) locks metric room size — '
                        'Planner 5D-style geometry when dots form a clean rectangle. '
                        'Then Review plan or place furniture on camera.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.teal.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '1. Measure the room with AR',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _arPolygonMode
                        ? 'Mark 4 floor corners (multi-dot map). Walk around the room; '
                            'point + at each corner → Mark. W×L is reconstructed from the polygon.'
                        : _arChainMode
                            ? 'Walk clockwise A→D. Point + at each wall end and Mark. '
                                'Opposite walls are averaged.'
                            : 'Point + at width corners (Mark twice), then length corners.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('4-corner multi-dot map (recommended)'),
                    subtitle: const Text(
                      'Planner5D-style: sparse floor corner cloud → room size',
                    ),
                    value: _arPolygonMode,
                    onChanged: (v) => setState(() {
                      _arPolygonMode = v;
                      if (v) _arChainMode = false;
                    }),
                  ),
                  if (!_arPolygonMode)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('4-wall chain'),
                      subtitle: const Text('Measure each wall segment A→D'),
                      value: _arChainMode,
                      onChanged: (v) => setState(() => _arChainMode = v),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: (_arStatus?.supported == true && !_isLoading)
                        ? _runArMeasure
                        : null,
                    icon: const Icon(Icons.view_in_ar),
                    label: Text(
                      _arMeasure == null
                          ? (_arPolygonMode
                              ? 'Map 4 floor corners with AR'
                              : _arChainMode
                                  ? 'Measure 4 walls with AR'
                                  : 'Measure with AR')
                          : 'Re-measure with AR',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  if (_arStatus != null && !_arStatus!.supported) ...[
                    const SizedBox(height: 8),
                    Text(
                      _arStatus!.message,
                      style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _scanMode = 'easy_scan'),
                      child: const Text('Switch to Easy photo/video'),
                    ),
                  ],
                  if (_arMeasure != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.teal.shade50,
                      child: ListTile(
                        leading: const Icon(Icons.check_circle, color: Colors.teal),
                        title: Text(_arMeasure!.summaryLabel),
                        subtitle: Text(
                          _arMeasure!.isChain
                              ? 'Walls: ${_arMeasure!.wallsFt.map((f) => f.toStringAsFixed(1)).join(" · ")} ft'
                              : 'From ARCore floor hit-testing',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      key: const Key('ar_place_layout_now'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArPlaceLayoutScreen(
                              measure: _arMeasure!,
                              roomName: 'AR Room',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.weekend),
                      label: const Text('Place furniture at AR size'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '2. Optional — photos for furniture',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Multi-select gallery photos or a walkaround video. '
                    'For 4 walls, pick in order: south → east → north → west '
                    '(full-res). Skip for an empty room plan.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _addGalleryMultiPhotos,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery (multi)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _addVideoToFreeFrames(fromCamera: true),
                        icon: const Icon(Icons.videocam),
                        label: const Text('Record video'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _addFreeFrame(camera: true),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Photo'),
                      ),
                    ],
                  ),
                  if (_freeFrames.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Frames: ${_freeFrames.length}/8',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _freeFrames.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(_freeFrames[i],
                                  width: 72, height: 72, fit: BoxFit.cover),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: InkWell(
                                onTap: () =>
                                    setState(() => _freeFrames.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ] else if (_scanMode == 'field_measure') ...[
                  Text(
                    'Step 2 — Openings on each wall (from LEFT corner facing wall)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stand facing the wall. Measure along the base: left corner → left edge of door/window → opening width. '
                    'Optional: photo + “AI suggest” then correct with tape.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  ...WallSide.values.map((s) => _buildFieldWallCard(s, unit, size)),
                  const SizedBox(height: 12),
                  Text(
                    'Step 3 — Furniture (optional)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Center of piece from left corner while facing its wall + depth into room. '
                    'Use catalog sizes when unsure.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_furnitureDrafts.length, _buildFurnCard),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _furnitureDrafts.add(_FurnDraft());
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add furniture against a wall'),
                  ),
                ] else if (_scanMode == 'wall_walk') ...[
                  Text(
                    'Step 2 — Photo each wall ($wallsDone/4)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stand facing the wall. Fill the frame with that wall + floor edge. '
                    'Walk clockwise: A → B → C → D. Expect to edit results in Review.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  ...WallSide.values.map(_buildWallPhotoCard),
                  const SizedBox(height: 12),
                  Text(
                    'Step 3 — Optional center overview',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 0; i < _overviewPhotos.length; i++)
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                _overviewPhotos[i],
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: InkWell(
                                onTap: () => setState(() => _overviewPhotos.removeAt(i)),
                                child: const CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Overview photo'),
                        onPressed: () => _addOverview(camera: true),
                      ),
                    ],
                  ),
                ] else ...[
                  const Text(
                    'Offline: creates an empty rectangle at your size. '
                    'Add doors/furniture in the editor.',
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _process,
                  child: Text(
                    switch (_scanMode) {
                      'ar_guided' => _arMeasure == null
                          ? 'Measure with AR first'
                          : 'Build plan from AR',
                      'field_measure' => 'Build plan from measurements',
                      'wall_walk' => 'Build plan from walls ($wallsDone/4)',
                      _ => 'Generate plan',
                    },
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.invalidate(roomProvider);
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const BlueprintScreen()),
                    );
                  },
                  child: const Text('Skip — draw manually'),
                ),
                ], // end advanced modes
              ],
            ),
    );
  }

  Widget _buildFieldWallCard(
    WallSide side,
    UnitSystem unit,
    (double, double)? size,
  ) {
    final wallLenFt = size != null ? side.lengthFt(size.$1, size.$2) : null;
    final photo = _wallPhotos[side];
    final openings = _wallOpenings[side]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: openings.isNotEmpty
                      ? Colors.teal.shade100
                      : Colors.grey.shade200,
                  child: Text(
                    side.shortLabel.replaceAll('Wall ', ''),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(side.shortLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (wallLenFt != null)
                        Text(
                          'Wall length ${LengthFormat.formatFeet(wallLenFt, unit)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(side.tip, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Row(
              children: [
                if (photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(photo, width: 48, height: 48, fit: BoxFit.cover),
                  ),
                if (photo != null) const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.camera_alt, size: 14),
                        label: Text(photo == null ? 'Photo' : 'Retake', style: const TextStyle(fontSize: 12)),
                        onPressed: () => _setWallPhoto(side, camera: true),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.auto_awesome, size: 14),
                        label: const Text('AI suggest', style: TextStyle(fontSize: 12)),
                        onPressed: () => _visionAssistWall(side),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(openings.length, (i) {
              final o = openings[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<StrokeType>(
                        value: o.type,
                        isDense: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Type',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: StrokeType.door, child: Text('Door')),
                          DropdownMenuItem(value: StrokeType.window, child: Text('Window')),
                          DropdownMenuItem(value: StrokeType.balcony, child: Text('Balcony')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => o.type = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: o.fromLeft,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'From L (${unit.label})',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: o.width,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'Width (${unit.label})',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        setState(() {
                          o.dispose();
                          openings.removeAt(i);
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  openings.add(_OpeningDraft(
                    type: StrokeType.door,
                    widthText: LengthFormat.feetToDisplay(3, unit).toStringAsFixed(1),
                  ));
                });
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add door / window / balcony'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFurnCard(int i) {
    final unit = ref.read(roomProvider).unitSystem;
    final d = _furnitureDrafts[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<FurnitureType>(
                    value: d.type,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Piece',
                      isDense: true,
                    ),
                    items: FurnitureType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(FurnitureCatalog.entryFor(t).label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final cat = FurnitureCatalog.entryFor(v);
                      setState(() {
                        d.type = v;
                        d.w.text = LengthFormat.feetToDisplay(cat.defaultWidthFt, unit)
                            .toStringAsFixed(1);
                        d.l.text = LengthFormat.feetToDisplay(cat.defaultLengthFt, unit)
                            .toStringAsFixed(1);
                        d.depth.text = LengthFormat.feetToDisplay(
                          cat.defaultLengthFt * 0.5,
                          unit,
                        ).toStringAsFixed(1);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<WallSide>(
                    value: d.wall,
                    isDense: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Against wall',
                      isDense: true,
                    ),
                    items: WallSide.values
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.shortLabel),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => d.wall = v);
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() {
                      d.dispose();
                      _furnitureDrafts.removeAt(i);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: d.fromLeft,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Center from L (${unit.label})',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: d.depth,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Depth (${unit.label})',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: d.w,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'W (${unit.label})',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: d.l,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'L (${unit.label})',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallPhotoCard(WallSide side) {
    final photo = _wallPhotos[side];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      photo != null ? Colors.teal.shade100 : Colors.grey.shade200,
                  child: Icon(
                    photo != null ? Icons.check : Icons.crop_square,
                    size: 16,
                    color: photo != null ? Colors.teal.shade800 : Colors.grey,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    side.shortLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(side.tip, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            Row(
              children: [
                if (photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(photo, width: 64, height: 64, fit: BoxFit.cover),
                  ),
                if (photo != null) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => _setWallPhoto(side, camera: true),
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: Text(photo == null ? 'Capture wall' : 'Retake'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _setWallPhoto(side, camera: false),
                        child: const Text('From gallery'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
