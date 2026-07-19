import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/plan_accuracy_metrics.dart';
import '../models/scan_result.dart';

/// Local JSONL log of scan feedback + plan snapshots for future model training.
///
/// Does **not** upload automatically. User can export/share the file.
/// Each line is one JSON event — easy to bulk-import later.
///
/// +109: Phase B metrics (`phase_b`) on feedback + snapshots for labeled
/// accuracy training (Planner5D-class dimension / placement fidelity).
class TrainingExportService {
  static const fileName = 'roomcraft_training_events.jsonl';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<void> logEvent(Map<String, dynamic> event) async {
    final f = await _file();
    final line = jsonEncode({
      ...event,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'v': 2,
    });
    await f.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  Future<void> logScanFeedback({
    required String rating,
    required String mode,
    double? accuracyScore,
    double? roomWidthFt,
    double? roomLengthFt,
    int? furnitureCount,
    int? openingsCount,
    Map<String, dynamic>? phaseB,
    ScanResult? plan,
  }) async {
    Map<String, dynamic>? metrics = phaseB;
    Map<String, dynamic>? planJson;
    if (plan != null) {
      metrics ??= PlanAccuracyMetrics.diagnosticsJson(plan);
      planJson = PlanAccuracyMetrics.planToJson(plan);
    }
    await logEvent({
      'type': 'scan_feedback',
      'rating': rating,
      'mode': mode,
      if (accuracyScore != null) 'accuracy': accuracyScore,
      if (roomWidthFt != null) 'width_ft': roomWidthFt,
      if (roomLengthFt != null) 'length_ft': roomLengthFt,
      if (furnitureCount != null) 'furniture_count': furnitureCount,
      if (openingsCount != null) 'openings_count': openingsCount,
      if (metrics != null) 'phase_b': metrics,
      if (planJson != null) 'plan': planJson,
    });
  }

  Future<void> logPlanSnapshot({
    required String source,
    required double widthFt,
    required double lengthFt,
    required List<Map<String, dynamic>> openings,
    required List<Map<String, dynamic>> furniture,
    String? feedbackRating,
    double? accuracyScore,
    Map<String, dynamic>? phaseB,
    ScanResult? plan,
  }) async {
    Map<String, dynamic>? metrics = phaseB;
    if (plan != null) {
      metrics ??= PlanAccuracyMetrics.diagnosticsJson(plan);
    }
    await logEvent({
      'type': 'plan_snapshot',
      'source': source,
      'width_ft': widthFt,
      'length_ft': lengthFt,
      'openings': openings,
      'furniture': furniture,
      if (feedbackRating != null) 'feedback': feedbackRating,
      if (accuracyScore != null) 'accuracy': accuracyScore,
      if (metrics != null) 'phase_b': metrics,
    });
  }

  /// Convenience: log snapshot from a full [ScanResult] (+109).
  Future<void> logScanResultSnapshot({
    required String source,
    required ScanResult plan,
    String? feedbackRating,
    ScanResult? userCorrected,
  }) async {
    final json = PlanAccuracyMetrics.planToJson(plan);
    await logPlanSnapshot(
      source: source,
      widthFt: plan.roomWidthFt,
      lengthFt: plan.roomLengthFt,
      openings: List<Map<String, dynamic>>.from(json['openings'] as List),
      furniture: List<Map<String, dynamic>>.from(json['furniture'] as List),
      feedbackRating: feedbackRating,
      accuracyScore: plan.accuracyScore,
      phaseB: PlanAccuracyMetrics.diagnosticsJson(
        plan,
        userCorrected: userCorrected,
      ),
      plan: plan,
    );
  }

  /// Predicted model plan vs user-corrected editor gold (+110).
  Future<void> logCorrectedGoldPair({
    required ScanResult predicted,
    required ScanResult corrected,
    String? feedbackRating,
    Map<String, dynamic>? pairDiagnostics,
  }) async {
    final vs = PlanAccuracyMetrics.compare(predicted, corrected);
    await logEvent({
      'type': 'corrected_gold_pair',
      'source': 'editor_save',
      if (feedbackRating != null) 'feedback': feedbackRating,
      'phase_b': pairDiagnostics ??
          {
            'schema': 'phase_b_pair_v1',
            'vs_user_corrected': vs.toJson(),
            'vs_template':
                PlanAccuracyMetrics.vsTemplate(predicted).toJson(),
            'predicted': PlanAccuracyMetrics.planToJson(predicted),
            'corrected': PlanAccuracyMetrics.planToJson(corrected),
          },
      'composite_vs_user': vs.compositeScore,
      'summary': vs.summaryLine(),
    });
  }

  Future<int> eventCount() async {
    final f = await _file();
    if (!await f.exists()) return 0;
    final lines = await f.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).length;
  }

  Future<String?> exportPath() async {
    final f = await _file();
    if (!await f.exists()) return null;
    return f.path;
  }

  Future<void> shareExport() async {
    final f = await _file();
    if (!await f.exists() || await f.length() == 0) {
      throw Exception('No training events yet — rate a few scans first');
    }
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'application/x-ndjson', name: fileName)],
      subject: 'RoomCraft training export',
      text:
          'Scan feedback + plan snapshots + Phase B accuracy metrics for model training',
    );
  }

  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
