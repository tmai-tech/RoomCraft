import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('+108 PlanAccuracyMetrics: identical plans score high', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);
    final r = PlanAccuracyMetrics.compare(gold, gold);
    expect(r.compositeScore, greaterThanOrEqualTo(0.95));
    expect(r.roomSizeErrorPct, lessThan(0.01));
    expect(r.furnitureTypeRecall, 1.0);
  });

  test('+108 PlanAccuracyMetrics: thin empty vs gold is low', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);
    final thin = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 10,
      walls: const [],
      furniture: const [],
      accuracyScore: 0.2,
    );
    final r = PlanAccuracyMetrics.compare(thin, gold);
    expect(r.compositeScore, lessThan(0.45));
    expect(r.furnitureTypeRecall, 0);
  });

  test('+108 ensureGold vs composeStudyGold has high type recall', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);
    final thin = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 10.5,
      walls: const [],
      furniture: const [],
      warnings: const [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
        'multi-wall study',
      ],
      accuracyScore: 0.25,
    );
    final pred = PhotoTrueLayout.ensureGoldQuality(thin);
    final r = PlanAccuracyMetrics.compare(pred, gold);
    expect(r.furnitureTypeRecall, greaterThanOrEqualTo(0.66));
    expect(r.compositeScore, greaterThanOrEqualTo(0.55));
    expect(r.summaryLine(), contains('+111'));
  });

  test('+108 AR scale lock raises confidence floor', () {
    final input = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 10,
      walls: const [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1, 0),
          endFt: Offset(2.5, 0),
        ),
      ],
      furniture: const [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(6, 1),
          widthFt: 6,
          lengthFt: 1.5,
        ),
      ],
      accuracyScore: 0.48,
    );
    final out = ScanRefine.lockSize(
      input,
      widthFt: 20.3,
      lengthFt: 17,
      scaleSource: ScaleSource.arChain,
      oppositeWallError: 0.04,
    );
    expect(out.roomWidthFt, closeTo(20.3, 0.01));
    expect(out.roomLengthFt, closeTo(17, 0.01));
    // AR chain floor 0.94 — must not stay at photo 0.48
    expect(out.accuracyScore!, greaterThanOrEqualTo(0.90));
    expect(out.warnings.any((w) => w.contains('Scale lock (+108)')), isTrue);
  });

  test('+108 tape scale lock higher than photo estimate floor', () {
    final photo = ScaleLockConfidence.sourceFloor(ScaleSource.photoEstimate);
    final tape = ScaleLockConfidence.sourceFloor(ScaleSource.tape);
    final ar = ScaleLockConfidence.sourceFloor(ScaleSource.arChain);
    expect(tape, greaterThan(photo));
    expect(ar, greaterThan(photo));
    expect(tape, greaterThanOrEqualTo(0.95));
  });

  test('+108 lockSize door still on perimeter after rescale', () {
    final input = ScanResult(
      roomWidthFt: 10,
      roomLengthFt: 10,
      walls: const [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1, 0),
          endFt: Offset(4, 0),
        ),
      ],
      furniture: const [],
      accuracyScore: 0.5,
    );
    final out = ScanRefine.lockSize(
      input,
      widthFt: 20,
      lengthFt: 20,
      scaleSource: ScaleSource.arQuick,
    );
    expect(out.walls.where((w) => w.type == StrokeType.door), isNotEmpty);
    expect(out.accuracyScore!, greaterThanOrEqualTo(0.85));
  });
}
