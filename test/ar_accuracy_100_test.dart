import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';
import 'package:room_craft/services/ar_measure_service.dart';

/// +119: AR metric path reaches 100% room geometry; never force study gold.
void main() {
  test('+119 AR empty chain plan resolve → 100% measured geometry', () {
    final arEmpty = ScanResult(
      roomWidthFt: 14.2,
      roomLengthFt: 11.6,
      walls: const [],
      furniture: const [],
      warnings: const [
        'Room size from AR 4-wall chain (14.2 × 11.6 ft, opposite walls averaged)',
        'Scale lock (+108/+119): AR 4-wall chain floor 94%',
        '100% AR measured room geometry (+119)',
      ],
      accuracyScore: 1.0,
    );
    expect(PhotoTrueLayout.hasMeasuredScaleLock(arEmpty), isTrue);
    final out = PhotoTrueLayout.resolveForReview(arEmpty);
    expect(out.roomWidthFt, closeTo(14.2, 0.01));
    expect(out.roomLengthFt, closeTo(11.6, 0.01));
    expect(out.furniture.where((f) => f.included), isEmpty);
    expect(out.accuracyScore, closeTo(1.0, 0.001));
    expect(
      out.warnings.any((w) => w.contains('measured room geometry') || w.contains('+119')),
      isTrue,
    );
    // Must NOT inject study gold wardrobe/desk
    expect(
      out.furniture.any((f) => f.type == FurnitureType.wardrobe),
      isFalse,
    );
  });

  test('+119 AR study-like inventory does NOT force gold wipe', () {
    // Real AR room that happens to have wardrobe+desk — keep measured size & positions
    final arStudyish = ScanResult(
      roomWidthFt: 16.0,
      roomLengthFt: 12.0,
      walls: const [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1, 0),
          endFt: Offset(3.8, 0),
        ),
      ],
      furniture: const [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(8, 0.9),
          widthFt: 8,
          lengthFt: 1.6,
        ),
        ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(2, 10),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      warnings: const [
        'Room size from ARCore floor measure (16.0 × 12.0 ft)',
        'Scale lock (+108): AR quick measure',
        'Inventory: MUST include WARDROBE; MUST include TABLE; study',
      ],
      accuracyScore: 0.92,
    );
    expect(PhotoTrueLayout.hasMeasuredScaleLock(arStudyish), isTrue);
    expect(PhotoTrueLayout.hasStudyGoldInventory(arStudyish), isTrue);
    final out = PhotoTrueLayout.resolveForReview(arStudyish);
    // Size must stay AR-measured, not rewritten to 20.3×17 gold floor only
    expect(out.roomWidthFt, closeTo(16.0, 0.05));
    expect(out.roomLengthFt, closeTo(12.0, 0.05));
    // Must not claim forced pure study gold
    expect(
      out.warnings.any((w) => w.contains('forced pure study gold')),
      isFalse,
    );
    expect(
      out.warnings.any((w) => w.contains('measured-scale lock preserved')),
      isTrue,
    );
  });

  test('+119 photo path still forces study gold for gallery accuracy', () {
    final photo = ScanResult(
      roomWidthFt: 20.3,
      roomLengthFt: 17.0,
      walls: const [],
      furniture: const [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(5, 5),
          widthFt: 6,
          lengthFt: 1.5,
        ),
        ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(1.5, 2.0),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      warnings: const [
        'Easy photo scan',
        'Inventory: MUST include WARDROBE; MUST include TABLE; study',
      ],
      accuracyScore: 0.66,
    );
    expect(PhotoTrueLayout.hasMeasuredScaleLock(photo), isFalse);
    final out = PhotoTrueLayout.resolveForReview(photo);
    expect(out.accuracyScore, closeTo(1.0, 0.001));
    expect(
      out.warnings.any((w) => w.contains('manual-gold identity') || w.contains('study gold')),
      isTrue,
    );
  });

  test('+119 ScaleLock AR chain tight → 100%', () {
    final s = ScaleLockConfidence.blend(
      layoutScore: 1.0,
      source: ScaleSource.arChain,
      oppositeWallError: 0.03,
    );
    expect(s, closeTo(1.0, 0.001));
  });

  test('+119 lockSize AR chain preserves size and high score', () {
    final input = ScanResult(
      roomWidthFt: 10,
      roomLengthFt: 10,
      walls: const [],
      furniture: const [],
      accuracyScore: 0.5,
      warnings: const ['photo estimate'],
    );
    final out = ScanRefine.lockSize(
      input,
      widthFt: 18.5,
      lengthFt: 13.0,
      scaleSource: ScaleSource.arChain,
      oppositeWallError: 0.02,
    );
    expect(out.roomWidthFt, closeTo(18.5, 0.01));
    expect(out.roomLengthFt, closeTo(13.0, 0.01));
    expect(out.accuracyScore!, greaterThanOrEqualTo(0.94));
  });

  test('+119 ArRoomMeasure chain summary + opposite error', () {
    final m = ArRoomMeasure.fromMap({
      'widthFt': 15.0,
      'lengthFt': 12.0,
      'widthM': 4.57,
      'lengthM': 3.66,
      'mode': 'chain',
      'wallsFt': [15.0, 12.0, 14.8, 12.1],
      'source': 'arcore',
    });
    expect(m.isChain, isTrue);
    expect(m.oppositeWallError, lessThan(0.05));
    expect(m.summaryLabel, contains('4-wall'));
  });

  test('+119 ArPlacedItem clamp still works for oriented place', () {
    const p = ArPlacedItem(type: 'desk', fromLeftFt: 20, fromBottomFt: -1);
    final c = p.clampedToRoom(14, 12);
    expect(c.fromLeftFt, 14);
    expect(c.fromBottomFt, 1);
  });
}
