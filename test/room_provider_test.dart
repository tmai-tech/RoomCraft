import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/providers/room_provider.dart';

void main() {
  test('pan and select tools toggle canvas pan flag', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(roomProvider.notifier);
    expect(container.read(roomProvider).currentTool, ToolMode.select);

    notifier.setTool(ToolMode.pan);
    expect(container.read(roomProvider).canvasPanEnabled, isTrue);

    notifier.setTool(ToolMode.wall);
    expect(container.read(roomProvider).isDrawTool, isTrue);
    expect(container.read(roomProvider).canvasPanEnabled, isFalse);
  });

  test('add furniture selects it and switches to select tool', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(roomProvider.notifier);

    notifier.addFurniture(FurnitureType.bed, const Offset(100, 100), 5, 6.5);
    final state = container.read(roomProvider);
    expect(state.room.furniture.length, 1);
    expect(state.selectedFurnitureId, isNotNull);
    expect(state.currentTool, ToolMode.select);
  });

  test('draw wall stroke commits on end', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(roomProvider.notifier);

    notifier.setTool(ToolMode.wall);
    notifier.startStroke(const Offset(0, 0));
    notifier.updateStroke(const Offset(40, 0));
    notifier.endStroke();

    expect(container.read(roomProvider).room.strokes.length, 1);
    expect(container.read(roomProvider).currentStroke, isNull);
  });
}
