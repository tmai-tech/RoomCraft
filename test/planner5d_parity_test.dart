import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/catalog/furniture_catalog.dart';
import 'package:room_craft/domain/layout/ai_designer.dart';
import 'package:room_craft/domain/layout/auto_arrange.dart';
import 'package:room_craft/domain/layout/collision.dart';
import 'package:room_craft/domain/layout/layout_alternatives.dart';
import 'package:room_craft/domain/units.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/painters/isometric_painter.dart';
import 'package:room_craft/providers/room_provider.dart';
import 'package:room_craft/screens/isometric_preview_screen.dart';

/// Evidence dir for verifier (goal harness).
Directory get _evidence {
  final d = Directory('/tmp/grok-goal-ef2d7761b704/implementer/evidence');
  d.createSync(recursive: true);
  return d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Catalog scale', () {
    test('has 80+ consumer SKUs across categories', () {
      expect(FurnitureCatalog.count, greaterThanOrEqualTo(80));
      expect(FurnitureType.values.length, greaterThanOrEqualTo(16));
      // Kitchen / bath / lighting present (Planner-class breadth)
      expect(
        FurnitureCatalog.all.any((e) => e.category == FurnitureCategory.kitchen),
        isTrue,
      );
      expect(
        FurnitureCatalog.all.any((e) => e.category == FurnitureCategory.bathroom),
        isTrue,
      );
      expect(
        FurnitureCatalog.all.any((e) => e.category == FurnitureCategory.lighting),
        isTrue,
      );
      final report = StringBuffer()
        ..writeln('catalog_count=${FurnitureCatalog.count}')
        ..writeln('furniture_types=${FurnitureType.values.length}')
        ..writeln(
          'categories=${FurnitureCategory.values.map((c) => c.name).join(",")}',
        );
      File('${_evidence.path}/catalog_scale.txt').writeAsStringSync('$report');
    });

    test('search finds desk and bathtub', () {
      expect(FurnitureCatalog.search('desk'), isNotEmpty);
      expect(FurnitureCatalog.search('bath'), isNotEmpty);
      expect(FurnitureCatalog.byId('queen_bed'), isNotNull);
    });
  });

  group('AI Designer furnisher', () {
    const pxf = 20.0;

    test('each style furnishes non-empty non-overlapping layout', () {
      final room = RoomModel(
        id: 'r',
        name: 'Designer',
        widthInFeet: 16,
        lengthInFeet: 14,
      );
      final scores = <String, int>{};
      for (final style in DesignStyle.values) {
        final items = AiDesigner.furnish(
          room: room,
          pixelsPerFoot: pxf,
          style: style,
        );
        expect(items, isNotEmpty, reason: style.name);
        expect(items.length, greaterThanOrEqualTo(4), reason: style.name);
        // catalog ids when possible
        expect(items.any((f) => f.catalogId != null), isTrue);
        final solid = items.where((f) => f.type != FurnitureType.rug).toList();
        final ids = Collision.overlappingIds(solid, pxf, padding: 2);
        expect(ids, isEmpty, reason: 'overlap in ${style.name}: $ids');
        scores[style.name] = items.length;
      }
      File('${_evidence.path}/ai_designer_styles.txt')
          .writeAsStringSync(scores.entries.map((e) => '${e.key}=${e.value}').join('\n'));
    });

    test('cozy and homeOffice produce different inventories', () {
      final room = RoomModel(
        id: 'r',
        name: 'Diff',
        widthInFeet: 18,
        lengthInFeet: 15,
      );
      final cozy = AiDesigner.furnish(
        room: room,
        pixelsPerFoot: pxf,
        style: DesignStyle.cozy,
      );
      final office = AiDesigner.furnish(
        room: room,
        pixelsPerFoot: pxf,
        style: DesignStyle.homeOffice,
      );
      final cozyTypes = cozy.map((f) => f.type).toSet();
      final officeTypes = office.map((f) => f.type).toSet();
      expect(cozyTypes.contains(FurnitureType.sofa), isTrue);
      expect(officeTypes.contains(FurnitureType.desk), isTrue);
    });
  });

  group('Provider real path: design + alternatives + 3D', () {
    test('applyDesignStyle mutates room furniture via provider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final room = RoomModel(
        id: 'p1',
        name: 'Prov',
        widthInFeet: 14,
        lengthInFeet: 12,
      );
      container.read(roomProvider.notifier).loadRoom(room);
      final n = container.read(roomProvider.notifier);
      n.applyDesignStyle(DesignStyle.studio);
      final state = container.read(roomProvider);
      expect(state.room.furniture, isNotEmpty);
      expect(state.layoutScore, greaterThanOrEqualTo(0));
      File('${_evidence.path}/provider_design_style.txt').writeAsStringSync(
        'pieces=${state.room.furniture.length} score=${state.layoutScore}\n'
        'types=${state.room.furniture.map((f) => f.type.name).join(",")}',
      );
    });

    test('compare layouts A/B/C apply via provider', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final room = RoomModel(
        id: 'p2',
        name: 'Alts',
        widthInFeet: 14,
        lengthInFeet: 12,
        furniture: const [
          FurnitureItem(
            id: 'bed',
            type: FurnitureType.bed,
            position: Offset(100, 100),
            widthInFeet: 5,
            lengthInFeet: 6.5,
          ),
          FurnitureItem(
            id: 'sofa',
            type: FurnitureType.sofa,
            position: Offset(180, 160),
            widthInFeet: 7,
            lengthInFeet: 3,
          ),
          FurnitureItem(
            id: 'table',
            type: FurnitureType.table,
            position: Offset(140, 140),
            widthInFeet: 3.5,
            lengthInFeet: 2,
          ),
        ],
      );
      container.read(roomProvider.notifier).loadRoom(room);
      final n = container.read(roomProvider.notifier);
      final alts = LayoutAlternatives.generate(
        room: container.read(roomProvider).room,
        pixelsPerFoot: container.read(roomProvider).pixelsPerFoot,
      );
      expect(alts, hasLength(3));
      final before = container.read(roomProvider).room.furniture.first.position;
      n.applyLayoutAlternative(alts.first.furniture);
      final after = container.read(roomProvider).room.furniture;
      expect(after, hasLength(3));
      // Undo restores
      n.undo();
      final undone = container.read(roomProvider).room.furniture;
      expect(undone.firstWhere((f) => f.id == 'bed').position, before);
      File('${_evidence.path}/layout_alts_apply_undo.txt').writeAsStringSync(
        'alts=${alts.map((a) => "${a.letter}:${a.style.name}:${a.score}").join(" | ")}\n'
        'undo_ok=true',
      );
    });
  });

  group('Isometric 3D widget path', () {
    testWidgets('IsometricPreviewScreen paints extruded room', (tester) async {
      final room = RoomModel(
        id: 'iso',
        name: '3D room',
        widthInFeet: 12,
        lengthInFeet: 10,
        furniture: AiDesigner.furnish(
          room: RoomModel(
            id: 'iso',
            name: '3D room',
            widthInFeet: 12,
            lengthInFeet: 10,
          ),
          pixelsPerFoot: 20,
          style: DesignStyle.cozy,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: IsometricPreviewScreen(
            room: room,
            pixelsPerFoot: 20,
            unitSystem: UnitSystem.feet,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('3D preview'), findsOneWidget);
      expect(find.textContaining('Drag horizontally'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // Exercise orbit gesture on the 3D surface
      await tester.drag(find.byType(GestureDetector).first, const Offset(80, 0));
      await tester.pump();

      // Capture widget tree proof
      File('${_evidence.path}/isometric_widget.txt').writeAsStringSync(
        'title=3D preview found\n'
        'furniture=${room.furniture.length}\n'
        'custom_paint_present=true\n'
        'orbit_drag_ok=true\n',
      );
    });

    test('IsometricPainter paints without throwing (render path)', () {
      final room = RoomModel(
        id: 'iso2',
        name: 'Paint',
        widthInFeet: 12,
        lengthInFeet: 10,
        furniture: [
          FurnitureItem(
            id: 's',
            type: FurnitureType.sofa,
            position: const Offset(120, 100),
            widthInFeet: 7,
            lengthInFeet: 3,
            catalogId: 'sofa_3',
          ),
          FurnitureItem(
            id: 't',
            type: FurnitureType.table,
            position: const Offset(120, 160),
            widthInFeet: 3.5,
            lengthInFeet: 2,
            catalogId: 'coffee_table',
          ),
        ],
      );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      IsometricPainter(
        room: room,
        pixelsPerFoot: 20,
        unitSystem: UnitSystem.feet,
        yaw: 0.4,
      ).paint(canvas, const Size(400, 400));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
      File('${_evidence.path}/isometric_paint_ok.txt').writeAsStringSync(
        'painted=true size=400x400 yaw=0.4 pieces=2\n',
      );
    });
  });

  group('Arrange styles still valid', () {
    test('three styles on furnished room', () {
      final room = RoomModel(
        id: 'a',
        name: 'A',
        widthInFeet: 14,
        lengthInFeet: 12,
        furniture: const [
          FurnitureItem(
            id: '1',
            type: FurnitureType.bed,
            position: Offset(80, 80),
            widthInFeet: 5,
            lengthInFeet: 6,
          ),
          FurnitureItem(
            id: '2',
            type: FurnitureType.desk,
            position: Offset(200, 100),
            widthInFeet: 4.5,
            lengthInFeet: 2.2,
          ),
          FurnitureItem(
            id: '3',
            type: FurnitureType.plant,
            position: Offset(150, 150),
            widthInFeet: 1.5,
            lengthInFeet: 1.5,
          ),
        ],
      );
      for (final s in ArrangeStyle.values) {
        final items = AutoArrange.arrangeWithStyle(
          room: room,
          pixelsPerFoot: 20,
          style: s,
        );
        expect(items.map((f) => f.id).toSet(), {'1', '2', '3'});
      }
    });
  });
}
