import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../catalog/furniture_catalog.dart';
import '../config/app_config.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/scan_keyframes.dart';
import '../domain/units.dart';
import '../domain/wall_relative_scan.dart';
import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import '../providers/room_provider.dart';
import '../services/ai_scanner_service.dart';
import '../services/analytics_service.dart';
import '../services/free_vision_scanner.dart';
import '../services/wall_relative_vision.dart';
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
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final AIScannerService _aiService = AIScannerService();

  final _widthController = TextEditingController(text: '12');
  final _lengthController = TextEditingController(text: '14');

  /// field_measure (default) | wall_walk | free_frames | offline_only | gemini
  String _scanMode = 'field_measure';

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
    _refreshVisionStatus();
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
    if (_freeFrames.length >= 8) return;
    final f = camera ? await _capturePhoto() : await _galleryPhoto();
    if (f == null || !mounted) return;
    setState(() => _freeFrames.add(f));
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

  Future<void> _process() async {
    final size = _parseRoomSize();
    if (size == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter exact room width × length first')),
      );
      return;
    }

    if (_scanMode == 'field_measure') {
      // No photo required — tape numbers are truth
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
        const SnackBar(content: Text('Add photos or a walkthrough video')),
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
            'No free vision key — only an empty measured rectangle will be created. '
            'Add Groq in Settings, or use Field measure with tape numbers.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Settings'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Frame only'),
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

    setState(() {
      _isLoading = true;
      _loadingDetail = switch (_scanMode) {
        'field_measure' => 'Building plan from tape measurements…',
        'wall_walk' => 'Analyzing each wall (designer method)…',
        _ => 'Running multi-frame scan…',
      };
    });

    final mode = _scanMode;
    await AnalyticsService.instance.scanStart(mode: mode);

    try {
      late final ScanResult result;
      if (mode == 'field_measure') {
        result = _composeFieldMeasure(size.$1, size.$2);
      } else if (mode == 'wall_walk') {
        if (_freeVisionReady == true) {
          result = await WallRelativeVision.scanWallByWall(
            wallPhotos: Map<WallSide, File>.from(_wallPhotos),
            roomWidthFt: size.$1,
            roomLengthFt: size.$2,
            overviewPhotos: List<File>.from(_overviewPhotos),
          );
        } else {
          result = await _aiService.scanRoomAccurateFree(
            _wallPhotos.values.toList(),
            roomWidthFt: size.$1,
            roomLengthFt: size.$2,
            tryVision: false,
            layoutType: RoomLayoutType.empty,
          );
        }
      } else if (mode == 'offline_only') {
        result = await _aiService.scanRoomAccurateFree(
          _freeFrames.isEmpty ? _wallPhotos.values.toList() : _freeFrames,
          layoutType: _layoutType,
          roomWidthFt: size.$1,
          roomLengthFt: size.$2,
          tryVision: false,
        );
      } else if (mode == 'gemini') {
        result = await _aiService.scanRoom(
          _freeFrames,
          preferGemini: true,
          roomWidthFt: size.$1,
          roomLengthFt: size.$2,
        );
      } else {
        result = await _aiService.scanRoomAccurateFree(
          _freeFrames,
          layoutType: RoomLayoutType.empty,
          roomWidthFt: size.$1,
          roomLengthFt: size.$2,
          tryVision: true,
        );
      }

      final included = result.furniture.where((f) => f.included).length;
      await AnalyticsService.instance.scanSuccess(
        mode: mode,
        furnitureCount: included,
        emptyFurniture: included == 0,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ScanReviewScreen(initial: result)),
      );
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
                Card(
                  color: Colors.teal.shade50,
                  child: const ListTile(
                    leading: Icon(Icons.straighten),
                    title: Text('Precision truth: tape + walls'),
                    subtitle: Text(
                      'Competitors (magicplan, RoomPlan, Houzz Pro) use AR/LiDAR '
                      'or laser meters — photos alone cannot measure feet accurately. '
                      'Best Flutter path: measure room + each opening from the left '
                      'corner while facing the wall (how designers field-measure). '
                      'Photos are optional AI assist — always verify numbers.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _widthController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Width (${unit.label})',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          helperText: 'Wall A / C length',
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
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Length (${unit.label})',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          helperText: 'Wall B / D length',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Scan method',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    helperText: _freeVisionReady == true
                        ? 'Vision ready for assist'
                        : 'Vision offline — field measure still works',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _scanMode,
                      items: const [
                        DropdownMenuItem(
                          value: 'field_measure',
                          child: Text('Field measure — tape (most accurate)'),
                        ),
                        DropdownMenuItem(
                          value: 'wall_walk',
                          child: Text('Wall photos + AI (assistive)'),
                        ),
                        DropdownMenuItem(
                          value: 'free_frames',
                          child: Text('Free photos / video (lowest accuracy)'),
                        ),
                        DropdownMenuItem(
                          value: 'offline_only',
                          child: Text('Offline rectangle only'),
                        ),
                        DropdownMenuItem(
                          value: 'gemini',
                          child: Text('Gemini (optional key)'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _scanMode = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_scanMode == 'field_measure') ...[
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
                ] else if (_scanMode == 'free_frames' || _scanMode == 'gemini') ...[
                  Text(
                    'Photos / video (${_freeFrames.length}/8)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lowest accuracy: AI guesses top-down layout from photos. Prefer Field measure.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonalIcon(
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
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _freeFrames.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _freeFrames[i],
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
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
