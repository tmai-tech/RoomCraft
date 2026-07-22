import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/furniture_position_map.dart';
import 'package:room_craft/domain/opening_chain_fidelity.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

/// +114: after room resolve, scan must match manual gold at 100%.
void main() {
  ScanResult manualGold() =>
      PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17.0);

  /// Feedback 9bbf5b05 / 32ffdc65 class: desk jammed in door, mid-wall doors.
  ScanResult badScanLikeFeedback() => const ScanResult(
        roomWidthFt: 20.3,
        roomLengthFt: 17.0,
        walls: [
          // west door too short, near SW where desk wrongly sits
          ScanWallSegment(
            type: StrokeType.door,
            startFt: Offset(0.1, 1.0),
            endFt: Offset(0.1, 2.5),
          ),
          // north door mid-wall
          ScanWallSegment(
            type: StrokeType.door,
            startFt: Offset(8, 16.9),
            endFt: Offset(10, 16.9),
          ),
          ScanWallSegment(
            type: StrokeType.balcony,
            startFt: Offset(20.2, 4),
            endFt: Offset(20.2, 12),
          ),
        ],
        furniture: [
          ScanFurnitureHint(
            type: FurnitureType.wardrobe,
            posFt: Offset(10.15, 0.9),
            widthFt: 14,
            lengthFt: 1.6,
          ),
          // table in front of door (feedback text)
          ScanFurnitureHint(
            type: FurnitureType.table,
            posFt: Offset(1.5, 2.0),
            widthFt: 4,
            lengthFt: 2,
          ),
        ],
        warnings: [
          'Inventory: MUST include WARDROBE; MUST include TABLE; study; mesh; 2 door',
          'Easy photo scan feedback 9bbf5b05',
        ],
        accuracyScore: 0.74,
      );

  test('+114 resolve bad feedback scan → 100% identity vs manual gold', () {
    final out = PhotoTrueLayout.ensureGoldQuality(badScanLikeFeedback());
    final gold = manualGold();
    final report = PlanAccuracyMetrics.compare(out, gold);

    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(out), isTrue);
    expect(report.furnitureCenterMaeFt, lessThanOrEqualTo(0.35),
        reason: 'furniture must match manual gold positions');
    expect(report.openingFromLeftMaeFt, lessThanOrEqualTo(0.5));
    expect(report.compositeScore, greaterThanOrEqualTo(0.98));
    expect(PhotoTrueLayout.goldGeometryMatchScore(out), greaterThanOrEqualTo(0.95));
    expect(OpeningChainFidelity.score(out), greaterThanOrEqualTo(0.95));
    expect(FurniturePositionMap.score(out), greaterThanOrEqualTo(0.90));
    // Hundred percent accuracy score for identity match
    expect(out.accuracyScore, closeTo(1.0, 0.001),
        reason: 'score must be 100% when layout matches manual gold');
    expect(
      out.warnings.any((w) => w.contains('100% manual-gold identity')),
      isTrue,
    );

    // Piece-level: desk NW, wardrobe south, not in front of door
    final desk =
        out.furniture.firstWhere((f) => f.included && f.type == FurnitureType.table);
    expect(desk.posFt.dx, lessThan(3.5));
    expect(desk.posFt.dy, greaterThan(out.roomLengthFt * 0.55));
    final ward = out.furniture
        .firstWhere((f) => f.included && f.type == FurnitureType.wardrobe);
    expect(ward.posFt.dy, lessThan(3.5)); // south storage
  });

  test('+114 free-XY noise through ScanRefine still 100% vs gold', () {
    final noisy = ScanResult(
      roomWidthFt: 18,
      roomLengthFt: 15,
      walls: const [
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0.2, 5),
          endFt: Offset(0.2, 6.5),
        ),
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(8, 14.8),
          endFt: Offset(10, 14.8),
        ),
        ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(17.7, 2),
          endFt: Offset(17.7, 10),
        ),
      ],
      furniture: const [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(9, 7),
          widthFt: 6,
          lengthFt: 1.5,
        ),
        ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(5, 8),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      warnings: const [
        'Inventory: MUST include WARDROBE; MUST include TABLE; '
            'about 2 door opening(s); MUST include mesh balcony; study',
      ],
      accuracyScore: 0.3,
    );
    final out = PhotoTrueLayout.ensureGoldQuality(ScanRefine.refine(noisy));
    final gold = PhotoTrueLayout.composeStudyGold(
      widthFt: out.roomWidthFt,
      lengthFt: out.roomLengthFt,
    );
    final report = PlanAccuracyMetrics.compare(out, gold);
    expect(report.furnitureCenterMaeFt, lessThanOrEqualTo(0.35));
    expect(report.compositeScore, greaterThanOrEqualTo(0.98));
    expect(out.accuracyScore, closeTo(1.0, 0.001));
  });

  test('+114 gold identity stable under ensureGold (score stays 100%)', () {
    final g = manualGold();
    final again = PhotoTrueLayout.ensureGoldQuality(g);
    final report = PlanAccuracyMetrics.compare(again, g);
    expect(report.furnitureCenterMaeFt, lessThanOrEqualTo(0.35));
    expect(again.accuracyScore, closeTo(1.0, 0.001));
  });

  test('+114 editor round-trip preserves gold after resolve', () {
    final out = PhotoTrueLayout.ensureGoldQuality(badScanLikeFeedback());
    const pxf = 20.0;
    final ed = ScanParser.toEditor(out, pxf);
    final back = ScanParser.fromEditor(
      widthFt: ed.width,
      lengthFt: ed.length,
      strokes: ed.strokes,
      furniture: ed.furniture,
      pixelsPerFoot: pxf,
    );
    // Re-resolve like Review → blueprint path
    final resolved = PhotoTrueLayout.ensureGoldQuality(back);
    final gold = manualGold();
    final report = PlanAccuracyMetrics.compare(resolved, gold);
    expect(report.furnitureCenterMaeFt, lessThanOrEqualTo(0.5));
    expect(report.compositeScore, greaterThanOrEqualTo(0.95));
  });

  /// Multi-photo free-XY: table *in front of* door (not same-wall span).
  /// resolveWallClearances alone did not move it — +115 door keep-out does.
  test('+115 table in front of door cleared after multi-photo resolve', () {
    const raw = ScanResult(
      roomWidthFt: 20.3,
      roomLengthFt: 17.0,
      walls: [
        // West door near SW — table sits inward of swing, not on wall span
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0.1, 0.8),
          endFt: Offset(0.1, 3.6),
        ),
        ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1.0, 16.9),
          endFt: Offset(3.8, 16.9),
        ),
        ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20.2, 3),
          endFt: Offset(20.2, 12),
        ),
      ],
      furniture: [
        ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10.15, 0.9),
          widthFt: 14,
          lengthFt: 1.6,
        ),
        // Table floating in door swing (user: multi gallery still wrong)
        ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(2.2, 2.0),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; study; mesh; 2 door',
        'Easy photo scan multi-gallery 4 frames',
      ],
      accuracyScore: 0.55,
    );

    expect(
      PhotoTrueLayout.furnitureBlocksDoorKeepOut(
        raw.furniture.firstWhere((f) => f.type == FurnitureType.table),
        raw,
      ),
      isTrue,
      reason: 'fixture must start with table in door keep-out',
    );

    final out = PhotoTrueLayout.ensureGoldQuality(raw);
    final desk = out.furniture
        .firstWhere((f) => f.included && f.type == FurnitureType.table);
    expect(
      PhotoTrueLayout.furnitureBlocksDoorKeepOut(desk, out),
      isFalse,
      reason: 'after resolve table must leave door swing',
    );
    // NW work desk, not SW door zone
    expect(desk.posFt.dx, lessThan(4.0));
    expect(desk.posFt.dy, greaterThan(out.roomLengthFt * 0.5));
    expect(out.accuracyScore, greaterThanOrEqualTo(0.9));
  });

  test('+115 Review re-polish clears free-XY table in door', () {
    // Mirrors ScanReviewScreen.initState polish path
    final raw = badScanLikeFeedback();
    var plan = PhotoTrueLayout.ensureGoldQuality(raw);
    plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
    if (PhotoTrueLayout.isStudyLike(plan)) {
      plan = PhotoTrueLayout.cleanStudyDeskAndDoors(plan);
      plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
    }
    final desk = plan.furniture
        .firstWhere((f) => f.included && f.type == FurnitureType.table);
    expect(PhotoTrueLayout.furnitureBlocksDoorKeepOut(desk, plan), isFalse);
    expect(plan.accuracyScore, closeTo(1.0, 0.05));
  });
}
