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

  test('catalog still ≥10000 SKUs and 18 types (skeptic: not 8 types)', () {
    expect(FurnitureCatalog.count, greaterThanOrEqualTo(10000));
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

  testWidgets(
    'V7 REAL path in interactive_3d_styler: select+rotate+apply+delete',
    (tester) async {
      // Fixed furniture (not only AI) so selection is deterministic
      final room = RoomModel(
        id: 'r',
        name: '3D',
        widthInFeet: 14,
        lengthInFeet: 12,
        furniture: const [
          FurnitureItem(
            id: 'sofa_a',
            type: FurnitureType.sofa,
            position: Offset(140, 120),
            widthInFeet: 7,
            lengthInFeet: 3,
            catalogId: 'sofa_3',
          ),
          FurnitureItem(
            id: 'table_a',
            type: FurnitureType.table,
            position: Offset(140, 180),
            widthInFeet: 3.5,
            lengthInFeet: 2,
            catalogId: 'coffee_table',
          ),
        ],
      );

      List<FurnitureItem>? applied;
      var applyCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: IsometricPreviewScreen(
            room: room,
            pixelsPerFoot: 20,
            unitSystem: UnitSystem.feet,
            onFurnitureChanged: (f) {
              applied = f;
              applyCount++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('3D'), findsWidgets);
      expect(find.byKey(const Key('iso_furniture_picker')), findsOneWidget);

      // Select sofa via dropdown
      await tester.tap(find.byKey(const Key('iso_furniture_picker')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('Sofa').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('iso_rotate_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('iso_rotate_btn')));
      await tester.pump();

      expect(find.byKey(const Key('iso_apply_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('iso_apply_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(applyCount, greaterThanOrEqualTo(1));
      expect(applied, isNotNull);
      final sofa = applied!.firstWhere((f) => f.id == 'sofa_a');
      expect(sofa.rotationAngle, closeTo(0.7853981633974483, 0.02));

      // Delete table
      await tester.tap(find.byKey(const Key('iso_furniture_picker')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('Table').last);
      await tester.pump();
      await tester.tap(find.byKey(const Key('iso_delete_btn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('iso_apply_btn')));
      await tester.pump();

      expect(applied!.length, 1);
      expect(applied!.first.id, 'sofa_a');

      // Primary V7 evidence file (what verification plan requires)
      File('${_ev.path}/interactive_3d_widget.txt').writeAsStringSync(
        'opened=true\n'
        'selected_via_picker=true\n'
        'rotated=true\n'
        'rotation_rad=${sofa.rotationAngle}\n'
        'apply_count=$applyCount\n'
        'onFurnitureChanged_fired=true\n'
        'deleted_table=true\n'
        'final_count=${applied!.length}\n'
        'source_test=interactive_3d_styler_test.dart\n',
      );
    },
  );

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
