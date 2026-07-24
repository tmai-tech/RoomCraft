import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:room_craft/domain/layout/blueprint_safety.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/models/stroke_model.dart';
import 'package:room_craft/providers/room_provider.dart';
import 'package:room_craft/screens/blueprint_screen.dart';

void main() {
  test('+134 sanitizeRoom injects closed perimeter when walls missing', () {
    final open = RoomModel(
      id: 'open',
      name: 'open',
      widthInFeet: 14,
      lengthInFeet: 12,
      strokes: [
        // Only one partial wall (feedback 225fb5de class)
        StrokeModel(
          id: 'w1',
          type: StrokeType.wall,
          points: const [Offset(0, 0), Offset(100, 0)],
        ),
        StrokeModel(
          id: 'd1',
          type: StrokeType.door,
          points: const [Offset(40, 0), Offset(80, 0)],
        ),
      ],
      furniture: const [],
    );
    final s = BlueprintSafety.sanitizeRoom(open);
    expect(s.strokes.where((x) => x.type == StrokeType.wall).length, 4);
    // Door opening preserved
    expect(s.strokes.any((x) => x.type == StrokeType.door), isTrue);
  });

  test('+113 sanitizeRoom fixes NaN furniture and zero size', () {
    final bad = RoomModel(
      id: 'x',
      name: 'bad',
      widthInFeet: double.nan,
      lengthInFeet: -3,
      furniture: [
        FurnitureItem(
          id: '1',
          type: FurnitureType.table,
          position: const Offset(double.nan, double.infinity),
          widthInFeet: 0,
          lengthInFeet: double.nan,
        ),
      ],
      strokes: [
        StrokeModel(
          id: 's',
          type: StrokeType.door,
          points: const [Offset(double.nan, 0), Offset(0, 1)],
        ),
      ],
    );
    final s = BlueprintSafety.sanitizeRoom(bad);
    expect(s.widthInFeet, greaterThan(0));
    expect(s.lengthInFeet, greaterThan(0));
    expect(s.furniture, isNotEmpty);
    expect(s.furniture.first.position.dx.isFinite, isTrue);
    expect(s.furniture.first.widthInFeet, greaterThan(0));
  });

  test('+113 resolveDoorFurnitureBlocks moves table off door', () {
    // Door on west wall y=1.2–4.0 at x=0; table right in front
    const pxf = 20.0;
    final room = RoomModel(
      id: 'r',
      name: 'study',
      widthInFeet: 20,
      lengthInFeet: 17,
      strokes: [
        StrokeModel(
          id: 'd1',
          type: StrokeType.door,
          points: [
            const Offset(0, 1.2 * pxf),
            const Offset(0, 4.0 * pxf),
          ],
        ),
      ],
      furniture: [
        FurnitureItem(
          id: 't',
          type: FurnitureType.table,
          // Center near door mid (~2.6 ft along west)
          position: Offset(1.5 * pxf, 2.6 * pxf),
          widthInFeet: 4,
          lengthInFeet: 2,
          rotationAngle: 1.57,
        ),
      ],
    );
    expect(BlueprintSafety.furnitureBlocksDoor(room, pxf), isTrue);
    final fixed = BlueprintSafety.resolveDoorFurnitureBlocks(room, pxf);
    expect(BlueprintSafety.furnitureBlocksDoor(fixed, pxf), isFalse);
    // Table moved away from door
    expect(
      (fixed.furniture.first.position - room.furniture.first.position).distance,
      greaterThan(5),
    );
  });

  test('+113 safePixelsPerFoot never zero', () {
    expect(BlueprintSafety.safePixelsPerFoot(0), greaterThan(0));
    expect(BlueprintSafety.safePixelsPerFoot(double.nan), greaterThan(0));
    expect(BlueprintSafety.safePixelsPerFoot(-1), greaterThan(0));
    expect(BlueprintSafety.safePixelsPerFoot(20), 20);
  });

  testWidgets('+113 BlueprintScreen opens for manual room without crash',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(roomProvider.notifier).beginManualRoom(12, 14);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BlueprintScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BlueprintScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('+113 BlueprintScreen opens for gold scan without crash',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);
    final cleaned = PhotoTrueLayout.cleanStudyDeskAndDoors(gold);
    final ed = ScanParser.toEditor(cleaned, 20);
    container.read(roomProvider.notifier).initFromScan(
          ed.width,
          ed.length,
          ed.strokes,
          ed.furniture,
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: BlueprintScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BlueprintScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Door clearances applied
    final room = container.read(roomProvider).room;
    expect(
      BlueprintSafety.furnitureBlocksDoor(room, 20),
      isFalse,
    );
  });

  test('+113 beginManualRoom sets size and wall tool', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(roomProvider.notifier).beginManualRoom(18, 16);
    final s = container.read(roomProvider);
    expect(s.room.widthInFeet, 18);
    expect(s.room.lengthInFeet, 16);
    expect(s.currentTool, ToolMode.wall);
    expect(s.canUndo, isFalse);
  });
}
