import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../domain/layout/ai_designer.dart';
import '../domain/layout/ai_styler.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/layout/layout_alternatives.dart';
import '../domain/layout/walkway_heatmap.dart';
import '../domain/scan_parser.dart';
import '../domain/scan_training_session.dart';
import '../domain/units.dart';
import '../models/furniture_item.dart';
import '../models/room_model.dart';
import '../painters/blueprint_painter.dart';
import '../painters/furniture_painter.dart';
import '../painters/isometric_painter.dart';
import '../providers/room_provider.dart';
import '../screens/isometric_preview_screen.dart';
import '../services/analytics_service.dart';
import '../services/export_service.dart';
import '../services/prefs_service.dart';
import '../services/storage_service.dart';
import '../services/training_export_service.dart';
import '../widgets/furniture_catalog_sheet.dart';

class BlueprintScreen extends ConsumerStatefulWidget {
  const BlueprintScreen({super.key});

  @override
  ConsumerState<BlueprintScreen> createState() => _BlueprintScreenState();
}

class _BlueprintScreenState extends ConsumerState<BlueprintScreen> {
  final TransformationController _transformController = TransformationController();
  final PrefsService _prefs = PrefsService();
  /// Integrated 3D edit mode (Planner-style 2D/3D toggle).
  bool _view3d = false;
  double _isoYaw = 0;
  double _isoPitch = 0.35;
  /// Walkway free-path heatmap overlay (layout intelligence).
  bool _showWalkwayHeatmap = false;
  /// +139: fit room to viewport once after open / size change (feedback 7f07625b).
  bool _didFitView = false;
  Size? _lastViewport;
  double _lastFitW = 0;
  double _lastFitL = 0;
  double _lastFitPxf = 0;

  static const Offset _canvasOrigin =
      Offset(AppConfig.canvasOriginPx, AppConfig.canvasOriginPx);

  static const double _canvasSize = 1200;

  /// Convert GestureDetector local coords → room model coords (origin at room TL).
  Offset _toModel(Offset local) => local - _canvasOrigin;

  /// Log predicted scan vs user-corrected editor plan as Phase B gold (+110).
  /// Returns true when a training pair was written.
  Future<bool> _logCorrectedGoldIfNeeded(RoomModel room, double pxf) async {
    if (!ScanTrainingSession.active) return false;
    final pred = ScanTrainingSession.predicted;
    if (pred == null) return false;
    try {
      final corrected = ScanParser.fromEditor(
        widthFt: room.widthInFeet,
        lengthFt: room.lengthInFeet,
        strokes: room.strokes,
        furniture: room.furniture,
        pixelsPerFoot: pxf,
        warnings: pred.warnings,
        accuracyScore: 0.96,
      );
      final pair = ScanTrainingSession.pairDiagnostics(corrected);
      await TrainingExportService().logCorrectedGoldPair(
        predicted: pred,
        corrected: corrected,
        feedbackRating: ScanTrainingSession.feedbackRating,
        pairDiagnostics: pair,
      );
      ScanTrainingSession.correctedLogged = true;
      ScanTrainingSession.clear();
      return true;
    } catch (_) {
      // Training export must never block save
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  Future<void> _loadUnits() async {
    final unit = await _prefs.loadUnitSystem();
    if (!mounted) return;
    ref.read(roomProvider.notifier).setUnitSystem(unit);
  }

  /// Fit full room outline into the InteractiveViewer viewport.
  /// Feedback 7f07625b: plan out of screen, cannot see full view.
  void _fitRoomToView({
    required RoomModel room,
    required double pixelsPerFoot,
    required Size viewport,
    bool force = false,
  }) {
    if (viewport.width < 32 || viewport.height < 32) return;
    final pxf = pixelsPerFoot.isFinite && pixelsPerFoot > 0.5
        ? pixelsPerFoot
        : AppConfig.defaultPixelsPerFoot;
    final rw = room.widthInFeet.isFinite ? room.widthInFeet : 10.0;
    final rl = room.lengthInFeet.isFinite ? room.lengthInFeet : 10.0;
    if (rw <= 0 || rl <= 0) return;

    if (!force &&
        _didFitView &&
        (_lastFitW - rw).abs() < 0.05 &&
        (_lastFitL - rl).abs() < 0.05 &&
        (_lastFitPxf - pxf).abs() < 0.5 &&
        _lastViewport != null &&
        (_lastViewport!.width - viewport.width).abs() < 8 &&
        (_lastViewport!.height - viewport.height).abs() < 8) {
      return;
    }

    final origin = AppConfig.canvasOriginPx;
    // Content box = room + padding around outline (labels / doors)
    final contentW = rw * pxf + origin * 2 + 40;
    final contentH = rl * pxf + origin * 2 + 40;
    const pad = 20.0;
    final scaleX = (viewport.width - pad * 2) / contentW;
    final scaleY = (viewport.height - pad * 2) / contentH;
    // +147: allow deeper zoom-out for long rooms + edge dimension labels
    final scale = math.min(scaleX, scaleY).clamp(0.08, 2.8);

    // Center the content origin area in the viewport
    final dx = (viewport.width - contentW * scale) / 2;
    final dy = (viewport.height - contentH * scale) / 2;

    // Scale about origin then translate into viewport center.
    // Use storage writes — Matrix4.translate/scale signatures vary by SDK.
    final m = Matrix4.identity();
    m.storage[0] = scale;
    m.storage[5] = scale;
    m.storage[10] = 1.0;
    m.storage[12] = dx;
    m.storage[13] = dy;
    _transformController.value = m;

    _didFitView = true;
    _lastViewport = viewport;
    _lastFitW = rw;
    _lastFitL = rl;
    _lastFitPxf = pxf;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomState = ref.watch(roomProvider);
    final roomNotifier = ref.read(roomProvider.notifier);

    final panEnabled = roomState.currentTool == ToolMode.pan ||
        (roomState.currentTool == ToolMode.select &&
            !roomState.isDraggingFurniture &&
            !roomState.hasSelection);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          try {
            await StorageService().saveRoom(roomState.room);
            await _logCorrectedGoldIfNeeded(
              roomState.room,
              roomState.pixelsPerFoot,
            );
          } catch (_) {
            // Save failure must not crash exit (feedback 9bbf5b05 red screen)
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            onTap: () =>
                _showRenameDialog(context, roomNotifier, roomState.room),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(roomState.room.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                const Icon(Icons.edit, size: 14),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.fit_screen),
              tooltip: 'Fit plan to screen',
              onPressed: () {
                final vs = _lastViewport;
                if (vs == null) {
                  _didFitView = false;
                  setState(() {});
                  return;
                }
                _fitRoomToView(
                  room: roomState.room,
                  pixelsPerFoot: roomState.pixelsPerFoot,
                  viewport: vs,
                  force: true,
                );
                setState(() {});
              },
            ),
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () async {
                try {
                  await StorageService().saveRoom(roomState.room);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Save failed: $e')),
                    );
                  }
                  return;
                }
                final logged = await _logCorrectedGoldIfNeeded(
                  roomState.room,
                  roomState.pixelsPerFoot,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        logged
                            ? 'Blueprint saved · training gold pair logged'
                            : 'Blueprint Saved Locally',
                      ),
                    ),
                  );
                }
              },
              tooltip: 'Save',
            ),
            IconButton(
              icon: Icon(_view3d ? Icons.grid_on : Icons.view_in_ar),
              tooltip: _view3d ? '2D plan' : '3D edit mode',
              onPressed: () {
                setState(() => _view3d = !_view3d);
                AnalyticsService.instance.logEvent(
                  _view3d ? 'blueprint_3d_mode' : 'blueprint_2d_mode',
                );
              },
              onLongPress: () async {
                // Full-screen 3D editor
                final result = await Navigator.of(context).push<List<FurnitureItem>>(
                  MaterialPageRoute(
                    builder: (_) => IsometricPreviewScreen(
                      room: roomState.room,
                      pixelsPerFoot: roomState.pixelsPerFoot,
                      unitSystem: roomState.unitSystem,
                      onFurnitureChanged: (items) {
                        roomNotifier.applyLayoutAlternative(items);
                      },
                    ),
                  ),
                );
                if (result != null) {
                  roomNotifier.applyLayoutAlternative(result);
                }
                AnalyticsService.instance.logEvent('isometric_edit_fullscreen');
              },
            ),
            PopupMenuButton<String>(
              tooltip: 'Export',
              icon: const Icon(Icons.ios_share),
              onSelected: (v) async {
                try {
                  if (v == 'png') {
                    await ExportService.sharePng(
                      roomState.room,
                      pixelsPerFoot: roomState.pixelsPerFoot,
                      unitSystem: roomState.unitSystem,
                    );
                    await AnalyticsService.instance.exportPng();
                  } else if (v == 'png_walk') {
                    await ExportService.sharePng(
                      roomState.room,
                      pixelsPerFoot: roomState.pixelsPerFoot,
                      unitSystem: roomState.unitSystem,
                      showWalkwayHeatmap: true,
                    );
                    await AnalyticsService.instance
                        .logEvent('export_png_walkway');
                  } else if (v == 'pdf') {
                    await ExportService.sharePdf(
                      roomState.room,
                      unitSystem: roomState.unitSystem,
                    );
                    await AnalyticsService.instance.logEvent('export_pdf');
                  } else if (v == 'pack') {
                    await ExportService.sharePlanPack(
                      roomState.room,
                      pixelsPerFoot: roomState.pixelsPerFoot,
                      unitSystem: roomState.unitSystem,
                    );
                    await AnalyticsService.instance.logEvent('export_plan_pack');
                  } else if (v == 'store') {
                    await ExportService.shareStoreScreenshot(
                      roomState.room,
                      pixelsPerFoot: roomState.pixelsPerFoot,
                      unitSystem: roomState.unitSystem,
                    );
                    await AnalyticsService.instance
                        .logEvent('export_store_screenshot');
                  } else if (v == 'feature') {
                    await ExportService.shareFeatureGraphic();
                    await AnalyticsService.instance
                        .logEvent('export_feature_graphic');
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $e')),
                    );
                  }
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'png', child: Text('Share PNG image')),
                PopupMenuItem(
                  value: 'png_walk',
                  child: Text('Share PNG + walkway heatmap'),
                ),
                PopupMenuItem(value: 'pdf', child: Text('Share PDF summary')),
                PopupMenuItem(
                  value: 'pack',
                  child: Text('Share plan pack (2D + 3D)'),
                ),
                PopupMenuItem(
                  value: 'store',
                  child: Text('Share store screenshot (1080×1920)'),
                ),
                PopupMenuItem(
                  value: 'feature',
                  child: Text('Share feature graphic (1024×500)'),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: roomState.canUndo ? () => roomNotifier.undo() : null,
              tooltip: 'Undo',
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: roomState.canRedo ? () => roomNotifier.redo() : null,
              tooltip: 'Redo',
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever),
              onPressed: () => _confirmClear(context, roomNotifier),
              tooltip: 'Clear All',
            ),
          ],
        ),
        body: Column(
          children: [
            _buildToolbar(context, roomState, roomNotifier),
            _buildModeHint(roomState),
            _buildStatsPanel(context, roomState, roomNotifier),
            _buildLayoutBar(context, roomState, roomNotifier),
            if (_view3d)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Chip(
                        avatar: const Icon(Icons.view_in_ar, size: 16),
                        label: const Text(
                          '3D edit mode',
                          overflow: TextOverflow.ellipsis,
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.teal.shade50,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _view3d = false),
                      child: const Text('2D'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _view3d
                  ? _buildIntegrated3d(roomState, roomNotifier)
                  : ColoredBox(
                      color: Colors.grey.shade100,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final vp = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted || _view3d) return;
                            _fitRoomToView(
                              room: roomState.room,
                              pixelsPerFoot: roomState.pixelsPerFoot,
                              viewport: vp,
                            );
                          });
                          return InteractiveViewer(
                        transformationController: _transformController,
                        minScale: 0.08,
                        maxScale: 5.0,
                        boundaryMargin: const EdgeInsets.all(double.infinity),
                        panEnabled: panEnabled,
                        scaleEnabled: true,
                        child: SizedBox(
                          width: _canvasSize,
                          height: _canvasSize,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: (details) {
                              final model = _toModel(details.localPosition);
                              if (roomState.isDrawTool) {
                                roomNotifier.startStroke(model);
                              } else if (roomState.currentTool ==
                                  ToolMode.select) {
                                roomNotifier.selectFurnitureAt(model);
                              }
                            },
                            onPanUpdate: (details) {
                              if (roomState.isDrawTool) {
                                roomNotifier.updateStroke(
                                    _toModel(details.localPosition));
                              } else if (roomState.currentTool ==
                                      ToolMode.select &&
                                  roomState.hasSelection) {
                                roomNotifier
                                    .updateFurniturePosition(details.delta);
                              }
                            },
                            onPanEnd: (_) {
                              if (roomState.isDrawTool) {
                                roomNotifier.endStroke();
                              } else if (roomState.currentTool ==
                                  ToolMode.select) {
                                roomNotifier.endFurnitureDrag();
                              }
                            },
                            child: CustomPaint(
                              size: const Size(_canvasSize, _canvasSize),
                              painter: BlueprintPainter(
                                room: roomState.room,
                                currentStroke: roomState.currentStroke,
                                pixelsPerFoot: roomState.pixelsPerFoot,
                                unitSystem: roomState.unitSystem,
                                origin: _canvasOrigin,
                                showWalkwayHeatmap: _showWalkwayHeatmap,
                              ),
                              foregroundPainter: FurniturePainter(
                                furniture: roomState.room.furniture,
                                selectedId: roomState.selectedFurnitureId,
                                selectedIds: roomState.selectedFurnitureIds,
                                pixelsPerFoot: roomState.pixelsPerFoot,
                                unitSystem: roomState.unitSystem,
                                collisionIds: roomState.collisionIds,
                                origin: _canvasOrigin,
                              ),
                            ),
                          ),
                        ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
        floatingActionButton: roomState.hasSelection
            ? Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'rotate45FAB',
                    tooltip: 'Rotate 45° (or drag amber handle)',
                    onPressed: () => roomNotifier.rotateSelectedFurniture(),
                    child: const Icon(Icons.rotate_right),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'rotate90FAB',
                    tooltip: 'Rotate 90°',
                    onPressed: () =>
                        roomNotifier.rotateSelectedFurniture(degrees: 90),
                    child: const Icon(Icons.rotate_90_degrees_cw),
                  ),
                  if (roomState.selectedFurnitureId != null &&
                      roomState.effectiveSelection.length == 1) ...[
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'resizeFAB',
                      tooltip: 'Resize',
                      onPressed: () =>
                          _resizeSelected(context, roomNotifier, roomState),
                      child: const Icon(Icons.photo_size_select_small),
                    ),
                  ],
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'deleteFAB',
                    backgroundColor: Colors.red.shade100,
                    tooltip: roomState.effectiveSelection.length > 1
                        ? 'Delete selected'
                        : 'Delete',
                    onPressed: () => roomNotifier.deleteSelectedFurniture(),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                ],
              )
            : null,
      ),
    );
  }



  Widget _buildIntegrated3d(RoomState roomState, RoomNotifier roomNotifier) {
    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onTapUp: (d) {
                    _selectInIso(d.localPosition, size, roomState, roomNotifier);
                  },
                  onHorizontalDragUpdate: (d) {
                    setState(() => _isoYaw += d.delta.dx * 0.01);
                  },
                  child: CustomPaint(
                    painter: IsometricPainter(
                      room: roomState.room,
                      pixelsPerFoot: roomState.pixelsPerFoot,
                      unitSystem: roomState.unitSystem,
                      yaw: _isoYaw,
                      wallHeightFt:
                          roomState.room.wallHeightFt.clamp(7.0, 14.0) +
                              (_isoPitch - 0.35) * 2,
                      selectedId: roomState.selectedFurnitureId,
                      perspective: true,
                    ),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Orbit', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: _isoYaw.clamp(-3.14, 3.14),
                    min: -3.14,
                    max: 3.14,
                    onChanged: (v) => setState(() => _isoYaw = v),
                  ),
                ),
                const Text('H', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: _isoPitch,
                    min: 0,
                    max: 1,
                    onChanged: (v) => setState(() => _isoPitch = v),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectInIso(
    Offset local,
    Size size,
    RoomState roomState,
    RoomNotifier notifier,
  ) {
    final room = roomState.room;
    if (room.furniture.isEmpty) return;
    final ids = room.furniture.map((f) => f.id).toList();
    final cur = roomState.selectedFurnitureId;
    final idx = cur == null ? 0 : (ids.indexOf(cur) + 1) % ids.length;
    notifier.selectFurnitureById(ids[idx]);
  }

  Widget _buildLayoutBar(
    BuildContext context,
    RoomState state,
    RoomNotifier notifier,
  ) {
    final score = state.layoutScore;
    final Color scoreColor;
    if (score >= 80) {
      scoreColor = Colors.green.shade700;
    } else if (score >= 50) {
      scoreColor = Colors.orange.shade800;
    } else {
      scoreColor = Colors.red.shade700;
    }

    final tip = state.layoutTips.isEmpty
        ? 'Add furniture or run Auto-arrange'
        : state.layoutTips.first.message;

    final walkwayPct = _showWalkwayHeatmap
        ? (WalkwayHeatmap.freeFraction(
                  WalkwayHeatmap.compute(
                    state.room,
                    state.pixelsPerFoot,
                  ),
                ) *
                100)
            .round()
        : null;

    return Container(
      width: double.infinity,
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Score $score',
                  style: TextStyle(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              if (walkwayPct != null) ...[
                const SizedBox(width: 6),
                Container(
                  key: const Key('walkway_free_pct'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.teal.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Walkways $walkwayPct%',
                    style: TextStyle(
                      color: Colors.teal.shade800,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tip,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                key: const Key('walkway_heatmap_toggle'),
                tooltip: _showWalkwayHeatmap
                    ? 'Hide walkway heatmap'
                    : 'Show walkway heatmap',
                icon: Icon(
                  _showWalkwayHeatmap
                      ? Icons.grid_on
                      : Icons.grid_off,
                  size: 20,
                  color: _showWalkwayHeatmap ? Colors.teal.shade700 : null,
                ),
                onPressed: () => setState(
                  () => _showWalkwayHeatmap = !_showWalkwayHeatmap,
                ),
                visualDensity: VisualDensity.compact,
              ),
              TextButton.icon(
                onPressed: () => _showAutoArrangeSheet(context, notifier, state),
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Auto'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              if (state.layoutTips.length > 1)
                IconButton(
                  tooltip: 'All tips',
                  icon: const Icon(Icons.list_alt, size: 20),
                  onPressed: () => _showAllTips(context, state),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAllTips(BuildContext context, RoomState state) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Layout tips', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final t in state.layoutTips)
            ListTile(
              dense: true,
              leading: Icon(
                t.severity == 'error'
                    ? Icons.error
                    : t.severity == 'info'
                        ? Icons.check_circle
                        : Icons.warning_amber,
                color: t.severity == 'error'
                    ? Colors.red
                    : t.severity == 'info'
                        ? Colors.green
                        : Colors.orange,
              ),
              title: Text(t.message),
            ),
        ],
      ),
    );
  }

  void _showLayoutAlternatives(
    BuildContext context,
    RoomNotifier notifier,
    RoomState state,
  ) {
    final alts = LayoutAlternatives.generate(
      room: state.room,
      pixelsPerFoot: state.pixelsPerFoot,
    );
    if (alts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add furniture first to compare layouts')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Layout alternatives',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Same furniture, three placement strategies. Scores use live layout rules.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 8),
              for (final alt in alts)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: alt.score >= 80
                        ? Colors.green.shade50
                        : alt.score >= 50
                            ? Colors.orange.shade50
                            : Colors.red.shade50,
                    child: Text(
                      alt.letter,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text('${alt.style.label} · score ${alt.score}'),
                  subtitle: Text(
                    alt.tips.isEmpty
                        ? alt.style.subtitle
                        : alt.tips.first.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.check_circle_outline),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.applyLayoutAlternative(alt.furniture);
                    AnalyticsService.instance.autoArrange(
                      type: 'alt_${alt.style.name}',
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Applied ${alt.letter}: ${alt.style.label} (score ${alt.score})',
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAutoArrangeSheet(
    BuildContext context,
    RoomNotifier notifier,
    RoomState state,
  ) {
    final hasFurniture = state.room.furniture.isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Arrange for space',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                hasFurniture
                    ? 'Keep your scanned furniture — suggest a more open layout '
                        '(along walls, clear walkways, less crowding).'
                    : 'No furniture on the plan yet. Scan with photos so furniture '
                        'is detected, or add from catalog, then arrange.',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (hasFurniture)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal.shade50,
                    child: Icon(Icons.auto_awesome, color: Colors.teal.shade700),
                  ),
                  title: const Text('Suggest more spacious layout'),
                  subtitle: Text(
                    'Re-place ${state.room.furniture.length} existing piece(s) — '
                    'same furniture, better spacing',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.suggestSpaciousLayout();
                    AnalyticsService.instance.autoArrange(type: 'spacious');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Suggested a more spacious layout for your furniture',
                        ),
                      ),
                    );
                  },
                ),
              if (hasFurniture)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade50,
                    child: Icon(Icons.compare, color: Colors.indigo.shade700),
                  ),
                  title: const Text('Compare layouts A / B / C'),
                  subtitle: const Text(
                    'Spacious, wall-hug, and conversation — pick best score',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showLayoutAlternatives(context, notifier, state);
                  },
                ),
              const Divider(),
              Text(
                'AI Designer (Furnisher)',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Fill the room from catalog recipes — free on-device styles',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              for (final style in DesignStyle.values)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.shade50,
                    child: Icon(Icons.auto_fix_high, color: Colors.deepPurple.shade700, size: 20),
                  ),
                  title: Text(style.label),
                  subtitle: Text(style.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.applyDesignStyle(style);
                    AnalyticsService.instance.autoArrange(type: 'design_${style.name}');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Applied AI Designer: ${style.label}')),
                    );
                  },
                ),
              const Divider(),
              Text(
                'AI Styler',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Palette + materials tips and restyle furniture layout (free on-device)',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              for (final style in DesignStyle.values)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Colors.pink.shade50,
                    child: Icon(Icons.palette, color: Colors.pink.shade700, size: 20),
                  ),
                  title: Text('Style: ${style.label}'),
                  subtitle: Text(style.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.pop(ctx);
                    final report = AiStyler.apply(
                      room: state.room,
                      pixelsPerFoot: state.pixelsPerFoot,
                      style: style,
                    );
                    notifier.applyLayoutAlternative(report.furniture);
                    AnalyticsService.instance.autoArrange(type: 'styler_${style.name}');
                    showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (c2) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: ListView(
                          children: [
                            Text('AI Styler · ${style.label}',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 8),
                            Text('Palette: ${report.palette}'),
                            Text('Materials: ${report.materials}'),
                            Text('Layout score: ${report.score}'),
                            const SizedBox(height: 8),
                            for (final tip in report.tips)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.check_circle_outline),
                                title: Text(tip),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const Divider(),
              Text(
                hasFurniture
                    ? 'Or replace with a room preset'
                    : 'Room presets (empty plan)',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              for (final type in [
                RoomLayoutType.bedroom,
                RoomLayoutType.living,
                RoomLayoutType.office,
              ])
                ListTile(
                  leading: const Icon(Icons.auto_awesome_mosaic),
                  title: Text(AutoArrange.label(type)),
                  subtitle: Text(
                    hasFurniture
                        ? 'Replaces current pieces with a ${AutoArrange.label(type).toLowerCase()} set'
                        : type == RoomLayoutType.bedroom
                            ? 'Bed, wardrobe, nightstands'
                            : type == RoomLayoutType.living
                                ? 'Sofa, table, TV, chairs'
                                : 'Desk, chair, bookshelf',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.applyPresetLayout(type);
                    AnalyticsService.instance.autoArrange(type: type.name);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Applied ${AutoArrange.label(type)}'),
                      ),
                    );
                  },
                ),
            ],
          ),
          ),
        ),
      ),
    );
  }


  Future<void> _resizeSelected(
    BuildContext context,
    RoomNotifier notifier,
    RoomState state,
  ) async {
    final id = state.selectedFurnitureId;
    if (id == null) return;
    final matches = state.room.furniture.where((f) => f.id == id);
    if (matches.isEmpty) return;
    final item = matches.first;
    final unit = state.unitSystem;
    final wCtrl = TextEditingController(
      text: LengthFormat.feetToDisplay(item.widthInFeet, unit).toStringAsFixed(1),
    );
    final lCtrl = TextEditingController(
      text: LengthFormat.feetToDisplay(item.lengthInFeet, unit).toStringAsFixed(1),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resize furniture'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: wCtrl,
              decoration: InputDecoration(
                labelText: 'Width (${unit.label})',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lCtrl,
              decoration: InputDecoration(
                labelText: 'Length / depth (${unit.label})',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true) return;
    final wDisp = double.tryParse(wCtrl.text);
    final lDisp = double.tryParse(lCtrl.text);
    if (wDisp == null || lDisp == null) return;
    notifier.resizeSelectedFurniture(
      LengthFormat.displayToFeet(wDisp, unit).clamp(0.5, 30),
      LengthFormat.displayToFeet(lDisp, unit).clamp(0.5, 30),
    );
  }

  Widget _buildModeHint(RoomState state) {
    String text;
    switch (state.currentTool) {
      case ToolMode.pan:
        text = 'Pan — drag canvas · pinch zoom';
      case ToolMode.select:
        text = state.multiSelectMode
            ? 'Multi-select — tap to add/remove · drag moves all · wall snap on release'
            : 'Select — drag · wall/edge snap · amber handle rotates 45°';
      case ToolMode.wall:
        text =
            'Wall — drag H/V; room inset from edges so left/top walls are drawable';
      case ToolMode.door:
        text = 'Door — drag along a room edge (snaps to nearest wall)';
      case ToolMode.window:
        text = 'Window — drag along a room edge (snaps to nearest wall)';
      case ToolMode.balcony:
        text = 'Balcony — free diagonal allowed (grid snap only)';
      case ToolMode.erase:
        text = 'Erase';
    }
    return Container(
      width: double.infinity,
      color: Colors.blueGrey.shade800,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _buildStatsPanel(
    BuildContext context,
    RoomState state,
    RoomNotifier notifier,
  ) {
    final totalArea = state.room.widthInFeet * state.room.lengthInFeet;
    final filledArea = state.room.furniture.fold<double>(
      0.0,
      (sum, f) => sum + (f.widthInFeet * f.lengthInFeet),
    );
    final freeArea = totalArea - filledArea;
    final isOverfilled = filledArea > totalArea;
    final unit = state.unitSystem;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      width: double.infinity,
      color: Colors.blueGrey.shade50,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 8.0,
        runSpacing: 4.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Room: ${LengthFormat.formatAreaSqFt(totalArea, unit)} '
                '(${LengthFormat.formatFeet(state.room.widthInFeet, unit)}×'
                '${LengthFormat.formatFeet(state.room.lengthInFeet, unit)})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showRoomSizeDialog(context, notifier, state),
              ),
            ],
          ),
          Text(
            'Filled: ${LengthFormat.formatAreaSqFt(filledArea, unit)}',
            style: TextStyle(
              color: isOverfilled ? Colors.red : Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Text(
            'Free: ${LengthFormat.formatAreaSqFt(freeArea, unit)}',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          SegmentedButton<UnitSystem>(
            segments: const [
              ButtonSegment(value: UnitSystem.feet, label: Text('ft')),
              ButtonSegment(value: UnitSystem.meters, label: Text('m')),
            ],
            selected: {unit},
            onSelectionChanged: (s) async {
              final u = s.first;
              notifier.setUnitSystem(u);
              await _prefs.saveUnitSystem(u);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  void _showRoomSizeDialog(
    BuildContext context,
    RoomNotifier notifier,
    RoomState state,
  ) {
    final room = state.room;
    final unit = state.unitSystem;
    final widthController = TextEditingController(
      text: LengthFormat.feetToDisplay(room.widthInFeet, unit).toStringAsFixed(1),
    );
    final lengthController = TextEditingController(
      text: LengthFormat.feetToDisplay(room.lengthInFeet, unit).toStringAsFixed(1),
    );
    final wallController = TextEditingController(
      text: LengthFormat.feetToDisplay(room.wallHeightFt, unit).toStringAsFixed(1),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Room size (${unit.label})'),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widthController,
              decoration: InputDecoration(labelText: 'Width (${unit.label})'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: lengthController,
              decoration: InputDecoration(labelText: 'Length (${unit.label})'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              key: const Key('room_wall_height'),
              controller: wallController,
              decoration: InputDecoration(
                labelText: 'Wall height (${unit.label})',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            Text(
              'Level: ${room.spaceLabel}'
              '${room.isExterior ? '' : ' · use Exterior for patio'}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('room_exterior_toggle'),
            onPressed: () {
              notifier.setExterior(!room.isExterior);
              Navigator.of(ctx).pop();
            },
            child: Text(room.isExterior ? 'Make interior' : 'Exterior patio'),
          ),
          TextButton(
            key: const Key('room_floor_up'),
            onPressed: () {
              notifier.setFloorLevel(room.floorLevel + 1);
              Navigator.of(ctx).pop();
            },
            child: const Text('Floor +1'),
          ),
          TextButton(
            key: const Key('room_shape_l'),
            onPressed: () {
              final wDisp = double.tryParse(widthController.text);
              final lDisp = double.tryParse(lengthController.text);
              final w = wDisp != null
                  ? LengthFormat.displayToFeet(wDisp, unit)
                  : room.widthInFeet;
              final l = lDisp != null
                  ? LengthFormat.displayToFeet(lDisp, unit)
                  : room.lengthInFeet;
              notifier.updateRoomSize(w, l);
              notifier.applyLShapeFloor();
              Navigator.of(ctx).pop();
            },
            child: const Text('L-shape'),
          ),
          if (room.isPolygonFloor)
            TextButton(
              key: const Key('room_shape_rect'),
              onPressed: () {
                notifier.applyRectangleFloor();
                Navigator.of(ctx).pop();
              },
              child: const Text('Rectangle'),
            ),
          TextButton(
            onPressed: () {
              final wDisp = double.tryParse(widthController.text);
              final lDisp = double.tryParse(lengthController.text);
              final hDisp = double.tryParse(wallController.text);
              final w = wDisp != null
                  ? LengthFormat.displayToFeet(wDisp, unit)
                  : room.widthInFeet;
              final l = lDisp != null
                  ? LengthFormat.displayToFeet(lDisp, unit)
                  : room.lengthInFeet;
              final h = hDisp != null
                  ? LengthFormat.displayToFeet(hDisp, unit)
                  : room.wallHeightFt;
              notifier.updateRoomSize(w, l);
              notifier.setWallHeightFt(h);
              Navigator.of(ctx).pop();
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    RoomState state,
    RoomNotifier notifier,
  ) {
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.pan_tool_alt,
              label: 'Pan',
              isActive: state.currentTool == ToolMode.pan,
              onTap: () => notifier.setTool(ToolMode.pan),
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.near_me,
              label: 'Select',
              isActive: state.currentTool == ToolMode.select && !state.multiSelectMode,
              onTap: () {
                notifier.setTool(ToolMode.select);
                notifier.setMultiSelectMode(false);
              },
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.select_all,
              label: 'Multi',
              isActive: state.currentTool == ToolMode.select && state.multiSelectMode,
              onTap: () {
                notifier.setTool(ToolMode.select);
                notifier.setMultiSelectMode(true);
              },
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.edit,
              label: 'Wall',
              isActive: state.currentTool == ToolMode.wall,
              onTap: () => notifier.setTool(ToolMode.wall),
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.door_front_door,
              label: 'Door',
              isActive: state.currentTool == ToolMode.door,
              onTap: () => notifier.setTool(ToolMode.door),
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.window,
              label: 'Window',
              isActive: state.currentTool == ToolMode.window,
              onTap: () => notifier.setTool(ToolMode.window),
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.deck,
              label: 'Balcony',
              isActive: state.currentTool == ToolMode.balcony,
              onTap: () => notifier.setTool(ToolMode.balcony),
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.chair,
              label: 'Furniture',
              isActive: false,
              onTap: () => _openCatalog(context, state, notifier),
            ),
          ],
        ),
      ),
    );
  }

  void _openCatalog(
    BuildContext context,
    RoomState state,
    RoomNotifier notifier,
  ) {
    FurnitureCatalogSheet.show(
      context,
      unitSystem: state.unitSystem,
      onAdd: (type, w, l, {catalogId}) {
        // Place near center of room outline in canvas coords.
        final cx = (state.room.widthInFeet * state.pixelsPerFoot) / 2;
        final cy = (state.room.lengthInFeet * state.pixelsPerFoot) / 2;
        notifier.addFurniture(type, Offset(cx, cy), w, l, catalogId: catalogId);
      },
    );
  }

  void _confirmClear(BuildContext context, RoomNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Room?'),
        content: const Text(
          'Clear all walls, doors, windows, and furniture?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              notifier.clearRoom();
              Navigator.of(ctx).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    RoomNotifier notifier,
    RoomModel room,
  ) {
    final controller = TextEditingController(text: room.name);
    final notesCtrl = TextEditingController(text: room.notes ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Plan details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Room name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('room_notes_field'),
                controller: notesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Client, address, style goals…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              notifier.updateName(controller.text);
              notifier.updateNotes(notesCtrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.grey.shade400,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? Colors.blue : Colors.black87, size: 20),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.blue : Colors.black87,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
