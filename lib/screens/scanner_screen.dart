import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/ai_scanner_service.dart';
import '../services/storage_service.dart';
import '../providers/room_provider.dart';
import '../models/furniture_item.dart';
import 'blueprint_screen.dart';

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final List<File> _images = [];
  final Map<File, String?> _validationResults = {};
  final Map<File, double> _wallMeasurements = {};
  
  final ImagePicker _picker = ImagePicker();
  final AIScannerService _aiService = AIScannerService();
  
  bool _isLoading = false;
  bool _isGuidedMode = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        final file = File(pickedFile.path);
        setState(() {
          _images.add(file);
        });

        // Trigger AI validation in background
        _aiService.validateImage(file).then((reason) {
          if (mounted) {
            setState(() {
              _validationResults[file] = reason;
            });
          }
        });

        if (_isGuidedMode) {
          _promptForMeasurement(file);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _promptForMeasurement(File file) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Wall Measurement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the length of the wall captured in this photo (in feet):'),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Length (ft)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) {
                setState(() => _wallMeasurements[file] = val);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add images.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _aiService.scanRoom(_images, wallMeasurements: _wallMeasurements);
      
      if (result != null) {
        final pxf = ref.read(roomProvider).pixelsPerFoot;
        final roomWidth = (result['roomWidth'] as num?)?.toDouble() ?? 20.0;
        final roomLength = (result['roomLength'] as num?)?.toDouble() ?? 20.0;
        
        final strokes = _aiService.convertToStrokes(result, pxf);
        final rawFurniture = _aiService.parseFurniture(result);
        
        final List<FurnitureItem> furnitureItems = [];
        for (var f in rawFurniture) {
          try {
            final type = FurnitureType.values.firstWhere(
              (e) => e.name.toUpperCase() == (f['type'] as String).toUpperCase(),
              orElse: () => FurnitureType.bed,
            );
            furnitureItems.add(FurnitureItem(
              id: UniqueKey().toString(),
              type: type,
              position: Offset(f['pos']['x'].toDouble() * pxf, f['pos']['y'].toDouble() * pxf),
              widthInFeet: f['dim']['w'].toDouble(),
              lengthInFeet: f['dim']['l'].toDouble(),
            ));
          } catch (_) {}
        }
        
        ref.read(roomProvider.notifier).initFromScan(roomWidth, roomLength, strokes, furnitureItems);
        
        // Ensure manual save immediately after generation
        await StorageService().saveRoom(ref.read(roomProvider).room);

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const BlueprintScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Scan Error'),
            content: Text(e.toString()),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Room Scanner'),
        actions: [
          Row(
            children: [
              const Text('Guided', style: TextStyle(fontSize: 12)),
              Switch(
                value: _isGuidedMode,
                onChanged: (v) => setState(() => _isGuidedMode = v),
              ),
            ],
          )
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Analysing room layout & objects...'),
                ],
              ),
            )
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb, color: Colors.blue.shade800),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Tip: Toggle "Guided" mode to enter wall lengths for higher accuracy.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _images.isEmpty
                      ? const Center(child: Text('No images added yet'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(8),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _images.length,
                          itemBuilder: (ctx, index) {
                            final file = _images[index];
                            final validationError = _validationResults[file];
                            final hasMeasurement = _wallMeasurements.containsKey(file);

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                children: [
                                  Image.file(file, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                                  // Validation Badge
                                  Positioned(
                                    left: 8,
                                    top: 8,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: validationError == null ? Colors.green.withValues(alpha: 0.8) : Colors.orange.withValues(alpha: 0.9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        validationError == null ? Icons.check : Icons.warning_amber,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  // Measurement Badge
                                  if (hasMeasurement)
                                    Positioned(
                                      left: 8,
                                      bottom: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.8),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '${_wallMeasurements[file]}ft',
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: IconButton(
                                      icon: const Icon(Icons.cancel, color: Colors.white),
                                      onPressed: () => setState(() => _images.removeAt(index)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _processImages,
                      child: Text(_isLoading ? 'Processing...' : 'Generate AI Blueprint'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
