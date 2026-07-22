import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/furniture_catalog.dart';
import '../domain/photo_true_layout.dart';
import '../domain/plan_accuracy_metrics.dart';
import '../domain/scan_parser.dart';
import '../domain/scan_refine.dart';
import '../domain/scan_training_session.dart';
import '../domain/units.dart';
import '../domain/wall_relative_scan.dart';
import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import '../providers/room_provider.dart';
import '../services/analytics_service.dart';
import '../services/ar_measure_service.dart';
import '../services/storage_service.dart';
import '../services/training_export_service.dart';
import 'blueprint_screen.dart';

/// Review plan: edit openings by tape distances, toggle furniture, open editor.
class ScanReviewScreen extends ConsumerStatefulWidget {
  final ScanResult initial;

  const ScanReviewScreen({super.key, required this.initial});

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  late ScanResult _result;
  /// Model output at Review open — Phase B predicted baseline (+110).
  late ScanResult _predictedBaseline;
  int? _calibrateWallIndex;
  final _scaleController = TextEditingController();
  /// null | good | ok | bad — training signal for future model improvement.
  String? _feedbackRating;

  @override
  void initState() {
    super.initState();
    // Keep raw model output for Phase B training baseline
    _predictedBaseline = widget.initial;
    // +115: always show door-clear / gold-resolved plan on Review (multi-photo
    // vision often leaves table in front of door even after scanner polish)
    var plan = PhotoTrueLayout.ensureGoldQuality(widget.initial);
    plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
    if (PhotoTrueLayout.isStudyLike(plan)) {
      plan = PhotoTrueLayout.cleanStudyDeskAndDoors(plan);
      plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
    }
    _result = plan;
    ScanTrainingSession.begin(widget.initial);
  }

  Future<void> _refineWithAr() async {
    if (!ArMeasureService.isPlatformSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AR refine needs an ARCore Android device')),
      );
      return;
    }
    try {
      final m = await ArMeasureService.measureRoom(mode: 'chain');
      if (!mounted) return;
      setState(() {
        _result = ScanRefine.lockSize(
          _result,
          widthFt: m.widthFt,
          lengthFt: m.lengthFt,
          reason:
              'Size re-locked from AR 4-wall measure (${m.widthFt.toStringAsFixed(1)}×${m.lengthFt.toStringAsFixed(1)} ft)',
          scaleSource: m.isChain
              ? ScaleSource.arChain
              : ScaleSource.arQuick,
          oppositeWallError: m.oppositeWallError,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Plan rescaled to AR ${m.widthFt.toStringAsFixed(1)} × ${m.lengthFt.toStringAsFixed(1)} ft',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (!msg.contains('CANCELLED') && !msg.contains('cancelled')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AR refine: $msg')),
        );
      }
    }
  }

  Future<void> _sendFeedback(String rating) async {
    setState(() => _feedbackRating = rating);
    await AnalyticsService.instance.scanFeedback(
      rating: rating,
      mode: 'review',
      accuracyScore: _result.accuracyScore,
    );
    final openings = _result.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .length;
    // +109/110: Phase B vs template; if user edited openings/furniture, also vs baseline
    final phaseB = PlanAccuracyMetrics.diagnosticsJson(
      _predictedBaseline,
      userCorrected: _result,
    );
    final vs = PlanAccuracyMetrics.vsTemplate(_result);
    final vsUser = PlanAccuracyMetrics.compare(_predictedBaseline, _result);
    ScanTrainingSession.feedbackRating = rating;
    await TrainingExportService().logScanFeedback(
      rating: rating,
      mode: 'review',
      accuracyScore: _result.accuracyScore,
      roomWidthFt: _result.roomWidthFt,
      roomLengthFt: _result.roomLengthFt,
      furnitureCount: _result.furniture.where((f) => f.included).length,
      openingsCount: openings,
      phaseB: phaseB,
      plan: _result,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          rating == 'good'
              ? 'Thanks — saved · ${vs.reviewLine()}'
              : rating == 'ok'
                  ? 'Noted · ${vs.reviewLine()}'
                  : 'Logged bad scan · ${vs.reviewLine()}'
                      '${vsUser.compositeScore < 0.99 ? " · edits vs scan ${(vsUser.compositeScore * 100).round()}%" : ""}',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _openEditor() async {
    // +51/+112: gold quality + clean desk/doors before editor
    var polished = PhotoTrueLayout.ensureGoldQuality(_result);
    if (PhotoTrueLayout.isStudyLike(polished)) {
      polished = PhotoTrueLayout.cleanStudyDeskAndDoors(polished);
    }
    setState(() => _result = polished);
    final pxf = ref.read(roomProvider).pixelsPerFoot;
    final converted = ScanParser.toEditor(_result, pxf);
    // +113: initFromScan sanitizes + clears furniture blocking door swings
    ref.read(roomProvider.notifier).initFromScan(
          converted.width,
          converted.length,
          converted.strokes,
          converted.furniture,
        );
    await StorageService().saveRoom(ref.read(roomProvider).room);
    await AnalyticsService.instance.openEditorFromScan();
    // Snapshot + mark session for editor gold on save (+109/110)
    try {
      ScanTrainingSession.markReviewFinal(
        _result,
        rating: _feedbackRating,
      );
      await TrainingExportService().logScanResultSnapshot(
        source: 'open_editor',
        plan: _result,
        feedbackRating: _feedbackRating,
        userCorrected: _result,
      );
      // Also log predicted baseline with vs review-final as interim correction
      await TrainingExportService().logScanResultSnapshot(
        source: 'scan_predicted_baseline',
        plan: _predictedBaseline,
        feedbackRating: _feedbackRating,
        userCorrected: _result,
      );
    } catch (_) {}
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

  List<ScanWallSegment> get _openingsOnly => _result.walls
      .where((w) =>
          w.type == StrokeType.door ||
          w.type == StrokeType.window ||
          w.type == StrokeType.balcony)
      .toList();

  void _rebuildFromFieldOpenings(List<WallOpeningHint> openings) {
    final composed = WallRelativeComposer.compose(
      widthFt: _result.roomWidthFt,
      lengthFt: _result.roomLengthFt,
      openings: openings,
      furniture: _result.furniture
          .where((f) => f.included)
          .map(
            (f) => WallFurnitureHint(
              type: f.type,
              freePlace: true,
              freeXFt: f.posFt.dx,
              freeYFt: f.posFt.dy,
              widthFt: f.widthFt,
              lengthFt: f.lengthFt,
              rotDeg: f.rotationRad * 180 / 3.1415926535,
              confidence: 1,
            ),
          )
          .toList(),
      warnings: const ['Openings corrected on Review screen'],
      fromTapeMeasure: true,
    );
    setState(() => _result = composed.copyWith(
          furniture: _result.furniture,
          accuracyScore: composed.accuracyScore,
        ));
  }

  Future<void> _editOpening(int openingIndex) async {
    final unit = ref.read(roomProvider).unitSystem;
    final openings = _openingsOnly;
    if (openingIndex < 0 || openingIndex >= openings.length) return;
    final seg = openings[openingIndex];
    final field = WallRelativeComposer.openingToField(
      seg,
      _result.roomWidthFt,
      _result.roomLengthFt,
    );
    if (field == null) return;

    var wall = field.wall;
    var type = seg.type;
    final fromCtrl = TextEditingController(
      text: LengthFormat.feetToDisplay(field.fromLeftFt, unit).toStringAsFixed(1),
    );
    final widthCtrl = TextEditingController(
      text: LengthFormat.feetToDisplay(field.widthFt, unit).toStringAsFixed(1),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit opening (tape)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Distances from LEFT corner while facing the wall — designer method.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<WallSide>(
                  value: wall,
                  decoration: const InputDecoration(
                    labelText: 'Wall',
                    border: OutlineInputBorder(),
                  ),
                  items: WallSide.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.shortLabel)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => wall = v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<StrokeType>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: StrokeType.door, child: Text('Door')),
                    DropdownMenuItem(value: StrokeType.window, child: Text('Window')),
                    DropdownMenuItem(value: StrokeType.balcony, child: Text('Balcony')),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => type = v);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: fromCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'From left corner (${unit.label})',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: widthCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Opening width (${unit.label})',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) {
      fromCtrl.dispose();
      widthCtrl.dispose();
      return;
    }

    final fromL = LengthFormat.displayToFeet(
      double.tryParse(fromCtrl.text) ?? 0,
      unit,
    );
    final width = LengthFormat.displayToFeet(
      double.tryParse(widthCtrl.text) ?? 3,
      unit,
    );
    fromCtrl.dispose();
    widthCtrl.dispose();

    final rebuilt = <WallOpeningHint>[];
    for (var i = 0; i < openings.length; i++) {
      if (i == openingIndex) {
        rebuilt.add(WallOpeningHint.fromLeft(
          wall: wall,
          type: type,
          fromLeftFt: fromL,
          widthFt: width,
          wallLengthFt: wall.lengthFt(_result.roomWidthFt, _result.roomLengthFt),
          confidence: 1,
          evidence: 'review edit',
        ));
      } else {
        final f = WallRelativeComposer.openingToField(
          openings[i],
          _result.roomWidthFt,
          _result.roomLengthFt,
        );
        if (f == null) continue;
        rebuilt.add(WallOpeningHint.fromLeft(
          wall: f.wall,
          type: openings[i].type,
          fromLeftFt: f.fromLeftFt,
          widthFt: f.widthFt,
          wallLengthFt: f.wall.lengthFt(_result.roomWidthFt, _result.roomLengthFt),
          confidence: 1,
        ));
      }
    }
    _rebuildFromFieldOpenings(rebuilt);
  }

  Future<void> _addOpening() async {
    final unit = ref.read(roomProvider).unitSystem;
    var wall = WallSide.south;
    var type = StrokeType.door;
    final fromCtrl = TextEditingController(text: '2');
    final widthCtrl = TextEditingController(
      text: LengthFormat.feetToDisplay(3, unit).toStringAsFixed(1),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add opening'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<WallSide>(
                value: wall,
                decoration: const InputDecoration(labelText: 'Wall', border: OutlineInputBorder()),
                items: WallSide.values
                    .map((s) => DropdownMenuItem(value: s, child: Text(s.shortLabel)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setLocal(() => wall = v);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<StrokeType>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: StrokeType.door, child: Text('Door')),
                  DropdownMenuItem(value: StrokeType.window, child: Text('Window')),
                  DropdownMenuItem(value: StrokeType.balcony, child: Text('Balcony')),
                ],
                onChanged: (v) {
                  if (v != null) setLocal(() => type = v);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fromCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'From left (${unit.label})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: widthCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Width (${unit.label})',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) {
      fromCtrl.dispose();
      widthCtrl.dispose();
      return;
    }

    final openings = _openingsOnly;
    final rebuilt = <WallOpeningHint>[];
    for (final o in openings) {
      final f = WallRelativeComposer.openingToField(
        o,
        _result.roomWidthFt,
        _result.roomLengthFt,
      );
      if (f == null) continue;
      rebuilt.add(WallOpeningHint.fromLeft(
        wall: f.wall,
        type: o.type,
        fromLeftFt: f.fromLeftFt,
        widthFt: f.widthFt,
        wallLengthFt: f.wall.lengthFt(_result.roomWidthFt, _result.roomLengthFt),
      ));
    }
    rebuilt.add(WallOpeningHint.fromLeft(
      wall: wall,
      type: type,
      fromLeftFt: LengthFormat.displayToFeet(double.tryParse(fromCtrl.text) ?? 0, unit),
      widthFt: LengthFormat.displayToFeet(double.tryParse(widthCtrl.text) ?? 3, unit),
      wallLengthFt: wall.lengthFt(_result.roomWidthFt, _result.roomLengthFt),
    ));
    fromCtrl.dispose();
    widthCtrl.dispose();
    _rebuildFromFieldOpenings(rebuilt);
  }

  void _deleteOpening(int index) {
    final openings = _openingsOnly;
    final rebuilt = <WallOpeningHint>[];
    for (var i = 0; i < openings.length; i++) {
      if (i == index) continue;
      final f = WallRelativeComposer.openingToField(
        openings[i],
        _result.roomWidthFt,
        _result.roomLengthFt,
      );
      if (f == null) continue;
      rebuilt.add(WallOpeningHint.fromLeft(
        wall: f.wall,
        type: openings[i].type,
        fromLeftFt: f.fromLeftFt,
        widthFt: f.widthFt,
        wallLengthFt: f.wall.lengthFt(_result.roomWidthFt, _result.roomLengthFt),
      ));
    }
    _rebuildFromFieldOpenings(rebuilt);
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(roomProvider).unitSystem;
    final includedCount = _result.furniture.where((f) => f.included).length;
    final openings = _openingsOnly;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review scan'),
      ),
      body: Column(
        children: [
          MaterialBanner(
            content: Text(
              'Room outline is your W×L. Fix doors/windows with tape distances '
              '(from left corner facing each wall). Photo AI is approximate — '
              'LiDAR/AR competitors still need laser for 100%.',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Room ${LengthFormat.formatFeet(_result.roomWidthFt, unit)}'
                  ' × ${LengthFormat.formatFeet(_result.roomLengthFt, unit)}'
                  ' · ${openings.length} opening(s) · $includedCount furniture',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (_result.accuracyScore != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Plan confidence',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _result.accuracyScore!.clamp(0.0, 1.0),
                          backgroundColor: Colors.grey.shade200,
                          color: _result.accuracyScore! >= 0.75
                              ? Colors.teal
                              : _result.accuracyScore! >= 0.5
                                  ? Colors.orange
                                  : Colors.redAccent,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_result.accuracyScore! * 100).round()}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  // +109: Phase B vs gold-template diagnostics (Planner5D-class)
                  Builder(
                    builder: (context) {
                      final vs = PlanAccuracyMetrics.vsTemplate(_result);
                      final color = vs.compositeScore >= 0.75
                          ? Colors.teal.shade700
                          : vs.compositeScore >= 0.5
                              ? Colors.orange.shade800
                              : Colors.red.shade700;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          vs.reviewLine(),
                          style: TextStyle(fontSize: 11, color: color),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  children: [
                    Text('Doors / windows / balconies',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addOpening,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const Text(
                  'Tap to edit: from left corner (facing wall) + opening width.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (openings.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.door_front_door_outlined),
                      title: Text('No openings yet'),
                      subtitle: Text('Add door/window/balcony with tape distances'),
                    ),
                  )
                else
                  ...List.generate(openings.length, (i) {
                    final o = openings[i];
                    final field = WallRelativeComposer.openingToField(
                      o,
                      _result.roomWidthFt,
                      _result.roomLengthFt,
                    );
                    final title = field == null
                        ? o.type.name
                        : '${field.wall.shortLabel} · ${o.type.name}';
                    final sub = field == null
                        ? LengthFormat.formatFeet(o.lengthFt, unit)
                        : 'From left ${LengthFormat.formatFeet(field.fromLeftFt, unit)} · '
                            'width ${LengthFormat.formatFeet(field.widthFt, unit)}';
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        switch (o.type) {
                          StrokeType.door => Icons.door_front_door,
                          StrokeType.window => Icons.window,
                          StrokeType.balcony => Icons.deck,
                          _ => Icons.crop_square,
                        },
                        color: switch (o.type) {
                          StrokeType.door => Colors.orange,
                          StrokeType.window => Colors.blue,
                          StrokeType.balcony => Colors.green,
                          _ => Colors.grey,
                        },
                      ),
                      title: Text(title),
                      subtitle: Text(sub),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => _editOpening(i),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _deleteOpening(i),
                          ),
                        ],
                      ),
                      onTap: () => _editOpening(i),
                    );
                  }),
                const SizedBox(height: 12),
                Text('Scale calibration', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text(
                  'Optional: pick a segment and set its true length to rescale the plan.',
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
                              'Seg ${i + 1} (${_result.walls[i].type.name}) · '
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
                    color: Colors.orange.shade50,
                    child: const ListTile(
                      leading: Icon(Icons.chair_outlined),
                      title: Text('No furniture detected'),
                      subtitle: Text(
                        'Retake with multi-gallery photos of every wall (bed/sofa/TV fully visible), '
                        'or add pieces from the catalog in the editor. '
                        'Optional: Hugging Face / Groq key in Settings for better free AI.',
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
                        '${LengthFormat.formatFeet(f.lengthFt, unit)} · '
                        'center (${f.posFt.dx.toStringAsFixed(1)}, ${f.posFt.dy.toStringAsFixed(1)}) ft',
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
                  Text(
                    'How is this plan?',
                    style: Theme.of(context).textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your rating trains better auto-layout over time',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _FeedbackChip(
                        label: 'Looks right',
                        icon: Icons.thumb_up_alt_outlined,
                        selected: _feedbackRating == 'good',
                        onTap: () => _sendFeedback('good'),
                      ),
                      const SizedBox(width: 8),
                      _FeedbackChip(
                        label: 'Close',
                        icon: Icons.thumbs_up_down_outlined,
                        selected: _feedbackRating == 'ok',
                        onTap: () => _sendFeedback('ok'),
                      ),
                      const SizedBox(width: 8),
                      _FeedbackChip(
                        label: 'Off',
                        icon: Icons.thumb_down_alt_outlined,
                        selected: _feedbackRating == 'bad',
                        onTap: () => _sendFeedback('bad'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (ArMeasureService.isPlatformSupported)
                    OutlinedButton.icon(
                      onPressed: _refineWithAr,
                      icon: const Icon(Icons.view_in_ar),
                      label: const Text('Refine size with AR (higher accuracy)'),
                    ),
                  const SizedBox(height: 8),
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
                    child: const Text('Back'),
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

class _FeedbackChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FeedbackChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      avatar: Icon(icon, size: 16),
      selected: selected,
      onSelected: (_) => onTap(),
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

    final roomRect = Rect.fromLTWH(
      0,
      0,
      result.roomWidthFt * scale,
      result.roomLengthFt * scale,
    );
    canvas.drawRect(roomRect, Paint()..color = Colors.white);
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
        ..strokeWidth = w.type == StrokeType.wall ? 4 : 3.5
        ..strokeCap = StrokeCap.round
        ..color = switch (w.type) {
          StrokeType.wall => Colors.black87,
          StrokeType.door => Colors.orange,
          StrokeType.window => Colors.blue,
          StrokeType.balcony => Colors.green.shade700,
        };
      canvas.drawLine(p1, p2, paint);
      // +48: opening labels like gold plan
      if (w.type != StrokeType.wall) {
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        final name = switch (w.type) {
          StrokeType.door => 'Door',
          StrokeType.window => 'Window',
          StrokeType.balcony => 'Mesh',
          StrokeType.wall => '',
        };
        final lenFt = w.lengthFt;
        final tp = TextPainter(
          text: TextSpan(
            text: '$name ${lenFt.toStringAsFixed(1)}′',
            style: TextStyle(
              color: paint.color,
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - tp.height - 2));
      }
    }

    for (final f in result.furniture.where((e) => e.included)) {
      final cx = f.posFt.dx * scale;
      final cy = f.posFt.dy * scale;
      final rw = f.widthFt * scale;
      final rh = f.lengthFt * scale;
      // +42: type colors so gold-plan pieces read clearly on review
      final (Color fill, Color stroke) = switch (f.type) {
        FurnitureType.wardrobe => (Colors.indigo.shade100, Colors.indigo.shade800),
        FurnitureType.table => (Colors.amber.shade100, Colors.brown.shade700),
        FurnitureType.chair => (Colors.orange.shade100, Colors.orange.shade800),
        FurnitureType.bed => (Colors.purple.shade100, Colors.purple.shade700),
        FurnitureType.sofa => (Colors.teal.shade100, Colors.teal.shade800),
        _ => (Colors.teal.shade100, Colors.teal.shade700),
      };
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(f.rotationRad);
      final rect = Rect.fromCenter(center: Offset.zero, width: rw, height: rh);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      // Label with size like gold plan (+47)
      canvas.rotate(-f.rotationRad);
      final name = switch (f.type) {
        FurnitureType.wardrobe => 'Wardrobe',
        FurnitureType.table => 'Desk',
        FurnitureType.chair => 'Chair',
        FurnitureType.bed => 'Bed',
        FurnitureType.sofa => 'Sofa',
        FurnitureType.tvUnit => 'TV',
        _ => f.type.name,
      };
      final along = f.widthFt >= f.lengthFt ? f.widthFt : f.lengthFt;
      final deep = f.widthFt < f.lengthFt ? f.widthFt : f.lengthFt;
      final label =
          '$name\n${along.toStringAsFixed(1)}×${deep.toStringAsFixed(1)}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: stroke,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ScanPreviewPainter oldDelegate) =>
      oldDelegate.result != result;
}
