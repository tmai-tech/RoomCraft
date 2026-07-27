import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../domain/home_scan.dart';
import '../domain/home_scan_inventory.dart';
import '../domain/scan_parser.dart';
import '../providers/room_provider.dart';
import '../services/ar_measure_service.dart' show ArMeasureService, ArRoomMeasure;
import '../services/home_scan_service.dart';
import 'blueprint_screen.dart';

/// Scan the room → confirm size → inventory → plan.
///
/// +137: AR proposes size; user confirms feet before plan.
/// +140: user marks openings/furniture (feedback 04919d14) — no random AI bed/sofa.
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

  /// Default: study gold (+36 quality / 32ffdc65). Lounge preset one tap away.
  HomeScanInventory _inventory = HomeScanInventory.studyGold;

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
      _wCtrl.text = size.widthFt.toStringAsFixed(1);
      _lCtrl.text = size.lengthFt.toStringAsFixed(1);

      setState(() {
        _busy = false;
        _measure = measure;
        _pack = pack;
        _status = 'Confirm size & contents';
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
    if (!_inventory.hasAnyOpenings && !_inventory.hasAnyFurniture) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mark doors/windows or furniture, or use the lounge preset.'),
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Creating plan…';
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
        coverageScore: base.coverageScore > 0.9 ? base.coverageScore : 0.9,
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
      // +140: inventory plan — not random AI living fill (feedback 04919d14)
      final plan = pack.toPlanWithInventory(_inventory);
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

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Colors.teal.shade100,
      checkmarkColor: Colors.teal.shade800,
    );
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
          padding: const EdgeInsets.all(24),
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
                const Icon(Icons.straighten, size: 56, color: Colors.teal),
                const SizedBox(height: 12),
                Text(
                  'Confirm size & contents',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'AR measures size only. Mark what is actually in the room '
                  'so the plan matches (not a random layout).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                const SizedBox(height: 18),
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
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Openings',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(
                      label: '1 door',
                      selected: _inventory.doors == 1,
                      onTap: () => setState(() {
                        _inventory = _inventory.copyWith(
                          doors: _inventory.doors == 1 ? 0 : 1,
                        );
                      }),
                    ),
                    _chip(
                      label: '2 doors',
                      selected: _inventory.doors == 2,
                      onTap: () => setState(() {
                        _inventory = _inventory.copyWith(
                          doors: _inventory.doors == 2 ? 0 : 2,
                        );
                      }),
                    ),
                    _chip(
                      label: 'French window',
                      selected: _inventory.frenchWindow,
                      onTap: () => setState(() {
                        _inventory = _inventory.copyWith(
                          frenchWindow: !_inventory.frenchWindow,
                        );
                      }),
                    ),
                    _chip(
                      label: 'Window',
                      selected: _inventory.windows >= 1,
                      onTap: () => setState(() {
                        _inventory = _inventory.copyWith(
                          windows: _inventory.windows >= 1 ? 0 : 1,
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Furniture',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip(
                      label: 'Wardrobe',
                      selected: _inventory.wardrobe,
                      onTap: () => setState(() {
                        _inventory = _inventory.copyWith(
                          wardrobe: !_inventory.wardrobe,
                        );
                      }),
                    ),
                    _chip(
                      label: 'Desk',
                      selected: _inventory.desk,
                      onTap: () => setState(() {
                        _inventory =
                            _inventory.copyWith(desk: !_inventory.desk);
                      }),
                    ),
                    _chip(
                      label: 'Table',
                      selected: _inventory.table,
                      onTap: () => setState(() {
                        _inventory =
                            _inventory.copyWith(table: !_inventory.table);
                      }),
                    ),
                    _chip(
                      label: 'Bean bag',
                      selected: _inventory.beanBag,
                      onTap: () => setState(() {
                        _inventory = _inventory.copyWith(
                          beanBag: !_inventory.beanBag,
                        );
                      }),
                    ),
                    _chip(
                      label: 'Sofa',
                      selected: _inventory.sofa,
                      onTap: () => setState(() {
                        _inventory =
                            _inventory.copyWith(sofa: !_inventory.sofa);
                      }),
                    ),
                    _chip(
                      label: 'Bed',
                      selected: _inventory.bed,
                      onTap: () => setState(() {
                        _inventory =
                            _inventory.copyWith(bed: !_inventory.bed);
                      }),
                    ),
                    _chip(
                      label: 'Chair',
                      selected: _inventory.chair,
                      onTap: () => setState(() {
                        _inventory =
                            _inventory.copyWith(chair: !_inventory.chair);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Selected: ${_inventory.summaryLabel}'
                  '${_inventory.usesStudyGoldLayout ? ' · study gold layout' : ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _inventory = HomeScanInventory.studyGold;
                      }),
                      child: const Text('Study gold (+36 layout)'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _inventory = HomeScanInventory.loungeOffice;
                      }),
                      child: const Text('Lounge (bean bag)'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _createPlan,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('Create plan'),
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
                  'Then confirm size and mark doors / furniture.',
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
