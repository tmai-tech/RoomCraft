import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/scan_keyframes.dart';
import '../domain/units.dart';
import '../providers/room_provider.dart';
import '../services/ai_scanner_service.dart';
import '../services/analytics_service.dart';
import '../services/free_vision_scanner.dart';
import 'blueprint_screen.dart';
import 'scan_review_screen.dart';
import 'settings_screen.dart';

/// Guided multi-photo / video walkthrough → precision free plan.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  static const _maxPhotos = 8;

  final List<File> _images = [];
  final Map<File, String?> _validationResults = {};

  final ImagePicker _picker = ImagePicker();
  final AIScannerService _aiService = AIScannerService();

  final _widthController = TextEditingController(text: '10');
  final _lengthController = TextEditingController(text: '10');

  bool _isLoading = false;
  String _loadingDetail = '';
  /// free (default, no key) | offline_only | gemini
  String _scanMode = 'free';
  RoomLayoutType _layoutType = RoomLayoutType.empty;
  int _guideStep = 0;
  bool? _freeVisionReady;
  bool _fromVideo = false;

  static const _guideTips = [
    'Best: Record a slow 360° video at eye level (10–30s), or add 4–8 photos.',
    'Corner shots: show two walls meeting the floor + any door/window on that wall.',
    'Openings: stand square to each door and window so edges are clear.',
    'Furniture: include full footprint (legs/base) — avoid only partial views.',
    'Details: film moulding, niches, built-ins if you want them on the plan.',
    'Lighting: walk slowly; pause at each wall — blurry frames are dropped.',
    'Measure first: enter exact width × length — that stays the plan size.',
    'Review: uncheck wrong items; edit openings in the blueprint after.',
  ];

  @override
  void initState() {
    super.initState();
    _refreshVisionStatus();
  }

  Future<void> _refreshVisionStatus() async {
    final ready = await FreeVisionScanner.isAvailable() ||
        AppConfig.hasBundledFreeVision ||
        ((await AIScannerService.resolveGeminiApiKey())?.isNotEmpty ?? false);
    if (mounted) setState(() => _freeVisionReady = ready);
  }

  @override
  void dispose() {
    _widthController.dispose();
    _lengthController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_images.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum $_maxPhotos photos / frames')),
      );
      return;
    }
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (pickedFile == null) return;
      final file = File(pickedFile.path);
      setState(() {
        _images.add(file);
        _fromVideo = false;
        _guideStep = (_images.length).clamp(0, _guideTips.length - 1);
      });

      _aiService.validateImage(file).then((reason) {
        if (mounted) setState(() => _validationResults[file] = reason);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    }
  }

  /// Record or pick a walkthrough video → extract diverse keyframes.
  Future<void> _pickVideo({required bool fromCamera}) async {
    try {
      setState(() {
        _isLoading = true;
        _loadingDetail = 'Opening video…';
      });
      final picked = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(seconds: 90),
      );
      if (picked == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      if (!mounted) return;
      setState(() => _loadingDetail = 'Extracting keyframes from walkthrough…');

      final video = File(picked.path);
      final frames = await ScanKeyframes.fromVideo(
        video,
        maxFrames: _maxPhotos,
        intervalMs: 1000,
      );
      final best = await ScanKeyframes.pickSharpest(frames, maxKeep: _maxPhotos);

      if (!mounted) return;
      setState(() {
        _images
          ..clear()
          ..addAll(best);
        _validationResults.clear();
        _fromVideo = true;
        _guideStep = 0;
        _isLoading = false;
        _loadingDetail = '';
      });
      for (final f in best) {
        _aiService.validateImage(f).then((reason) {
          if (mounted) setState(() => _validationResults[f] = reason);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Extracted ${best.length} clear frames from video — ready to scan',
            ),
          ),
        );
      }
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

  Future<void> _processImages() async {
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one room photo')),
      );
      return;
    }

    final size = _parseRoomSize();
    if (size == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter room width and length (e.g. 10 × 10)'),
        ),
      );
      return;
    }

    // Gemini optional path only — free path never asks for a key.
    if (_scanMode == 'gemini') {
      final key = await AIScannerService.resolveGeminiApiKey();
      if (key == null || key.isEmpty) {
        if (!mounted) return;
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gemini key not set'),
            content: const Text(
              'Free accurate scan works without any key.\n\n'
              'Gemini is optional. Use Free accurate scan, or add a key in Settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Use free scan'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Settings'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (go == true) {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
          await _refreshVisionStatus();
          final again = await AIScannerService.resolveGeminiApiKey();
          if (again == null || again.isEmpty) {
            setState(() => _scanMode = 'free');
          }
        } else {
          setState(() => _scanMode = 'free');
        }
      }
    }

    // Free accurate path: warn if furniture vision is offline (would get frame only).
    if (_scanMode == 'free' && _freeVisionReady != true) {
      if (!mounted) return;
      final cont = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Furniture detection offline'),
          content: const Text(
            'This build has no free vision key, so scan will only draw the room '
            'frame (exact size). To place furniture from photos:\n\n'
            '• Add a free Groq key in Settings (console.groq.com), or\n'
            '• Ask maintainers to set ROOMCRAFT_GROQ_API_KEY on CI builds.\n\n'
            'You can still scan the frame and add pieces from the catalog.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Open Settings'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Scan room frame only'),
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
      _loadingDetail = _fromVideo || _images.length >= 3
          ? 'Precision multi-pass scan (architecture + furniture)…'
          : 'Analyzing room frames…';
    });
    final mode = _scanMode;
    await AnalyticsService.instance.scanStart(
      mode: _fromVideo ? '${mode}_video' : mode,
    );
    try {
      final result = mode == 'offline_only'
          ? await _aiService.scanRoomAccurateFree(
              _images,
              layoutType: _layoutType,
              roomWidthFt: size.$1,
              roomLengthFt: size.$2,
              tryVision: false,
            )
          : mode == 'gemini'
              ? await _aiService.scanRoom(
                  _images,
                  preferGemini: true,
                  roomWidthFt: size.$1,
                  roomLengthFt: size.$2,
                )
              : await _aiService.scanRoomAccurateFree(
                  _images,
                  layoutType: RoomLayoutType.empty,
                  roomWidthFt: size.$1,
                  roomLengthFt: size.$2,
                  tryVision: true,
                );
      final included = result.furniture.where((f) => f.included).length;
      await AnalyticsService.instance.scanSuccess(
        mode: mode,
        furnitureCount: included,
        emptyFurniture: included == 0,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScanReviewScreen(initial: result),
        ),
      );
    } catch (e) {
      await AnalyticsService.instance.scanFail(
        mode: mode,
        reason: e.toString(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Scan failed'),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _removeImage(int index) {
    final file = _images[index];
    setState(() {
      _images.removeAt(index);
      _validationResults.remove(file);
      _guideStep = _images.isEmpty
          ? 0
          : (_images.length - 1).clamp(0, _guideTips.length - 1);
    });
  }

  String get _loadingLabel {
    if (_loadingDetail.isNotEmpty) return _loadingDetail;
    switch (_scanMode) {
      case 'gemini':
        return 'Gemini analyzing…';
      case 'offline_only':
        return 'Building exact-size plan…';
      default:
        return 'Precision room scan…';
    }
  }

  String get _generateLabel {
    if (_images.isEmpty) return 'Add photos or record a walkthrough';
    switch (_scanMode) {
      case 'gemini':
        return 'Generate with Gemini';
      case 'offline_only':
        return 'Generate exact plan (offline)';
      default:
        return _fromVideo || _images.length >= 3
            ? 'Run precision scan (${_images.length} frames)'
            : 'Generate free accurate plan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tip = _guideTips[_guideStep.clamp(0, _guideTips.length - 1)];
    final unit = ref.watch(roomProvider).unitSystem;
    final visionHint = _freeVisionReady == true
        ? (_fromVideo
            ? 'Video walkthrough · multi-pass precision scan ready'
            : 'Photos or video · multi-pass maps openings + furniture')
        : 'No free vision key — room frame only (add Groq in Settings or CI)';

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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(_loadingLabel),
                  const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Multi-pass: architecture (doors/windows) then furniture. '
                      'Room size stays exact — never warped by the photo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step ${_images.isEmpty ? 1 : (_images.length + 1).clamp(1, _maxPhotos)} of $_maxPhotos',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(tip, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _images.length / _maxPhotos,
                        backgroundColor: Colors.blue.shade100,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Width (${unit.label})',
                            helperText: 'Exact room width',
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
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Length (${unit.label})',
                            helperText: 'Exact room length',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Enter exact size first (source of truth). Prefer a slow video walkthrough '
                    'or 4–8 photos of every wall for best accuracy. Not LiDAR — interior layout sketch.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Scan mode',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      helperText: visionHint,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _scanMode,
                        items: const [
                          DropdownMenuItem(
                            value: 'free',
                            child: Text('Free accurate (recommended, no key)'),
                          ),
                          DropdownMenuItem(
                            value: 'offline_only',
                            child: Text('Offline only (exact size, empty)'),
                          ),
                          DropdownMenuItem(
                            value: 'gemini',
                            child: Text('Gemini AI (optional key)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _scanMode = v);
                        },
                      ),
                    ),
                  ),
                ),
                if (_scanMode == 'offline_only') ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Furniture (offline only)',
                        isDense: true,
                        border: OutlineInputBorder(),
                        helperText:
                            'Empty = no fake bed/sofa. Presets are optional.',
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<RoomLayoutType>(
                          isExpanded: true,
                          value: _layoutType,
                          items: [
                            for (final t in [
                              RoomLayoutType.empty,
                              RoomLayoutType.bedroom,
                              RoomLayoutType.living,
                              RoomLayoutType.office,
                            ])
                              DropdownMenuItem(
                                value: t,
                                child: Text(AutoArrange.label(t)),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _layoutType = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: _images.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.photo_camera_back_outlined,
                                  size: 72, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text('No photos yet'),
                              const SizedBox(height: 8),
                              Text(
                                'Set width × length, then add 1–$_maxPhotos photos',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _images.length,
                          itemBuilder: (ctx, index) {
                            final file = _images[index];
                            final validationError = _validationResults[file];

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(file, fit: BoxFit.cover),
                                  Positioned(
                                    left: 8,
                                    top: 8,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: validationError == null
                                            ? Colors.green.withValues(alpha: 0.85)
                                            : Colors.orange.withValues(alpha: 0.9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        validationError == null
                                            ? Icons.check
                                            : Icons.warning_amber,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (validationError != null)
                                    Positioned(
                                      left: 8,
                                      right: 8,
                                      bottom: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        color: Colors.black54,
                                        child: Text(
                                          validationError,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: IconButton(
                                      icon: const Icon(Icons.cancel,
                                          color: Colors.white),
                                      onPressed: () => _removeImage(index),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _pickVideo(fromCamera: true),
                              icon: const Icon(Icons.videocam),
                              label: const Text('Record video'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _pickVideo(fromCamera: false),
                              icon: const Icon(Icons.video_library),
                              label: const Text('Video file'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _images.length >= _maxPhotos
                                  ? null
                                  : () => _pickImage(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Photo'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _images.length >= _maxPhotos
                                  ? null
                                  : () => _pickImage(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Gallery'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _images.isEmpty ? null : _processImages,
                          child: Text(_generateLabel),
                        ),
                        TextButton(
                          onPressed: () {
                            ref.invalidate(roomProvider);
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const BlueprintScreen(),
                              ),
                            );
                          },
                          child: const Text('Skip — draw manually'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
