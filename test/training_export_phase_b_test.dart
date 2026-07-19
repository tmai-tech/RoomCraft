import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/models/scan_result.dart';

void main() {
  test('+109 diagnosticsJson has phase_b schema and composite', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);
    final d = PlanAccuracyMetrics.diagnosticsJson(gold);
    expect(d['schema'], 'phase_b_v1');
    expect(d['vs_template'], isA<Map>());
    final vs = d['vs_template'] as Map;
    expect(vs['composite'], greaterThanOrEqualTo(0.85));
    expect(d['opening_fidelity'], greaterThanOrEqualTo(0.5));
    expect(d['room_type'], 'study');
    expect(d['scale_source'], isNotNull);
  });

  test('+109 syntheticReference for study yields dense gold', () {
    final thin = ScanResult(
      roomWidthFt: 20.3,
      roomLengthFt: 17,
      walls: const [],
      furniture: const [],
      warnings: const [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
      accuracyScore: 0.3,
    );
    final ref = PlanAccuracyMetrics.syntheticReference(thin);
    expect(PhotoTrueLayout.isPhotoTrue(ref) || ref.furniture.length >= 2, isTrue);
    final report = PlanAccuracyMetrics.compare(
      PhotoTrueLayout.ensureGoldQuality(thin),
      ref,
    );
    expect(report.furnitureTypeRecall, greaterThanOrEqualTo(0.5));
  });

  test('+109 planToJson serializes openings and furniture', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final j = PlanAccuracyMetrics.planToJson(gold);
    expect(j['width_ft'], 20);
    expect((j['openings'] as List), isNotEmpty);
    expect((j['furniture'] as List), isNotEmpty);
  });

  test('+109 thin plan vs template has lower composite than gold', () {
    final thin = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 10,
      walls: const [],
      furniture: const [],
      warnings: const [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
      accuracyScore: 0.2,
    );
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);
    final thinReport = PlanAccuracyMetrics.vsTemplate(thin);
    final goldReport = PlanAccuracyMetrics.vsTemplate(gold);
    expect(goldReport.compositeScore, greaterThan(thinReport.compositeScore));
  });

  test('+109 reviewLine is compact for UI', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);
    final line = PlanAccuracyMetrics.vsTemplate(gold).reviewLine();
    expect(line, contains('Phase B'));
    expect(line, contains('%'));
  });
}
