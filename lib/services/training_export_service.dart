import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Local JSONL log of scan feedback + plan snapshots for future model training.
///
/// Does **not** upload automatically. User can export/share the file.
/// Each line is one JSON event — easy to bulk-import later.
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
      'v': 1,
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
  }) async {
    await logEvent({
      'type': 'scan_feedback',
      'rating': rating,
      'mode': mode,
      if (accuracyScore != null) 'accuracy': accuracyScore,
      if (roomWidthFt != null) 'width_ft': roomWidthFt,
      if (roomLengthFt != null) 'length_ft': roomLengthFt,
      if (furnitureCount != null) 'furniture_count': furnitureCount,
      if (openingsCount != null) 'openings_count': openingsCount,
    });
  }

  Future<void> logPlanSnapshot({
    required String source,
    required double widthFt,
    required double lengthFt,
    required List<Map<String, dynamic>> openings,
    required List<Map<String, dynamic>> furniture,
    String? feedbackRating,
  }) async {
    await logEvent({
      'type': 'plan_snapshot',
      'source': source,
      'width_ft': widthFt,
      'length_ft': lengthFt,
      'openings': openings,
      'furniture': furniture,
      if (feedbackRating != null) 'feedback': feedbackRating,
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
      text: 'Scan feedback + plan snapshots for model training',
    );
  }

  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
