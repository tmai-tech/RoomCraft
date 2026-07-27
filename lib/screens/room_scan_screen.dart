import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../domain/home_scan.dart';
import '../domain/scan_parser.dart';
import '../providers/room_provider.dart';
import '../services/ar_measure_service.dart' show ArMeasureService, ArRoomMeasure;
import '../services/home_scan_service.dart';
import 'blueprint_screen.dart';

/// Scan the room → confirm size → plan with furniture.
///
/// +137: approach fix — AR walk only *proposes* size; user confirms/edits feet
/// before we invent a plan. Stops silent wrong 10×10 output (feedback 225fb5de).
class RoomScanScreen extends ConsumerStatefulWidget {
  const RoomScanScreen({super.key});

  @override
  ConsumerState<RoomScanScreen> createState() => _RoomScanScreenState();
}

class _RoomScanScreenState extends ConsumerState<RoomScanScreen> {
  String _status = 'Starting…';
  bool _busy = false;
  String? _error;

  /// After AR returns, we show size confirm (not auto-open a wrong plan).
  ArRoomMeasure? _measure;
  HomeScanPackage? _pack;
  late final TextEditingController _wCtrl;
  late final TextEditingController _lCtrl;

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController();
    _lCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runArWalk());
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _lCtrl.dispose();
    super.dispose();
  }

  Future<void> _runArWalk() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _measure = null;
      _pack = null;
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

      final pack = HomeScanPackage.fromMeasure(
        measure,
        appVersion: AppConfig.versionLabel,
      );
      try {
        await HomeScanService().save(pack);
      } catch (_) {}

      final size = pack.resolvedSize;
      // Prefer AR proposal, but never trust tiny half-walk without confirmation
      _wCtrl.text = size.widthFt.toStringAsFixed(1);
      _lCtrl.text = size.lengthFt.toStringAsFixed(1);

      setState(() {
        _busy = false;
        _measure = measure;
        _pack = pack;
        _status = 'Confirm room size';
      });
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

  Future<void> _createPlan() async {
    final w = double.tryParse(_wCtrl.text.trim());
    final l = double.tryParse(_lCtrl.text.trim());
    if (w == null || l == null || w < 6 || l < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter real size in feet (each side at least 6 ft).'),
        ),
      );
      return;
    }
    if (w > 40 || l > 40) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Size looks too large for one room — check units (feet), not inches/cm.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Creating plan with furniture…';
      _error = null;
    });

    try {
      final base = _measure ??
          ArRoomMeasure(
            widthFt: w,
            lengthFt: l,
            widthM: w / 3.28084,
            lengthM: l / 3.28084,
            mode: 'auto',
          );
      // Override with confirmed size (truth step) — source locks fuse (+138)
      final confirmed = ArRoomMeasure(
        widthFt: w >= l ? w : l,
        lengthFt: w >= l ? l : w,
        widthM: (w >= l ? w : l) / 3.28084,
        lengthM: (w >= l ? l : w) / 3.28084,
        mode: base.mode,
        source: 'user_confirm',
        wallsFt: base.wallsFt,
        wallsM: base.wallsM,
        cornersM: base.cornersM,
        posesM: base.posesM,
        sampleCount: base.sampleCount,
        poseCount: base.poseCount,
        orthogonalScore: base.orthogonalScore,
        diagonalError: base.diagonalError,
        coverageScore:
            base.coverageScore > 0.9 ? base.coverageScore : 0.9,
        depthEnabled: base.depthEnabled,
        depthSamples: base.depthSamples,
        wallLockWidthM: base.wallLockWidthM,
        wallLockLengthM: base.wallLockLengthM,
        wallLockPairs: base.wallLockPairs,
      );
      final pack = HomeScanPackage.fromMeasure(
        confirmed,
        appVersion: AppConfig.versionLabel,
        floorHitsM: _pack?.floorHitsM,
        posesM: _pack?.posesM,
      );
      final plan = pack.toPlanWithAiFurniture();
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
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _measure != null && _error == null && !_busy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan the room'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error != null) ...[
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade800),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _runArWalk,
                  child: const Text('Try again'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ] else if (confirming) ...[
                const Icon(Icons.straighten, size: 64, color: Colors.teal),
                const SizedBox(height: 16),
                Text(
                  'Confirm room size',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'AR suggested this size. Fix it with a tape measure if wrong, '
                  'then create the plan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Width (ft)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Length (ft)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_pack != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'AR samples: ${_pack!.sampleCount} floor · ${_pack!.poseCount} poses',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                Builder(
                  builder: (context) {
                    final ww = double.tryParse(_wCtrl.text.trim()) ?? 0;
                    final ll = double.tryParse(_lCtrl.text.trim()) ?? 0;
                    final large = ww > 24 || ll > 24;
                    if (!large) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'This size is large for a single room '
                        '(${ww.toStringAsFixed(0)}×${ll.toStringAsFixed(0)} ft). '
                        'Double-check with a tape before creating the plan.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _createPlan,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('Create plan with furniture'),
                ),
                TextButton(
                  onPressed: _runArWalk,
                  child: const Text('Re-scan with AR'),
                ),
              ] else ...[
                const Icon(Icons.view_in_ar, size: 72, color: Colors.teal),
                const SizedBox(height: 20),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Walk the full room near the walls. Tap Done when finished.\n'
                  'You will confirm size, then get a plan with furniture.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                if (_busy) ...[
                  const SizedBox(height: 28),
                  const CircularProgressIndicator(),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
