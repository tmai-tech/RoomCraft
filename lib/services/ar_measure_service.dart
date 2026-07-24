import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of an ARCore guided floor measure.
class ArRoomMeasure {
  final double widthFt;
  final double lengthFt;
  final double widthM;
  final double lengthM;
  final String source;
  /// `auto` | `quick` | `chain` | `polygon` / `corners` (+125 walk-to-map).
  final String mode;
  /// Per-wall lengths in feet (A,B[,C,D]).
  final List<double> wallsFt;
  final List<double> wallsM;
  /// Flat world corners meters: [x0,y0,z0, x1,y1,z1, ...] for polygon mode.
  final List<double> cornersM;
  /// +127 Home Scan camera pose trail: [x0,y0,z0, ...] meters.
  final List<double> posesM;
  final int sampleCount;
  final int poseCount;
  /// +124 how rectangular the multi-dot map is (0..1).
  final double orthogonalScore;
  /// +124 |measuredDiag/expected − 1| after auto refine.
  final double diagonalError;
  /// +126 angular walk coverage (0..1) — Planner5D loop completeness.
  final double coverageScore;
  /// +131 Depth API was enabled for this capture (device-supported only).
  final bool depthEnabled;
  final int depthSamples;

  const ArRoomMeasure({
    required this.widthFt,
    required this.lengthFt,
    required this.widthM,
    required this.lengthM,
    this.source = 'arcore',
    this.mode = 'quick',
    this.wallsFt = const [],
    this.wallsM = const [],
    this.cornersM = const [],
    this.posesM = const [],
    this.sampleCount = 0,
    this.poseCount = 0,
    this.orthogonalScore = 0,
    this.diagonalError = 0,
    this.coverageScore = 0,
    this.depthEnabled = false,
    this.depthSamples = 0,
  });

  factory ArRoomMeasure.fromMap(Map<dynamic, dynamic> map) {
    List<double> asDoubles(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => (e as num).toDouble()).toList();
    }

    final corners = asDoubles(map['cornersM']);
    final poses = asDoubles(map['posesM']);
    return ArRoomMeasure(
      widthFt: (map['widthFt'] as num).toDouble(),
      lengthFt: (map['lengthFt'] as num).toDouble(),
      widthM: (map['widthM'] as num?)?.toDouble() ?? 0,
      lengthM: (map['lengthM'] as num?)?.toDouble() ?? 0,
      source: map['source']?.toString() ?? 'arcore',
      mode: map['mode']?.toString() ?? 'quick',
      wallsFt: asDoubles(map['wallsFt']),
      wallsM: asDoubles(map['wallsM']),
      cornersM: corners,
      posesM: poses,
      sampleCount: (map['sampleCount'] as num?)?.toInt() ?? (corners.length ~/ 3),
      poseCount: (map['poseCount'] as num?)?.toInt() ?? (poses.length ~/ 3),
      orthogonalScore: (map['orthogonalScore'] as num?)?.toDouble() ?? 0,
      diagonalError: (map['diagonalError'] as num?)?.toDouble() ?? 0,
      coverageScore: (map['coverageScore'] as num?)?.toDouble() ?? 0,
      depthEnabled: map['depthEnabled'] == true,
      depthSamples: (map['depthSamples'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isChain => mode == 'chain' && wallsFt.length >= 4;

  /// +123 multi-dot 4-corner floor map.
  bool get isPolygon =>
      mode == 'polygon' || mode == 'corners' || cornersM.length >= 12;

  /// +125 easy walk-to-map (default for common users).
  bool get isAuto => mode == 'auto' || (mode == 'polygon' && cornersM.length > 12);

  /// Opposite-wall consistency: max relative difference (0–1).
  double get oppositeWallError {
    if (wallsFt.length < 4) return 0;
    final a = wallsFt[0];
    final b = wallsFt[1];
    final c = wallsFt[2];
    final d = wallsFt[3];
    final eW = a <= 0 ? 0.0 : ((a - c).abs() / a);
    final eL = b <= 0 ? 0.0 : ((b - d).abs() / b);
    return eW > eL ? eW : eL;
  }

  String get summaryLabel {
    final base =
        '${widthFt.toStringAsFixed(1)} × ${lengthFt.toStringAsFixed(1)} ft';
    if (isAuto) {
      final o = orthogonalScore > 0
          ? ' · fit ${(orthogonalScore * 100).round()}%'
          : '';
      final c = coverageScore > 0
          ? ' · cover ${(coverageScore * 100).round()}%'
          : '';
      return '$base · AR easy walk$o$c';
    }
    if (isPolygon) {
      final o = orthogonalScore > 0
          ? ' · ortho ${(orthogonalScore * 100).round()}%'
          : '';
      return '$base · AR multi-dot$o';
    }
    if (isChain) {
      return '$base · 4-wall AR chain';
    }
    return '$base · AR quick';
  }

  /// Combined consistency error for scale-lock blend (+124/+126).
  /// Incomplete walk coverage raises effective error so score is honest.
  double get consistencyError {
    final wall = oppositeWallError;
    var err = wall > diagonalError ? wall : diagonalError;
    if (isAuto && coverageScore > 0 && coverageScore < 0.75) {
      final covErr = (0.75 - coverageScore) * 0.20;
      if (covErr > err) err = covErr;
    }
    return err;
  }

  ArRoomMeasure get normalized {
    if (widthFt >= lengthFt) return this;
    return ArRoomMeasure(
      widthFt: lengthFt,
      lengthFt: widthFt,
      widthM: lengthM,
      lengthM: widthM,
      source: source,
      mode: mode,
      wallsFt: wallsFt,
      wallsM: wallsM,
      cornersM: cornersM,
      posesM: posesM,
      sampleCount: sampleCount,
      poseCount: poseCount,
      orthogonalScore: orthogonalScore,
      diagonalError: diagonalError,
      coverageScore: coverageScore,
    );
  }
}

class ArAvailability {
  final bool supported;
  final bool installNeeded;
  final String message;

  const ArAvailability({
    required this.supported,
    required this.installNeeded,
    required this.message,
  });
}

/// Flutter bridge to native ARCore guided measure (Android only).
class ArMeasureService {
  static const _channel = MethodChannel('com.logicrequire.room_craft/ar_measure');

  static bool get isPlatformSupported => !kIsWeb && Platform.isAndroid;

  static Future<ArAvailability> isAvailable() async {
    if (!isPlatformSupported) {
      return const ArAvailability(
        supported: false,
        installNeeded: false,
        message: 'AR measure is available on Android devices with ARCore',
      );
    }
    try {
      final raw = await _channel
          .invokeMethod<dynamic>('isAvailable')
          .timeout(const Duration(seconds: 5));
      if (raw is! Map) {
        return const ArAvailability(
          supported: false,
          installNeeded: false,
          message: 'AR check returned empty',
        );
      }
      return ArAvailability(
        supported: raw['supported'] == true,
        installNeeded: raw['installNeeded'] == true,
        message: raw['message']?.toString() ?? '',
      );
    } on PlatformException catch (e) {
      return ArAvailability(
        supported: false,
        installNeeded: false,
        message: e.message ?? e.code,
      );
    } catch (e) {
      return ArAvailability(
        supported: false,
        installNeeded: false,
        message: e.toString(),
      );
    }
  }

  /// [mode]: `auto` (easy walk, default) | `corners` | `chain` | `quick`.
  static Future<ArRoomMeasure> measureRoom({String mode = 'auto'}) async {
    if (!isPlatformSupported) {
      throw PlatformException(
        code: 'UNSUPPORTED',
        message: 'AR measure requires Android + ARCore',
      );
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'measureRoom',
      {'mode': mode},
    );
    if (raw == null) {
      throw PlatformException(code: 'EMPTY', message: 'No measure result');
    }
    final m = ArRoomMeasure.fromMap(raw);
    if (m.widthFt < 1.5 || m.lengthFt < 1.5) {
      throw PlatformException(
        code: 'TOO_SMALL',
        message:
            'Measured size looks too small — try again with clearer floor tracking',
      );
    }
    if (m.widthFt > 80 || m.lengthFt > 80) {
      throw PlatformException(
        code: 'TOO_LARGE',
        message:
            'Measured size looks unrealistic — retake with both ends on the floor grid',
      );
    }
    return m;
  }

  /// Live-camera AR: mark origin + place furniture on floor plane.
  /// Returns room-relative positions in feet from SW origin.
  static Future<List<ArPlacedItem>> placeFurniture({
    required double widthFt,
    required double lengthFt,
  }) async {
    if (!isPlatformSupported) {
      throw PlatformException(
        code: 'UNSUPPORTED',
        message: 'AR place requires Android + ARCore',
      );
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'placeFurniture',
      {'widthFt': widthFt, 'lengthFt': lengthFt},
    );
    if (raw == null) return const [];
    final list = raw['placements'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => ArPlacedItem.fromMap(Map<dynamic, dynamic>.from(e)))
        .toList();
  }
}

/// One furniture placement from live AR floor hit-testing.
class ArPlacedItem {
  final String type;
  final double fromLeftFt;
  final double fromBottomFt;

  const ArPlacedItem({
    required this.type,
    required this.fromLeftFt,
    required this.fromBottomFt,
  });

  factory ArPlacedItem.fromMap(Map<dynamic, dynamic> m) {
    return ArPlacedItem(
      type: m['type']?.toString() ?? 'table',
      fromLeftFt: (m['fromLeftFt'] as num?)?.toDouble() ?? 0,
      fromBottomFt: (m['fromBottomFt'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Clamp placement inside room so AR hits outside the measured box still land on plan.
  ArPlacedItem clampedToRoom(double widthFt, double lengthFt) {
    final w = widthFt.clamp(1.0, 200.0);
    final l = lengthFt.clamp(1.0, 200.0);
    return ArPlacedItem(
      type: type,
      fromLeftFt: fromLeftFt.abs().clamp(0.0, w),
      fromBottomFt: fromBottomFt.abs().clamp(0.0, l),
    );
  }
}
