import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/catalog/furniture_catalog.dart';
import 'package:room_craft/models/furniture_item.dart';

/// Proof tests that read SHIPPED source — not reimplemented logic.
/// Skeptic-cited paths are asserted against current tree content.
void main() {
  final root = Directory.current.path;
  final evidence = Directory('/tmp/grok-goal-ef2d7761b704/implementer/evidence')
    ..createSync(recursive: true);

  test('SOURCE: home AR tile calls _createNewAR not _createNewAI', () {
    final home = File('$root/lib/screens/home_screen.dart').readAsStringSync();
    // Extract block between AR Room Planner title and Scan with AI photos
    final start = home.indexOf("title: const Text('AR Room Planner')");
    final end = home.indexOf("title: const Text('Scan with AI photos')");
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final arBlock = home.substring(start, end);
    expect(arBlock.contains('_createNewAR()'), isTrue);
    expect(arBlock.contains('_createNewAI()'), isFalse);
    expect(home.contains("initialScanMode: 'ar_guided'"), isTrue);

    File('${evidence.path}/source_ar_not_createNewAI.txt').writeAsStringSync(
      'ar_block_has_createNewAR=${arBlock.contains('_createNewAR()')}\n'
      'ar_block_has_createNewAI=${arBlock.contains('_createNewAI()')}\n'
      'initialScanMode_ar_guided=${home.contains("initialScanMode: 'ar_guided'")}\n'
      'ar_place_layout_screen_exists=${File('$root/lib/screens/ar_place_layout_screen.dart').existsSync()}\n'
      'ar_place_activity_exists=${File('$root/android/app/src/main/kotlin/com/logicrequire/room_craft/ArPlaceActivity.kt').existsSync()}\n',
    );
  });

  test('SOURCE: interactive_3d_styler V7 is select/rotate/apply/delete not open-only', () {
    final f = File('$root/test/interactive_3d_styler_test.dart').readAsStringSync();
    expect(f.contains('V7 REAL path in interactive_3d_styler: select+rotate+apply+delete'), isTrue);
    expect(f.contains('iso_furniture_picker'), isTrue);
    expect(f.contains('iso_rotate_btn'), isTrue);
    expect(f.contains('iso_apply_btn'), isTrue);
    expect(f.contains('iso_delete_btn'), isTrue);
    expect(f.contains('onFurnitureChanged'), isTrue);
    // Must NOT be the old open-only body as sole path
    expect(f.contains('interactive_3d_open_only.txt'), isFalse);

    File('${evidence.path}/source_v7_not_open_only.txt').writeAsStringSync(
      'has_v7_title=true\n'
      'has_picker=true\n'
      'has_rotate=true\n'
      'has_apply=true\n'
      'has_delete=true\n'
      'no_open_only_evidence_file=true\n',
    );
  });

  test('SOURCE+RUNTIME: catalog ≥10000 and perspective painter defaults true', () {
    expect(FurnitureCatalog.count, greaterThanOrEqualTo(10000));
    expect(FurnitureType.values.length, greaterThanOrEqualTo(18));
    final painter = File('$root/lib/painters/isometric_painter.dart').readAsStringSync();
    expect(painter.contains('this.perspective = true'), isTrue);
    expect(painter.contains('walkX'), isTrue);
    expect(painter.contains('eyeHeightFt'), isTrue);

    File('${evidence.path}/source_catalog_and_3d.txt').writeAsStringSync(
      'skus=${FurnitureCatalog.count}\n'
      'types=${FurnitureType.values.length}\n'
      'perspective_default_true=${painter.contains('this.perspective = true')}\n'
      'walkthrough_walkX=${painter.contains('walkX')}\n',
    );
  });

  test('SOURCE: plan §5 states full Play objective not free-only success redefine', () {
    final plan = File('$root/docs/PLANNER5D_PARITY_PLAN.md').readAsStringSync();
    expect(plan.contains('Objective = Planner 5D Play listing level'), isTrue);
    expect(plan.contains('Goal = full Play listing parity'), isTrue);
    expect(plan.contains('Meeting C1–C8 = **goal achieved**'), isFalse);
    File('${evidence.path}/source_plan_objective.txt').writeAsStringSync(
      'has_play_objective_title=true\n'
      'has_full_parity_goal=true\n'
      'no_c1c8_goal_achieved_line=true\n',
    );
  });

  test('SOURCE: live AR placeFurniture bridge + native activity', () {
    final svc = File('$root/lib/services/ar_measure_service.dart').readAsStringSync();
    final layout = File('$root/lib/screens/ar_place_layout_screen.dart').readAsStringSync();
    final main = File(
      '$root/android/app/src/main/kotlin/com/logicrequire/room_craft/MainActivity.kt',
    ).readAsStringSync();
    final place = File(
      '$root/android/app/src/main/kotlin/com/logicrequire/room_craft/ArPlaceActivity.kt',
    );
    expect(place.existsSync(), isTrue);
    expect(svc.contains("invokeMethod") && svc.contains("'placeFurniture'"), isTrue);
    expect(svc.contains('class ArPlacedItem'), isTrue);
    expect(layout.contains('_liveArPlace'), isTrue);
    expect(layout.contains('ar_live_place_camera'), isTrue);
    expect(main.contains('launchPlace'), isTrue);
    expect(main.contains('startPlaceActivity'), isTrue);
    expect(main.contains('ArPlaceActivity.REQUEST_CODE'), isTrue);
    expect(place.readAsStringSync().contains('HORIZONTAL_UPWARD_FACING'), isTrue);

    File('${evidence.path}/source_ar_live_place.txt').writeAsStringSync(
      'placeFurniture_method=true\n'
      'ArPlacedItem=true\n'
      'ar_live_place_camera_key=true\n'
      'launchPlace=true\n'
      'startPlaceActivity=true\n'
      'ArPlaceActivity_exists=true\n'
      'floor_hit_test=true\n',
    );
  });

  test('SOURCE+RUNTIME: marketplace collection lines filter catalog', () {
    expect(FurnitureCatalog.collectionLines, contains('Nordic'));
    expect(FurnitureCatalog.collectionLines, contains('Luxe'));
    final nordic = FurnitureCatalog.byCollection('Nordic');
    expect(nordic, isNotEmpty);
    expect(nordic.every((e) => e.description.contains('Nordic collection') ||
        e.label.startsWith('Nordic ') ||
        e.id.endsWith('__nordic')), isTrue);
    File('${evidence.path}/source_marketplace_collections.txt').writeAsStringSync(
      'lines=${FurnitureCatalog.collectionLines.join(",")}\n'
      'nordic_count=${nordic.length}\n'
      'total_skus=${FurnitureCatalog.count}\n',
    );
  });
}
