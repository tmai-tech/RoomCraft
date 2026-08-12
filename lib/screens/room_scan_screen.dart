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
/// +140: user marks openings/furniture (feedback 04919d14).
/// +145: one-wall tape calibrate + size quality coaching.
/// +146: soft-cap oversize AR (b5fa46b8 29×16); inventory checklist; no default wardrobe.
class RoomScanScreen extends ConsumerStatefulWidget {
  const RoomScanScreen({super.key});

  @override
  ConsumerState<RoomScanScreen> createState() => _RoomScanScreenState();
}

class _RoomScanScreenState extends ConsumerState<RoomScanScreen> {
  String _status = 'Starting…';
  bool _busy = false;
  String? _error;

  ArRoomMeasure? _measure;
  HomeScanPackage? _pack;
  late final TextEditingController _wCtrl;
  late final TextEditingController _lCtrl;
  late final TextEditingController _knownWallCtrl;

  /// +146: start empty — user must pick Study gold or Lounge (or chips).
  /// Default study gold caused full-wall wardrobe on every oversized AR (b5fa46b8).
  HomeScanInventory _inventory = const HomeScanInventory();

  String _calibrateAxis = 'width';
  bool _oneWallApplied = false;
  String? _calibrateNote;
  bool _sizeWasClamped = false;
  bool _sizeWasUndersized = false;
  double? _rawArWidth;
  double? _rawArLength;

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController();
    _lCtrl = TextEditingController();
    _knownWallCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runArWalk());
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _lCtrl.dispose();
    _knownWallCtrl.dispose();
    super.dispose();
  }

  Future<void> _runArWalk() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _measure = null;
      _pack = null;
      _oneWallApplied = false;
      _calibrateNote = null;
      _sizeWasClamped = false;
      _sizeWasUndersized = false;
      _rawArWidth = null;
      _rawArLength = null;
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
      final proposed = HomeScanGeometry.proposeConfirmSize(
        widthFt: size.widthFt,
        lengthFt: size.lengthFt,
        hasWallLock: measure.hasWallLock,
      );
      _wCtrl.text = proposed.widthFt.toStringAsFixed(1);
      _lCtrl.text = proposed.lengthFt.toStringAsFixed(1);
      _knownWallCtrl.clear();

      setState(() {
        _busy = false;
        _measure = measure;
        _pack = pack;
        _sizeWasClamped = proposed.clamped;
        _sizeWasUndersized = proposed.undersized;
        _rawArWidth = proposed.rawWidthFt;
        _rawArLength = proposed.rawLengthFt;
        if (proposed.undersized) {
          _calibrateNote =
              'AR map was too small '
              '(${proposed.rawWidthFt.toStringAsFixed(0)}×${proposed.rawLengthFt.toStringAsFixed(0)} ft) '
              '— filled study gold 20.3×17. Tape one wall or re-scan a full loop.';
        }
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

  void _applyOneWallCalibrate() {
    final known = double.tryParse(_knownWallCtrl.text.trim());
    final w = double.tryParse(_wCtrl.text.trim());
    final l = double.tryParse(_lCtrl.text.trim());
    if (known == null || known < 6 || known > 40) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the tape length in feet (6–40 ft).'),
        ),
      );
      return;
    }
    if (w == null || l == null || w < 3 || l < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AR size missing — re-scan first.')),
      );
      return;
    }
    final scaled = HomeScanGeometry.scaleByKnownWall(
      proposedWidthFt: w,
      proposedLengthFt: l,
      axis: _calibrateAxis,
      knownWallFt: known,
    );
    if (scaled == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not apply that measurement — check the number.'),
        ),
      );
      return;
    }
    setState(() {
      _wCtrl.text = scaled.widthFt.toStringAsFixed(1);
      _lCtrl.text = scaled.lengthFt.toStringAsFixed(1);
      _oneWallApplied = true;
      _sizeWasClamped = false;
      _calibrateNote =
          'Scaled from tape: ${_calibrateAxis == 'length' ? 'short' : 'long'} '
          'wall = ${known.toStringAsFixed(1)} ft '
          '(×${scaled.scale.toStringAsFixed(2)})';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Size locked: ${scaled.widthFt.toStringAsFixed(1)} × '
          '${scaled.lengthFt.toStringAsFixed(1)} ft from one wall',
        ),
      ),
    );
  }

  void _applyGoldStudySize() {
    setState(() {
      _wCtrl.text = HomeScanGeometry.goldStudyWidthFt.toStringAsFixed(1);
      _lCtrl.text = HomeScanGeometry.goldStudyLengthFt.toStringAsFixed(1);
      _oneWallApplied = true;
      _sizeWasClamped = false;
      _calibrateNote =
          'Applied study gold size ${HomeScanGeometry.goldStudyWidthFt}×'
          '${HomeScanGeometry.goldStudyLengthFt} ft (32ffdc65 tape)';
      _inventory = HomeScanInventory.studyGold;
    });
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

    // +147: hard block closet-size rooms (c643ffe0 7.0×5.1)
    if (w < 9 || l < 8) {
      final fix = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Room size too small'),
          content: Text(
            '${w.toStringAsFixed(1)}×${l.toStringAsFixed(1)} ft is too small for a room plan '
            '(AR often under-sizes incomplete walks). Re-scan a full loop, tape one wall, '
            'or use study gold 20.3×17.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'back'),
              child: const Text('Go back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'gold'),
              child: const Text('Use 20.3×17'),
            ),
          ],
        ),
      );
      if (fix == 'gold') {
        _applyGoldStudySize();
      }
      return;
    }

    // +146: hard block huge sizes without tape / one-wall (b5fa46b8 29.3 ft)
    if (!_oneWallApplied &&
        (w > HomeScanGeometry.hardConfirmWidthFt ||
            l > HomeScanGeometry.hardConfirmLengthFt)) {
      final fix = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Size looks too large'),
          content: Text(
            '${w.toStringAsFixed(1)}×${l.toStringAsFixed(1)} ft is large for one room '
            '(AR often over-sizes). Measure one wall with a tape, or use the '
            'study gold size (20.3×17) if this is that room.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'back'),
              child: const Text('Go back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'gold'),
              child: const Text('Use 20.3×17'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'force'),
              child: const Text('My room is this large'),
            ),
          ],
        ),
      );
      if (fix == null || fix == 'back') return;
      if (fix == 'gold') {
        _applyGoldStudySize();
        return;
      }
      // force → treat as intentional large room
      setState(() => _oneWallApplied = true);
    }

    if (!_inventory.isReadyToPlace) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mark openings/furniture or tap Study gold / Lounge first.',
          ),
        ),
      );
      return;
    }

    final pack0 = _pack;
    if (pack0 != null &&
        !_oneWallApplied &&
        pack0.qualityRejectReason() != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Map may be incomplete'),
          content: Text(
            '${pack0.qualityRejectReason()}\n\n'
            'Tip: measure one wall with a tape, or re-scan a full loop.\n\n'
            'Create plan with ${w.toStringAsFixed(1)}×${l.toStringAsFixed(1)} ft anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use this size'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    final inv = _inventory;

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
      final source = _oneWallApplied ? 'one_wall_calibrate' : 'user_confirm';
      final confirmed = ArRoomMeasure(
        widthFt: w >= l ? w : l,
        lengthFt: w >= l ? l : w,
        widthM: (w >= l ? w : l) / 3.28084,
        lengthM: (w >= l ? l : w) / 3.28084,
        mode: base.mode,
        source: source,
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
      var plan = pack.toPlanWithInventory(inv);
      // Density guard only when user asked for study wardrobe layout
      final furnN = plan.furniture.where((f) => f.included).length;
      if (inv.usesStudyGoldLayout && furnN < 3) {
        plan = pack.toPlanWithInventory(HomeScanInventory.studyGold);
      }
      // +146 match report into snackbar before open
      final report =
          HomeScanInventoryComposer.matchReport(plan, inv);
      final pxf = AppConfig.defaultPixelsPerFoot;
      final converted = ScanParser.toEditor(plan, pxf);
      ref.read(roomProvider.notifier).initFromScan(
            converted.width,
            converted.length,
            converted.strokes,
            converted.furniture,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.fullMatch
                ? 'Plan: ${report.summary}'
                : 'Plan partial: ${report.summary}',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
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
    final hints = _pack?.sizeQualityHints() ?? const <String>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan the room'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      // +147: never wrap ScrollView in Center — causes BOTTOM OVERFLOW
      // (feedback c643ffe0 yellow/black stripes on confirm size).
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                const Icon(Icons.straighten, size: 48, color: Colors.teal),
                const SizedBox(height: 8),
                Text(
                  'Confirm size & contents',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '1) Fix room size (tape one wall if AR is off). '
                  '2) Mark what is in the room — no random layout.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.3,
                    fontSize: 13,
                  ),
                ),
                if (_sizeWasUndersized &&
                    _rawArWidth != null &&
                    _rawArLength != null) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        'AR map too small '
                        '(${_rawArWidth!.toStringAsFixed(0)}×${_rawArLength!.toStringAsFixed(0)} ft) '
                        '— incomplete walk. Use tape / Study gold 20.3×17, or re-scan all walls.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ),
                ] else if (_sizeWasClamped &&
                    _rawArWidth != null &&
                    _rawArLength != null) ...[
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        'AR raw size looked large '
                        '(${_rawArWidth!.toStringAsFixed(0)}×${_rawArLength!.toStringAsFixed(0)} ft) '
                        '— capped for a single room. Measure one wall or tap '
                        '“Study gold 20.3×17” if that is your room.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: Colors.deepOrange.shade900,
                        ),
                      ),
                    ),
                  ),
                ],
                if (hints.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final h in hints.take(1))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            h,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {
                          _oneWallApplied = false;
                        }),
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
                        onChanged: (_) => setState(() {
                          _oneWallApplied = false;
                        }),
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
                    'AR samples: ${_pack!.sampleCount} floor · ${_pack!.poseCount} poses'
                    '${_pack!.resolvedSize.coverage > 0 ? ' · cover ${(_pack!.resolvedSize.coverage * 100).round()}%' : ''}'
                    '${_oneWallApplied ? ' · tape lock' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                if (_calibrateNote != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _calibrateNote!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _applyGoldStudySize,
                      child: const Text('Study gold 20.3×17'),
                    ),
                  ],
                ),
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
                        'Tape one wall or use Study gold 20.3×17.',
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
                const SizedBox(height: 14),
                Material(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'I measured one wall (recommended)',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: Colors.teal.shade900,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tape one wall, pick which side, Apply. '
                          'Other side scales to keep AR shape.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.teal.shade900,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _calibrateAxis,
                                decoration: const InputDecoration(
                                  labelText: 'Which wall',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'width',
                                    child: Text('Longer side (width)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'length',
                                    child: Text('Shorter side (length)'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _calibrateAxis = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _knownWallCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Tape (ft)',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _applyOneWallCalibrate,
                          icon: const Icon(Icons.straighten, size: 18),
                          label: const Text('Apply one-wall scale'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Room type (required)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => setState(() {
                        _inventory = HomeScanInventory.studyGold;
                      }),
                      child: const Text('Study gold (+36)'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(() {
                        _inventory = HomeScanInventory.loungeOffice;
                      }),
                      child: const Text('Lounge (bean bag)'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 12),
                // +146 Phase 2 match checklist
                Material(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Will place on plan',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _inventory.isReadyToPlace
                              ? _inventory.summaryLabel
                              : 'Nothing selected — pick Study gold, Lounge, or chips',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _inventory.isReadyToPlace
                                ? Colors.blueGrey.shade900
                                : Colors.red.shade800,
                          ),
                        ),
                        if (_inventory.usesStudyGoldLayout) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Layout: study gold (wardrobe wall unit)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                        ] else if (_inventory.isReadyToPlace) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Layout: inventory placement (no invented bed/sofa)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        for (final line in _inventory.matchChecklistLines())
                          Text(
                            line,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Colors.blueGrey.shade800,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 48),
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
                  'Then fix size (tape if needed) and mark doors / furniture.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                if (_busy) ...[
                  const SizedBox(height: 28),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
