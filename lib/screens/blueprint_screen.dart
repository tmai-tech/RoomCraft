import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/room_provider.dart';
import '../painters/blueprint_painter.dart';
import '../painters/furniture_painter.dart';
import '../models/furniture_item.dart';
import '../models/room_model.dart';
import '../services/storage_service.dart';

class BlueprintScreen extends ConsumerWidget {
  const BlueprintScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomState = ref.watch(roomProvider);
    final roomNotifier = ref.read(roomProvider.notifier);

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
            onTap: () => _showRenameDialog(context, roomNotifier, roomState.room.name),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(roomState.room.name),
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
              icon: const Icon(Icons.undo),
              onPressed: () => roomNotifier.undo(),
              tooltip: 'Undo',
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
          _buildStatsPanel(context, roomState, roomNotifier),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              panEnabled: roomState.currentTool == ToolMode.select, 
              scaleEnabled: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onPanStart: (details) {
                      if (roomState.currentTool != ToolMode.select) {
                        roomNotifier.startStroke(details.localPosition);
                      } else {
                        roomNotifier.selectFurnitureAt(details.localPosition);
                      }
                    },
                    onPanUpdate: (details) {
                      if (roomState.currentTool != ToolMode.select) {
                        roomNotifier.updateStroke(details.localPosition);
                      } else if (roomState.selectedFurnitureId != null) {
                        roomNotifier.updateFurniturePosition(details.delta);
                      }
                    },
                    onPanEnd: (details) {
                      if (roomState.currentTool != ToolMode.select) {
                        roomNotifier.endStroke();
                      }
                    },
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: BlueprintPainter(
                        room: roomState.room,
                        currentStroke: roomState.currentStroke,
                        pixelsPerFoot: roomState.pixelsPerFoot,
                      ),
                      foregroundPainter: FurniturePainter(
                        furniture: roomState.room.furniture,
                        selectedId: roomState.selectedFurnitureId,
                        pixelsPerFoot: roomState.pixelsPerFoot,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: roomState.selectedFurnitureId != null 
        ? Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FloatingActionButton(
                heroTag: 'rotateFAB',
                onPressed: () => roomNotifier.rotateSelectedFurniture(),
                child: const Icon(Icons.rotate_right),
              ),
              const SizedBox(height: 8),
              FloatingActionButton(
                heroTag: 'deleteFAB',
                backgroundColor: Colors.red.shade100,
                onPressed: () => roomNotifier.deleteSelectedFurniture(),
                child: const Icon(Icons.delete, color: Colors.red),
              ),
            ],
          ) 
        : null,
      ),
    );
  }

  Widget _buildStatsPanel(BuildContext context, RoomState state, RoomNotifier notifier) {
    final totalArea = state.room.widthInFeet * state.room.lengthInFeet;
    final filledArea = state.room.furniture.fold(0.0, (sum, f) => sum + (f.widthInFeet * f.lengthInFeet));
    final freeArea = totalArea - filledArea;
    final bool isOverfilled = filledArea > totalArea;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              Text('Room: ${totalArea.toStringAsFixed(1)} sq ft (${state.room.widthInFeet}x${state.room.lengthInFeet})', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showRoomSizeDialog(context, notifier, state.room),
              ),
            ],
          ),
          Text('Filled: ${filledArea.toStringAsFixed(1)} sq ft', style: TextStyle(color: isOverfilled ? Colors.red : Colors.black, fontWeight: FontWeight.bold)),
          Text('Free: ${freeArea.toStringAsFixed(1)} sq ft', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showRoomSizeDialog(BuildContext context, RoomNotifier notifier, RoomModel room) {
    final widthController = TextEditingController(text: room.widthInFeet.toString());
    final lengthController = TextEditingController(text: room.lengthInFeet.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Room Dimensions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widthController,
              decoration: const InputDecoration(labelText: 'Width (feet)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: lengthController,
              decoration: const InputDecoration(labelText: 'Length (feet)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final w = double.tryParse(widthController.text) ?? room.widthInFeet;
              final l = double.tryParse(lengthController.text) ?? room.lengthInFeet;
              notifier.updateRoomSize(w, l);
              Navigator.of(ctx).pop();
            },
            child: const Text('Update'),
          ),
        ],
      )
    );
  }

  Widget _buildToolbar(BuildContext context, RoomState state, RoomNotifier notifier) {
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ToolButton(
              icon: Icons.pan_tool,
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
              label: 'Add Furniture',
              isActive: false,
              onTap: () => _showFurnitureDialog(context, notifier),
            ),
          ],
        ),
      ),
    );
  }

  void _showFurnitureDialog(BuildContext context, RoomNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Furniture'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: FurnitureType.values.map((type) {
              return InkWell(
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showFurnitureSizeDialog(context, notifier, type);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Center(
                    child: Text(
                      type.name.toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      )
    );
  }

  void _showFurnitureSizeDialog(BuildContext context, RoomNotifier notifier, FurnitureType type) {
    double width = 3.0;
    double length = 3.0;
    if (type == FurnitureType.bed) { width = 5.0; length = 6.5; }
    if (type == FurnitureType.sofa) { width = 6.0; length = 3.0; }
    if (type == FurnitureType.table) { width = 4.0; length = 4.0; }
    if (type == FurnitureType.wardrobe) { width = 4.0; length = 2.0; }

    final widthController = TextEditingController(text: width.toString());
    final lengthController = TextEditingController(text: length.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set ${type.name.toUpperCase()} Dimensions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widthController,
              decoration: const InputDecoration(labelText: 'Width (feet)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: lengthController,
              decoration: const InputDecoration(labelText: 'Length (feet)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final w = double.tryParse(widthController.text) ?? width;
              final l = double.tryParse(lengthController.text) ?? length;
              notifier.addFurniture(type, const Offset(200, 200), w, l);
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      )
    );
  }

  void _confirmClear(BuildContext context, RoomNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Room?'),
        content: const Text('Are you sure you want to clear all walls, doors, windows, and furniture?'),
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
      )
    );
  }

  void _showRenameDialog(BuildContext context, RoomNotifier notifier, String currentName) {
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.grey.shade400,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? Colors.blue : Colors.black87),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.blue : Colors.black87,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
