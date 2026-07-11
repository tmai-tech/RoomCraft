import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/providers/room_provider.dart';

void main() {
  test('undo/redo furniture add', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(roomProvider.notifier);

    n.addFurniture(FurnitureType.chair, const Offset(50, 50), 2, 2);
    expect(container.read(roomProvider).room.furniture.length, 1);
    expect(container.read(roomProvider).canUndo, isTrue);

    n.undo();
    expect(container.read(roomProvider).room.furniture, isEmpty);
    expect(container.read(roomProvider).canRedo, isTrue);

    n.redo();
    expect(container.read(roomProvider).room.furniture.length, 1);
  });

  test('orthogonal wall snap is H or V', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(roomProvider.notifier);

    n.setTool(ToolMode.wall);
    n.startStroke(const Offset(0, 0));
    n.updateStroke(const Offset(80, 20)); // more X than Y → horizontal
    n.endStroke();

    final stroke = container.read(roomProvider).room.strokes.single;
    expect(stroke.points.first.dy, stroke.points.last.dy);
  });

  test('rotate snaps by 45 degrees', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(roomProvider.notifier);

    n.addFurniture(FurnitureType.sofa, const Offset(100, 100), 6, 3);
    n.rotateSelectedFurniture(degrees: 45);
    final angle = container.read(roomProvider).room.furniture.single.rotationAngle;
    // ~ pi/4
    expect(angle, closeTo(0.785398, 0.01));
  });
}
