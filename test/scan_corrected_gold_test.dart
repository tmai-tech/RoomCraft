import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/domain/scan_training_session.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  tearDown(() => ScanTrainingSession.clear());

  test('+110 fromEditor round-trips toEditor geometry', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    const pxf = 20.0;
    final ed = ScanParser.toEditor(gold, pxf);
    final back = ScanParser.fromEditor(
      widthFt: ed.width,
      lengthFt: ed.length,
      strokes: ed.strokes,
      furniture: ed.furniture,
      pixelsPerFoot: pxf,
    );
    expect(back.roomWidthFt, 20);
    expect(back.roomLengthFt, 17);
    expect(back.furniture.length, gold.furniture.where((f) => f.included).length);
    final doors = back.walls.where((w) => w.type == StrokeType.door).length;
    final goldDoors =
        gold.walls.where((w) => w.type == StrokeType.door).length;
    expect(doors, goldDoors);
    // Positions within 0.2 ft
    final gWard =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    final bWard =
        back.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(bWard.posFt.dx, closeTo(gWard.posFt.dx, 0.25));
    expect(bWard.posFt.dy, closeTo(gWard.posFt.dy, 0.25));
  });

  test('+149 north-up: desk at top of blueprint, wardrobe lower (matches Review)', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17.0);
    const pxf = 20.0;
    final ed = ScanParser.toEditor(gold, pxf);
    final desk = ed.furniture.firstWhere((f) => f.type == FurnitureType.table);
    final ward = ed.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // Model: desk NW high y, wardrobe south low y. Editor north-up: desk low dy (top).
    expect(desk.position.dy, lessThan(ward.position.dy),
        reason: 'desk should be nearer top (N) than wardrobe');
    expect(desk.position.dy, lessThan(ed.length * pxf * 0.45),
        reason: 'NW desk should sit in upper half of north-up canvas');
    // Round-trip restores south=0 feet
    final back = ScanParser.fromEditor(
      widthFt: ed.width,
      lengthFt: ed.length,
      strokes: ed.strokes,
      furniture: ed.furniture,
      pixelsPerFoot: pxf,
    );
    final gDesk = gold.furniture.firstWhere((f) => f.type == FurnitureType.table);
    final bDesk = back.furniture.firstWhere((f) => f.type == FurnitureType.table);
    expect(bDesk.posFt.dy, closeTo(gDesk.posFt.dy, 0.3));
    expect(bDesk.posFt.dx, closeTo(gDesk.posFt.dx, 0.3));
  });

  test('+110 session pairDiagnostics predicted vs corrected', () {
    final predicted = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    ScanTrainingSession.begin(predicted);
    // User moves wardrobe significantly (simulated correction)
    final corrected = predicted.copyWith(
      furniture: [
        for (final f in predicted.furniture)
          if (f.type == FurnitureType.wardrobe)
            ScanFurnitureHint(
              type: f.type,
              posFt: Offset(f.posFt.dx + 4.0, f.posFt.dy),
              widthFt: f.widthFt,
              lengthFt: f.lengthFt,
              rotationRad: f.rotationRad,
              included: f.included,
            )
          else
            f,
      ],
      warnings: [...predicted.warnings, 'user moved wardrobe'],
    );
    final pair = ScanTrainingSession.pairDiagnostics(corrected);
    expect(pair, isNotNull);
    expect(pair!['schema'], 'phase_b_pair_v1');
    final vsUser = pair['vs_user_corrected'] as Map;
    // Averaged over all matched types — wardrobe move shows up as nonzero MAE
    expect(vsUser['furniture_center_mae_ft'], greaterThan(0.5));
    expect(vsUser['furniture_type_recall'], 1.0);
    expect(pair['predicted'], isNotNull);
    expect(pair['corrected'], isNotNull);
  });

  test('+110 diagnosticsJson includes vs_user_corrected when provided', () {
    final pred = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final thin = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 10,
      walls: const [],
      furniture: const [],
      accuracyScore: 0.2,
    );
    final d = PlanAccuracyMetrics.diagnosticsJson(thin, userCorrected: pred);
    expect(d['schema'], 'phase_b_v2');
    expect(d['vs_user_corrected'], isNotNull);
    expect(d['has_user_gold'], true);
  });

  test('+110 identical corrected gold scores high vs itself', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);
    ScanTrainingSession.begin(gold);
    final pair = ScanTrainingSession.pairDiagnostics(gold)!;
    final vs = pair['vs_user_corrected'] as Map;
    expect(vs['composite'], greaterThanOrEqualTo(0.95));
  });
}
