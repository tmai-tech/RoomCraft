import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/layout/auto_arrange.dart';
import '../domain/units.dart';
import '../painters/blueprint_painter.dart';
import '../painters/furniture_painter.dart';
import '../providers/room_provider.dart';
import '../services/export_service.dart';
import '../services/prefs_service.dart';
import '../services/storage_service.dart';
import '../widgets/furniture_catalog_sheet.dart';

class BlueprintScreen extends ConsumerStatefulWidget {
  const BlueprintScreen({super.key});

  @override
  ConsumerState<BlueprintScreen> createState() => _BlueprintScreenState();
}

class _BlueprintScreenState extends ConsumerState<BlueprintScreen> {
  final TransformationController _transformController = TransformationController();
  final PrefsService _prefs = PrefsService();

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
            roomState.selectedFurnitureId == null);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          StorageService().saveRoom(roomState.room);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: InkWell(
            onTap: () =>
                _showRenameDialog(context, roomNotifier, roomState.room.name),
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
              icon: const Icon(Icons.save),
              onPressed: () async {
                await StorageService().saveRoom(roomState.room);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Blueprint Saved Locally')),
                  );
                }
              },
              tooltip: 'Save',
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export PNG',
              onPressed: () async {
                try {
                  await ExportService.sharePng(
                    roomState.room,
                    pixelsPerFoot: roomState.pixelsPerFoot,
                    unitSystem: roomState.unitSystem,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $e')),
                    );
                  }
                }
              },
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
            Expanded(
              child: ColoredBox(
                color: Colors.grey.shade100,
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.4,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  panEnabled: panEnabled,
                  scaleEnabled: true,
                  child: SizedBox(
                    width: 1200,
                    height: 1200,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        if (roomState.isDrawTool) {
                          roomNotifier.startStroke(details.localPosition);
                        } else if (roomState.currentTool == ToolMode.select) {
                          roomNotifier.selectFurnitureAt(details.localPosition);
                        }
                      },
                      onPanUpdate: (details) {
                        if (roomState.isDrawTool) {
                          roomNotifier.updateStroke(details.localPosition);
                        } else if (roomState.currentTool == ToolMode.select &&
                            roomState.selectedFurnitureId != null) {
                          roomNotifier.updateFurniturePosition(details.delta);
                        }
                      },
                      onPanEnd: (_) {
                        if (roomState.isDrawTool) {
                          roomNotifier.endStroke();
                        } else if (roomState.currentTool == ToolMode.select) {
                          roomNotifier.endFurnitureDrag();
                        }
                      },
                      child: CustomPaint(
                        size: const Size(1200, 1200),
                        painter: BlueprintPainter(
                          room: roomState.room,
                          currentStroke: roomState.currentStroke,
                          pixelsPerFoot: roomState.pixelsPerFoot,
                          unitSystem: roomState.unitSystem,
                        ),
                        foregroundPainter: FurniturePainter(
                          furniture: roomState.room.furniture,
                          selectedId: roomState.selectedFurnitureId,
                          pixelsPerFoot: roomState.pixelsPerFoot,
                          unitSystem: roomState.unitSystem,
                          collisionIds: roomState.collisionIds,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: roomState.selectedFurnitureId != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'rotate45FAB',
                    tooltip: 'Rotate 45°',
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
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'resizeFAB',
                    tooltip: 'Resize',
                    onPressed: () => _resizeSelected(context, roomNotifier, roomState),
                    child: const Icon(Icons.photo_size_select_small),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'deleteFAB',
                    backgroundColor: Colors.red.shade100,
                    tooltip: 'Delete',
                    onPressed: () => roomNotifier.deleteSelectedFurniture(),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                ],
              )
            : null,
      ),
    );
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
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tip,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
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

  void _showAutoArrangeSheet(
    BuildContext context,
    RoomNotifier notifier,
    RoomState state,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Auto-arrange', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text(
                'Places furniture with wall alignment and collision avoidance.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final type in [
                RoomLayoutType.bedroom,
                RoomLayoutType.living,
                RoomLayoutType.office,
              ])
                ListTile(
                  leading: const Icon(Icons.auto_awesome_mosaic),
                  title: Text(AutoArrange.label(type)),
                  subtitle: Text(
                    type == RoomLayoutType.bedroom
                        ? 'Bed, wardrobe, nightstands'
                        : type == RoomLayoutType.living
                            ? 'Sofa, table, TV, chairs'
                            : 'Desk, chair, bookshelf',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.autoArrange(type: type);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Arranged as ${AutoArrange.label(type)}'),
                      ),
                    );
                  },
                ),
              if (state.room.furniture.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.reorder),
                  title: const Text('Re-flow current furniture'),
                  subtitle: const Text('Keep items, find better positions'),
                  onTap: () {
                    Navigator.pop(ctx);
                    notifier.autoArrange(reflowExisting: true);
                  },
                ),
            ],
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
        text = 'Select — drag furniture · ends snap to grid · rotate FAB = 45°';
      case ToolMode.wall:
        text = 'Wall — drag; snaps horizontal/vertical';
      case ToolMode.door:
        text = 'Door — drag along wall line';
      case ToolMode.window:
        text = 'Window — drag along wall line';
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Room size (${unit.label})'),
        content: Column(
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
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
              isActive: state.currentTool == ToolMode.select,
              onTap: () => notifier.setTool(ToolMode.select),
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
      onAdd: (type, w, l) {
        // Place near center of room outline in canvas coords.
        final cx = (state.room.widthInFeet * state.pixelsPerFoot) / 2;
        final cy = (state.room.lengthInFeet * state.pixelsPerFoot) / 2;
        notifier.addFurniture(type, Offset(cx, cy), w, l);
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
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Blueprint'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Room Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              notifier.updateName(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
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
