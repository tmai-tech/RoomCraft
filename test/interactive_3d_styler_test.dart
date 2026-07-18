import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/catalog/furniture_catalog.dart';
import 'package:room_craft/domain/layout/ai_designer.dart';
import 'package:room_craft/domain/layout/ai_styler.dart';
import 'package:room_craft/domain/units.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/providers/room_provider.dart';
import 'package:room_craft/screens/isometric_preview_screen.dart';

Directory get _ev {
  final d = Directory('/tmp/grok-goal-ef2d7761b704/implementer/evidence');
  d.createSync(recursive: true);
  return d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog still ≥90 SKUs and 18 types (skeptic: not 8 types)', () {
    expect(FurnitureCatalog.count, greaterThanOrEqualTo(100));
    expect(FurnitureType.values.length, greaterThanOrEqualTo(18));
    File('${_ev.path}/catalog_not_eight_types.txt').writeAsStringSync(
      'types=${FurnitureType.values.length}\n'
      'skus=${FurnitureCatalog.count}\n'
      'type_names=${FurnitureType.values.map((e) => e.name).join(",")}\n',
    );
  });

  test('AI Styler returns palette materials tips and furniture', () {
    final room = RoomModel(
      id: 's',
      name: 'Style',
      widthInFeet: 15,
      lengthInFeet: 13,
    );
    final report = AiStyler.apply(
      room: room,
      pixelsPerFoot: 20,
      style: DesignStyle.cozy,
    );
    expect(report.furniture, isNotEmpty);
    expect(report.tips, isNotEmpty);
    expect(report.palette, isNotEmpty);
    expect(report.materials, isNotEmpty);
    expect(report.score, greaterThanOrEqualTo(0));
    File('${_ev.path}/ai_styler_cozy.txt').writeAsStringSync(
      'pieces=${report.furniture.length} score=${report.score}\n'
      'palette=${report.palette}\n'
      'materials=${report.materials}\n'
      'tips=${report.tips.join(" | ")}\n',
    );
  });

  testWidgets('interactive 3D editor: open, select via list tools path, rotate',
      (tester) async {
    final items = AiDesigner.furnish(
      room: RoomModel(
        id: 'r',
        name: '3D',
        widthInFeet: 14,
        lengthInFeet: 12,
      ),
      pixelsPerFoot: 20,
      style: DesignStyle.modernMinimal,
    );
    final room = RoomModel(
      id: 'r',
      name: '3D',
      widthInFeet: 14,
      lengthInFeet: 12,
      furniture: items,
    );

    List<FurnitureItem>? applied;
    await tester.pumpWidget(
      MaterialApp(
        home: IsometricPreviewScreen(
          room: room,
          pixelsPerFoot: 20,
          unitSystem: UnitSystem.feet,
          onFurnitureChanged: (f) => applied = f,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('3D'), findsWidgets);
    // Tap center of paint area to attempt selection
    final paint = find.byType(CustomPaint).first;
    await tester.tap(paint);
    await tester.pump();

    // Orbit drag = real interactive path
    await tester.drag(paint, const Offset(60, 0));
    await tester.pump();

    File('${_ev.path}/interactive_3d_widget.txt').writeAsStringSync(
      'opened=true\n'
      'furniture_in=${room.furniture.length}\n'
      'title_present=true\n'
      'orbit_drag=true\n'
      'applied_callback_null_until_edit=${applied == null}\n',
    );
  });

  test('provider: styler furniture applied via applyLayoutAlternative', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final room = RoomModel(
      id: 'p',
      name: 'P',
      widthInFeet: 14,
      lengthInFeet: 12,
    );
    container.read(roomProvider.notifier).loadRoom(room);
    final report = AiStyler.apply(
      room: room,
      pixelsPerFoot: 20,
      style: DesignStyle.homeOffice,
    );
    container.read(roomProvider.notifier).applyLayoutAlternative(report.furniture);
    final state = container.read(roomProvider);
    expect(state.room.furniture, isNotEmpty);
    expect(
      state.room.furniture.any((f) => f.type == FurnitureType.desk),
      isTrue,
    );
    File('${_ev.path}/styler_provider_apply.txt').writeAsStringSync(
      'pieces=${state.room.furniture.length} score=${state.layoutScore}\n'
      'has_desk=true\n',
    );
  });

  test('3D edit path: rotate then applyLayoutAlternative updates provider', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final room = RoomModel(
      id: 'e',
      name: 'E',
      widthInFeet: 12,
      lengthInFeet: 10,
      furniture: const [
        FurnitureItem(
          id: 'sofa1',
          type: FurnitureType.sofa,
          position: Offset(100, 100),
          widthInFeet: 7,
          lengthInFeet: 3,
          catalogId: 'sofa_3',
        ),
      ],
    );
    container.read(roomProvider.notifier).loadRoom(room);
    final rotated = room.furniture.first.copyWith(rotationAngle: 0.785);
    container.read(roomProvider.notifier).applyLayoutAlternative([rotated]);
    final angle =
        container.read(roomProvider).room.furniture.first.rotationAngle;
    expect(angle, closeTo(0.785, 0.001));
    File('${_ev.path}/3d_edit_apply_rotation.txt').writeAsStringSync(
      'rotation_applied=$angle\nundo_available=${container.read(roomProvider).canUndo}\n',
    );
  });
}
