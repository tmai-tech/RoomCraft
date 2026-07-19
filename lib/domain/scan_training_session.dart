import '../models/scan_result.dart';
import 'plan_accuracy_metrics.dart';

/// In-memory session linking scan prediction → review → editor gold (+110).
///
/// Planner5D-class accuracy training needs **user-corrected** plans as labels,
/// not only synthetic templates. This holds the predicted scan until the
/// blueprint save logs a corrected gold pair.
class ScanTrainingSession {
  ScanTrainingSession._();

  static ScanResult? predicted;
  static ScanResult? reviewFinal;
  static String? feedbackRating;
  static bool correctedLogged = false;

  /// Call when Review opens (or scan completes).
  static void begin(ScanResult scanPredicted) {
    predicted = scanPredicted;
    reviewFinal = null;
    feedbackRating = null;
    correctedLogged = false;
  }

  /// Call when leaving Review into editor.
  static void markReviewFinal(ScanResult review, {String? rating}) {
    reviewFinal = review;
    if (rating != null) feedbackRating = rating;
  }

  static void clear() {
    predicted = null;
    reviewFinal = null;
    feedbackRating = null;
    correctedLogged = false;
  }

  /// Whether a predicted baseline is waiting for editor gold.
  static bool get active => predicted != null && !correctedLogged;

  /// Phase B pair: predicted vs corrected (+110).
  static Map<String, dynamic>? pairDiagnostics(ScanResult corrected) {
    final pred = predicted;
    if (pred == null) return null;
    final vsUser = PlanAccuracyMetrics.compare(pred, corrected);
    final vsTemplate = PlanAccuracyMetrics.vsTemplate(pred);
    return {
      'schema': 'phase_b_pair_v1',
      'vs_user_corrected': vsUser.toJson(),
      'vs_template': vsTemplate.toJson(),
      'predicted': PlanAccuracyMetrics.planToJson(pred),
      'corrected': PlanAccuracyMetrics.planToJson(corrected),
      if (reviewFinal != null)
        'review_final': PlanAccuracyMetrics.planToJson(reviewFinal!),
      if (feedbackRating != null) 'feedback': feedbackRating,
      'note':
          'User-corrected editor plan is gold label; predicted is model output (+110)',
    };
  }
}
