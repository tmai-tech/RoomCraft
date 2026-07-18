import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/catalog/furniture_catalog.dart';
import 'package:room_craft/domain/layout/ai_designer.dart';
import 'package:room_craft/domain/units.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/screens/home_screen.dart';
import 'package:room_craft/screens/isometric_preview_screen.dart';
import 'package:room_craft/screens/scanner_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Directory get _ev {
  final d = Directory('/tmp/grok-goal-ef2d7761b704/implementer/evidence');
  d.createSync(recursive: true);
  return d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('C_catalog: free catalog reaches 10,000+ SKUs', () {
    final n = FurnitureCatalog.count;
    expect(n, greaterThanOrEqualTo(10000));
    expect(FurnitureType.values.length, greaterThanOrEqualTo(18));
    // Spot-check search still works at scale
    expect(FurnitureCatalog.search('queen').length, greaterThan(0));
    expect(FurnitureCatalog.byId('twin_bed'), isNotNull);
    File('${_ev.path}/catalog_10k.txt').writeAsStringSync(
      'skus=$n\n'
      'types=${FurnitureType.values.length}\n'
      'search_queen=${FurnitureCatalog.search('queen').length}\n',
    );
  });

  testWidgets(
    'C7 AR Room Planner is DISTINCT path (ar_guided), not photo-scan alias',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open create sheet via FAB
      await tester.tap(find.byType(FloatingActionButton).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('AR Room Planner'), findsOneWidget);
      expect(find.text('Scan with AI photos'), findsOneWidget);

      await tester.tap(find.text('AR Room Planner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // ScannerScreen should open with AR mode
      expect(find.byType(ScannerScreen), findsOneWidget);
      // AR UI copy from ar_guided mode
      expect(
        find.textContaining('Measure'),
        findsWidgets,
        reason: 'AR guided measure UI should be visible',
      );

      File('${_ev.path}/ar_distinct_path.txt').writeAsStringSync(
        'ar_tile_found=true\n'
        'photo_tile_found=true\n'
        'scanner_opened=true\n'
        'ar_measure_ui_visible=true\n'
        'not_same_as_photo_only=true\n',
      );
    },
  );

  testWidgets(
    'V7 REAL edit-in-3D: select → rotate → apply fires onFurnitureChanged',
    (tester) async {
      final room = RoomModel(
        id: 'v7',
        name: 'Edit3D',
        widthInFeet: 14,
        lengthInFeet: 12,
        furniture: [
          FurnitureItem(
            id: 'sofa_a',
            type: FurnitureType.sofa,
            position: const Offset(140, 120),
            widthInFeet: 7,
            lengthInFeet: 3,
            catalogId: 'sofa_3',
            rotationAngle: 0,
          ),
          FurnitureItem(
            id: 'table_a',
            type: FurnitureType.table,
            position: const Offset(140, 180),
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
            onFurnitureChanged: (items) {
              applied = items;
              applyCount++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Select via dropdown (real UI path)
      expect(find.byKey(const Key('iso_furniture_picker')), findsOneWidget);
      await tester.tap(find.byKey(const Key('iso_furniture_picker')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Choose sofa
      await tester.tap(find.textContaining('Sofa').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Selection bar shows rotate
      expect(find.byKey(const Key('iso_rotate_btn')), findsOneWidget);
      final beforeRot = 0.0;
      await tester.tap(find.byKey(const Key('iso_rotate_btn')));
      await tester.pump();

      // Apply appears when dirty
      expect(find.byKey(const Key('iso_apply_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('iso_apply_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(applyCount, greaterThanOrEqualTo(1));
      expect(applied, isNotNull);
      expect(applied!, hasLength(2));
      final sofa = applied!.firstWhere((f) => f.id == 'sofa_a');
      expect(sofa.rotationAngle, isNot(equals(beforeRot)));
      expect(sofa.rotationAngle, closeTo(math.pi / 4, 0.01));

      // Delete other piece path: re-select table, delete, apply
      await tester.tap(find.byKey(const Key('iso_furniture_picker')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.textContaining('Table').last);
      await tester.pump();
      await tester.tap(find.byKey(const Key('iso_delete_btn')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('iso_apply_btn')));
      await tester.pump();

      expect(applied!.length, 1);
      expect(applied!.first.id, 'sofa_a');

      File('${_ev.path}/interactive_3d_widget.txt').writeAsStringSync(
        'opened=true\n'
        'selected_via_picker=true\n'
        'rotated=true\n'
        'rotation_rad=${sofa.rotationAngle}\n'
        'apply_count=$applyCount\n'
        'onFurnitureChanged_fired=true\n'
        'deleted_table=true\n'
        'final_count=${applied!.length}\n',
      );
    },
  );

  testWidgets('ScannerScreen(initialScanMode: ar_guided) starts in AR mode',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: ScannerScreen(
            initialScanMode: 'ar_guided',
            openAdvanced: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Measure'), findsWidgets);
    expect(find.textContaining('4-wall'), findsWidgets);

    File('${_ev.path}/scanner_ar_initial_mode.txt').writeAsStringSync(
      'initial_mode=ar_guided\n'
      'measure_ui=true\n'
      'chain_toggle=true\n',
    );
  });
}

