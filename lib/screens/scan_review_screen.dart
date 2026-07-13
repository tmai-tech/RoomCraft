import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/furniture_catalog.dart';
import '../domain/scan_parser.dart';
import '../domain/units.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import '../providers/room_provider.dart';
import '../services/analytics_service.dart';
import '../services/storage_service.dart';
import 'blueprint_screen.dart';

/// Review AI plan: toggle furniture, calibrate scale, open editor.
class ScanReviewScreen extends ConsumerStatefulWidget {
  final ScanResult initial;

  const ScanReviewScreen({super.key, required this.initial});

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  late ScanResult _result;
  int? _calibrateWallIndex;
  final _scaleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _result = widget.initial;
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _openEditor() async {
    final pxf = ref.read(roomProvider).pixelsPerFoot;
    final converted = ScanParser.toEditor(_result, pxf);
    ref.read(roomProvider.notifier).initFromScan(
          converted.width,
          converted.length,
          converted.strokes,
          converted.furniture,
        );
    await StorageService().saveRoom(ref.read(roomProvider).room);
    await AnalyticsService.instance.openEditorFromScan();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const BlueprintScreen()),
    );
  }

  void _applyCalibration() {
    final idx = _calibrateWallIndex;
    if (idx == null) return;
    final unit = ref.read(roomProvider).unitSystem;
    final display = double.tryParse(_scaleController.text);
    if (display == null || display <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid wall length')),
      );
      return;
    }
    final feet = LengthFormat.displayToFeet(display, unit);
    setState(() {
      _result = ScanParser.applyScaleCalibration(
        _result,
        wallIndex: idx,
        targetLengthFt: feet,
      );
      _calibrateWallIndex = null;
      _scaleController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(roomProvider).unitSystem;
    final includedCount =
        _result.furniture.where((f) => f.included).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review scan'),
      ),
      body: Column(
        children: [
          MaterialBanner(
            content: Text(
              _result.warnings.isNotEmpty
                  ? _result.warnings.take(3).join(' · ')
                  : 'Measured layout sketch — walls form a rectangle from your '
                      'width × length (not LiDAR). Edit freely in the next step.',
              style: const TextStyle(fontSize: 12),
            ),
            leading: const Icon(Icons.info_outline),
            actions: [
              TextButton(
                onPressed: () =>
                    ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text('OK'),
              ),
            ],
          ),
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.grey.shade200,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: CustomPaint(
                painter: _ScanPreviewPainter(result: _result),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Room ${LengthFormat.formatFeet(_result.roomWidthFt, unit)}'
                    ' × ${LengthFormat.formatFeet(_result.roomLengthFt, unit)}'
                    ' · ${_result.walls.length} walls · $includedCount furniture',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 2,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text('Scale calibration', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Pick a wall you know the real length of, enter it, then Apply.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Reference wall',
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      hint: const Text('Select a wall'),
                      value: _calibrateWallIndex,
                      items: [
                        for (var i = 0; i < _result.walls.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              'Wall ${i + 1} (${_result.walls[i].type.name}) · '
                              '${LengthFormat.formatFeet(_result.walls[i].lengthFt, unit)}',
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _calibrateWallIndex = v),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _scaleController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: 'Actual length (${unit.label})',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _calibrateWallIndex == null ? null : _applyCalibration,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Furniture', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                if (_result.furniture.isEmpty)
                  Card(
                    color: Colors.amber.shade50,
                    child: const ListTile(
                      leading: Icon(Icons.chair_outlined),
                      title: Text('No furniture on this plan'),
                      subtitle: Text(
                        'Room size is still exact. Free vision may be offline '
                        'on this build, or the photo had no clear pieces. '
                        'Add items from the catalog after you open the editor.',
                      ),
                    ),
                  )
                else
                  ...List.generate(_result.furniture.length, (i) {
                    final f = _result.furniture[i];
                    final entry = FurnitureCatalog.entryFor(f.type);
                    return CheckboxListTile(
                      dense: true,
                      value: f.included,
                      secondary: Icon(entry.icon),
                      title: Text(entry.label),
                      subtitle: Text(
                        '${LengthFormat.formatFeet(f.widthFt, unit)} × '
                        '${LengthFormat.formatFeet(f.lengthFt, unit)}',
                      ),
                      onChanged: (v) {
                        setState(() {
                          final list = List<ScanFurnitureHint>.from(_result.furniture);
                          list[i] = f.copyWith(included: v ?? true);
                          _result = _result.copyWith(furniture: list);
                        });
                      },
                    );
                  }),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _openEditor,
                    icon: const Icon(Icons.edit),
                    label: const Text('Open in editor'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to photos'),
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

class _ScanPreviewPainter extends CustomPainter {
  final ScanResult result;

  _ScanPreviewPainter({required this.result});

  @override
  void paint(Canvas canvas, Size size) {
    if (result.roomWidthFt <= 0 || result.roomLengthFt <= 0) return;

    const pad = 24.0;
    final scale = ((size.width - pad * 2) / result.roomWidthFt)
        .clamp(0.0, (size.height - pad * 2) / result.roomLengthFt);

    canvas.translate(pad, pad);

    // Room fill
    final roomRect = Rect.fromLTWH(
      0,
      0,
      result.roomWidthFt * scale,
      result.roomLengthFt * scale,
    );
    canvas.drawRect(
      roomRect,
      Paint()..color = Colors.white,
    );
    canvas.drawRect(
      roomRect,
      Paint()
        ..color = Colors.blueGrey.shade200
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (final w in result.walls) {
      final p1 = Offset(w.startFt.dx * scale, w.startFt.dy * scale);
      final p2 = Offset(w.endFt.dx * scale, w.endFt.dy * scale);
      final paint = Paint()
        ..strokeWidth = w.type == StrokeType.wall ? 4 : 2.5
        ..strokeCap = StrokeCap.round
        ..color = switch (w.type) {
          StrokeType.wall => Colors.black87,
          StrokeType.door => Colors.orange,
          StrokeType.window => Colors.blue,
          StrokeType.balcony => Colors.green,
        };
      canvas.drawLine(p1, p2, paint);
    }

    for (final f in result.furniture.where((e) => e.included)) {
      final cx = f.posFt.dx * scale;
      final cy = f.posFt.dy * scale;
      final rw = f.widthFt * scale;
      final rh = f.lengthFt * scale;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(f.rotationRad);
      final rect = Rect.fromCenter(center: Offset.zero, width: rw, height: rh);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = Colors.teal.shade100,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..color = Colors.teal.shade700
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ScanPreviewPainter oldDelegate) =>
      oldDelegate.result != result;
}
