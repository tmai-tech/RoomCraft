import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/units.dart';
import '../providers/room_provider.dart';
import '../services/ai_scanner_service.dart';
import '../services/free_vision_scanner.dart';
import 'blueprint_screen.dart';
import 'scan_review_screen.dart';
import 'settings_screen.dart';

/// Guided multi-photo capture → free accurate plan (no user API key required).
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  static const _maxPhotos = 4;

  final List<File> _images = [];
  final Map<File, String?> _validationResults = {};

  final ImagePicker _picker = ImagePicker();
  final AIScannerService _aiService = AIScannerService();

  final _widthController = TextEditingController(text: '10');
  final _lengthController = TextEditingController(text: '10');

  bool _isLoading = false;
  /// free (default, no key) | offline_only | gemini
  String _scanMode = 'free';
  RoomLayoutType _layoutType = RoomLayoutType.empty;
  int _guideStep = 0;
  bool? _freeVisionReady;

  static const _guideTips = [
    'Photo 1: Stand in a corner — show two walls meeting the floor.',
    'Photo 2: Opposite side of the room for full width/length.',
    'Photo 3 (optional): Include door or window openings.',
    'Photo 4 (optional): Capture large furniture for free AI detection.',
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
        const SnackBar(content: Text('Maximum 4 photos')),
      );
      return;
    }
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (pickedFile == null) return;
      final file = File(pickedFile.path);
      setState(() {
        _images.add(file);
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

    setState(() => _isLoading = true);
    try {
      final result = _scanMode == 'offline_only'
          ? await _aiService.scanRoomAccurateFree(
              _images,
              layoutType: _layoutType,
              roomWidthFt: size.$1,
              roomLengthFt: size.$2,
              tryVision: false,
            )
          : _scanMode == 'gemini'
              ? await _aiService.scanRoom(
                  _images,
                  preferGemini: true,
                  roomWidthFt: size.$1,
                  roomLengthFt: size.$2,
                )
              : await _aiService.scanRoomAccurateFree(
                  // Free accurate — no user key required
                  _images,
                  layoutType: RoomLayoutType.empty,
                  roomWidthFt: size.$1,
                  roomLengthFt: size.$2,
                  tryVision: true,
                );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScanReviewScreen(initial: result),
        ),
      );
    } catch (e) {
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
    switch (_scanMode) {
      case 'gemini':
        return 'Gemini analyzing…';
      case 'offline_only':
        return 'Building exact-size plan…';
      default:
        return 'Free accurate scan…';
    }
  }

  String get _generateLabel {
    if (_images.isEmpty) return 'Add photos to continue';
    switch (_scanMode) {
      case 'gemini':
        return 'Generate with Gemini';
      case 'offline_only':
        return 'Generate exact plan (offline)';
      default:
        return 'Generate free accurate plan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tip = _guideTips[_guideStep.clamp(0, _guideTips.length - 1)];
    final unit = ref.watch(roomProvider).unitSystem;
    final visionHint = _freeVisionReady == true
        ? 'Furniture assist available (no key paste needed)'
        : 'Exact room size always — furniture from catalog if vision offline';

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
                  const Text(
                    'Room size stays exact — never warped by the photo',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
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
                    '10 × 10 stays 10 × 10 — free scan needs no API key',
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
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _images.length >= _maxPhotos
                              ? null
                              : () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
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
