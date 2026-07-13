import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/scan_keyframes.dart';
import '../domain/units.dart';
import '../domain/wall_relative_scan.dart';
import '../models/scan_result.dart';
import '../providers/room_provider.dart';
import '../services/ai_scanner_service.dart';
import '../services/analytics_service.dart';
import '../services/free_vision_scanner.dart';
import '../services/wall_relative_vision.dart';
import 'blueprint_screen.dart';
import 'scan_review_screen.dart';
import 'settings_screen.dart';

/// Guided wall-by-wall scan (designer method) + optional free multi-frame scan.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  final AIScannerService _aiService = AIScannerService();

  final _widthController = TextEditingController(text: '10');
  final _lengthController = TextEditingController(text: '10');

  /// wall_walk (default, accurate) | free_frames | offline_only | gemini
  String _scanMode = 'wall_walk';

  final Map<WallSide, File> _wallPhotos = {};
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

  Future<void> _process() async {
    final size = _parseRoomSize();
    if (size == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter exact room width × length first')),
      );
      return;
    }

    if (_scanMode == 'wall_walk') {
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

    if (_scanMode != 'offline_only' && _freeVisionReady != true) {
      if (!mounted) return;
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vision offline'),
          content: const Text(
            'No free vision key — only an empty measured rectangle will be created. '
            'Add Groq in Settings or ensure CI bundles ROOMCRAFT_GROQ_API_KEY.',
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
      _loadingDetail = _scanMode == 'wall_walk'
          ? 'Analyzing each wall (designer method)…'
          : 'Running multi-frame scan…';
    });

    final mode = _scanMode;
    await AnalyticsService.instance.scanStart(mode: mode);

    try {
      late final ScanResult result;
      if (mode == 'wall_walk') {
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
        // free multi-frame fallback
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
                    const SizedBox(height: 8),
                    Text(
                      'Wall-relative mapping · size locked to your measurements',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
                    leading: Icon(Icons.architecture),
                    title: Text('Designer method (most accurate)'),
                    subtitle: Text(
                      'Competitors like magicplan use AR/LiDAR + guided corners. '
                      'Without LiDAR we use: exact measure → photo EACH wall → '
                      'place doors/furniture relative to that wall. '
                      'Not freeform single-photo guessing.',
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
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tape-measure these first — this is the scale of the plan.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Scan method',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    helperText: _freeVisionReady == true
                        ? 'Vision ready'
                        : 'Vision offline — frame only',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _scanMode,
                      items: const [
                        DropdownMenuItem(
                          value: 'wall_walk',
                          child: Text('Wall-by-wall (recommended)'),
                        ),
                        DropdownMenuItem(
                          value: 'free_frames',
                          child: Text('Free photos / video (fallback)'),
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
                if (_scanMode == 'wall_walk') ...[
                  Text(
                    'Step 2 — Photo each wall ($wallsDone/4)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stand facing the wall. Fill the frame with that wall + floor edge. '
                    'Walk clockwise: A → B → C → D.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 8),
                  ...WallSide.values.map(_buildWallCard),
                  const SizedBox(height: 12),
                  Text(
                    'Step 3 — Optional center overview (furniture in middle of room)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                                onTap: () => setState(
                                  () => _overviewPhotos.removeAt(i),
                                ),
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
                    _scanMode == 'wall_walk'
                        ? 'Build plan from walls ($wallsDone/4)'
                        : 'Generate plan',
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

  Widget _buildWallCard(WallSide side) {
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
                  backgroundColor: photo != null
                      ? Colors.teal.shade100
                      : Colors.grey.shade200,
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
            Text(
              side.tip,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      photo,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
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
