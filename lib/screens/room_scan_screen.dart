import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../domain/home_scan.dart';
import '../domain/photo_true_layout.dart';
import '../domain/scan_parser.dart';
import '../providers/room_provider.dart';
import '../services/ar_measure_service.dart';
import '../services/home_scan_service.dart';
import 'blueprint_screen.dart';

/// One button flow: scan room → plan with furniture. Nothing else (+129).
class RoomScanScreen extends ConsumerStatefulWidget {
  const RoomScanScreen({super.key});

  @override
  ConsumerState<RoomScanScreen> createState() => _RoomScanScreenState();
}

class _RoomScanScreenState extends ConsumerState<RoomScanScreen> {
  String _status = 'Starting…';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runScan());
  }

  Future<void> _runScan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Checking AR…';
    });

    if (!ArMeasureService.isPlatformSupported) {
      setState(() {
        _busy = false;
        _error = 'Needs an Android phone with Google AR.';
      });
      return;
    }

    try {
      final avail = await ArMeasureService.isAvailable();
      if (!avail.supported) {
        setState(() {
          _busy = false;
          _error = avail.message.isNotEmpty
              ? avail.message
              : 'AR not available on this device.';
        });
        return;
      }

      setState(() => _status = 'Walk the room, then tap Done');
      final measure = await ArMeasureService.measureRoom(mode: 'auto');
      if (!mounted) return;

      setState(() => _status = 'Creating your plan…');
      final pack = HomeScanPackage.fromMeasure(
        measure,
        appVersion: AppConfig.versionLabel,
      );
      try {
        await HomeScanService().save(pack);
      } catch (_) {}

      final plan = PhotoTrueLayout.resolveForReview(
        pack.toPlanWithAiFurniture(),
      );
      final pxf = AppConfig.defaultPixelsPerFoot;
      final converted = ScanParser.toEditor(plan, pxf);
      ref.read(roomProvider.notifier).initFromScan(
            converted.width,
            converted.length,
            converted.strokes,
            converted.furniture,
          );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const BlueprintScreen()),
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('CANCELLED') || msg.contains('cancelled')) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = msg
            .replaceFirst(RegExp(r'PlatformException:?\s*'), '')
            .trim();
        if (_error!.isEmpty) _error = 'Scan failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan the room'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error == null) ...[
                const Icon(Icons.view_in_ar, size: 72, color: Colors.teal),
                const SizedBox(height: 20),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Point at the floor and walk around the room. Tap Done when finished.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                if (_busy) ...[
                  const SizedBox(height: 28),
                  const CircularProgressIndicator(),
                ],
              ] else ...[
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade800),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _runScan,
                  child: const Text('Try again'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
