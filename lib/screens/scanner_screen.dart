import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/units.dart';
import '../providers/room_provider.dart';
import '../services/ai_scanner_service.dart';
import 'blueprint_screen.dart';
import 'scan_review_screen.dart';
import 'settings_screen.dart';

/// Guided multi-photo capture → AI scan → review.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  static const _maxPhotos = 4;

  final List<File> _images = [];
  final Map<File, String?> _validationResults = {};
  final Map<File, double> _wallMeasurements = {};

  final ImagePicker _picker = ImagePicker();
  final AIScannerService _aiService = AIScannerService();

  bool _isLoading = false;
  bool _askMeasurements = true;
  int _guideStep = 0;

  static const _guideTips = [
    'Photo 1: Stand in a corner — show two walls meeting the floor.',
    'Photo 2: Opposite side of the room for full width/length.',
    'Photo 3 (optional): Include door or window openings.',
    'Photo 4 (optional): Capture large furniture for detection.',
  ];

  Future<void> _ensureApiKey() async {
    final key = await AIScannerService.loadApiKey();
    if (key != null && key.isNotEmpty) return;
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API key needed'),
        content: const Text(
          'AI scan requires a Gemini API key. Add it in Settings, or draw the room manually.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Draw manually'),
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
    } else if (go == null) {
      ref.invalidate(roomProvider);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const BlueprintScreen()),
      );
    }
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

      if (_askMeasurements) {
        await _promptForMeasurement(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    }
  }

  Future<void> _promptForMeasurement(File file) async {
    final unit = ref.read(roomProvider).unitSystem;
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Optional wall length'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'If you know the length of the main wall in this photo, enter it (${unit.label}). Improves scale.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Length (${unit.label})',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) {
                final feet = LengthFormat.displayToFeet(val, unit);
                setState(() => _wallMeasurements[file] = feet);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _processImages() async {
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one room photo')),
      );
      return;
    }

    await _ensureApiKey();
    final key = await AIScannerService.loadApiKey();
    if (key == null || key.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final result = await _aiService.scanRoom(
        _images,
        wallMeasurements: _wallMeasurements.isEmpty ? null : _wallMeasurements,
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
      _wallMeasurements.remove(file);
      _guideStep = _images.isEmpty
          ? 0
          : (_images.length - 1).clamp(0, _guideTips.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tip = _guideTips[_guideStep.clamp(0, _guideTips.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan room'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Building top-down layout…'),
                  SizedBox(height: 8),
                  Text(
                    'This may take 15–40 seconds',
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
                SwitchListTile(
                  title: const Text('Ask for wall lengths'),
                  subtitle: const Text('Improves scale accuracy'),
                  value: _askMeasurements,
                  onChanged: (v) => setState(() => _askMeasurements = v),
                  dense: true,
                ),
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
                                'Take or pick 1–$_maxPhotos photos of your room',
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
                            final hasMeasurement =
                                _wallMeasurements.containsKey(file);
                            final unit = ref.watch(roomProvider).unitSystem;

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
                                  if (hasMeasurement)
                                    Positioned(
                                      left: 8,
                                      bottom: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.85),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          LengthFormat.formatFeet(
                                            _wallMeasurements[file]!,
                                            unit,
                                          ),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (validationError != null)
                                    Positioned(
                                      left: 8,
                                      right: 8,
                                      bottom: hasMeasurement ? 32 : 8,
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
                          child: Text(
                            _images.isEmpty
                                ? 'Add photos to continue'
                                : 'Generate top-down plan',
                          ),
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
