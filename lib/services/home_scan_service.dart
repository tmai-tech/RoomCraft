import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/home_scan.dart';
import 'ar_measure_service.dart';

/// Persist Home Scan packages on device (+127).
///
/// Packages are training / future cloud inputs (poses + floor hits).
/// Never auto-uploads.
class HomeScanService {
  static const _dirName = 'home_scans';

  Future<Directory> _dir() async {
    final root = await getApplicationDocumentsDirectory();
    final d = Directory('${root.path}/$_dirName');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> save(HomeScanPackage pack) async {
    final d = await _dir();
    final f = File('${d.path}/${pack.id}.json');
    await f.writeAsString(pack.toJsonString());
    final index = File('${d.path}/index.jsonl');
    await index.writeAsString(
      '${jsonEncode({
            'id': pack.id,
            'created_at': pack.createdAt.toUtc().toIso8601String(),
            'width_ft': pack.resolvedSize.widthFt,
            'length_ft': pack.resolvedSize.lengthFt,
            'samples': pack.sampleCount,
            'poses': pack.poseCount,
          })}\n',
      mode: FileMode.append,
    );
    return f;
  }

  Future<List<String>> listIds() async {
    final d = await _dir();
    if (!await d.exists()) return [];
    return d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json') && !f.path.endsWith('index.jsonl'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
        .toList();
  }

  Future<HomeScanPackage?> load(String id) async {
    final d = await _dir();
    final f = File('${d.path}/$id.json');
    if (!await f.exists()) return null;
    final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return _fromJson(map);
  }

  HomeScanPackage? _fromJson(Map<String, dynamic> map) {
    try {
      final m = map['measure'] as Map<String, dynamic>? ?? {};
      final measure = ArRoomMeasure(
        widthFt: (m['width_ft'] as num?)?.toDouble() ?? 0,
        lengthFt: (m['length_ft'] as num?)?.toDouble() ?? 0,
        widthM: (m['width_m'] as num?)?.toDouble() ?? 0,
        lengthM: (m['length_m'] as num?)?.toDouble() ?? 0,
        mode: m['mode']?.toString() ?? 'auto',
        source: m['source']?.toString() ?? 'arcore',
        orthogonalScore: (m['orthogonal_score'] as num?)?.toDouble() ?? 0,
        diagonalError: (m['diagonal_error'] as num?)?.toDouble() ?? 0,
        coverageScore: (m['coverage_score'] as num?)?.toDouble() ?? 0,
      );
      List<List<double>> pts(dynamic raw) {
        if (raw is! List) return const [];
        return raw
            .whereType<List>()
            .map((e) => e.map((v) => (v as num).toDouble()).toList())
            .toList();
      }

      return HomeScanPackage(
        id: map['id']?.toString() ?? 'unknown',
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now().toUtc(),
        measure: measure,
        floorHitsM: pts(map['floor_hits_m']),
        posesM: pts(map['poses_m']),
        appVersion: map['app_version']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
