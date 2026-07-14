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
  /// `quick` (W×L) or `chain` (4 walls A–D).
  final String mode;
  /// Per-wall lengths in feet (A,B[,C,D]).
  final List<double> wallsFt;
  final List<double> wallsM;

  const ArRoomMeasure({
    required this.widthFt,
    required this.lengthFt,
    required this.widthM,
    required this.lengthM,
    this.source = 'arcore',
    this.mode = 'quick',
    this.wallsFt = const [],
    this.wallsM = const [],
  });

  factory ArRoomMeasure.fromMap(Map<dynamic, dynamic> map) {
    List<double> asDoubles(dynamic v) {
      if (v is! List) return const [];
      return v.map((e) => (e as num).toDouble()).toList();
    }

    return ArRoomMeasure(
      widthFt: (map['widthFt'] as num).toDouble(),
      lengthFt: (map['lengthFt'] as num).toDouble(),
      widthM: (map['widthM'] as num?)?.toDouble() ?? 0,
      lengthM: (map['lengthM'] as num?)?.toDouble() ?? 0,
      source: map['source']?.toString() ?? 'arcore',
      mode: map['mode']?.toString() ?? 'quick',
      wallsFt: asDoubles(map['wallsFt']),
      wallsM: asDoubles(map['wallsM']),
    );
  }

  bool get isChain => mode == 'chain' && wallsFt.length >= 4;

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
    if (isChain) {
      return '$base · 4-wall AR chain';
    }
    return '$base · AR quick';
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
      final raw =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('isAvailable');
      if (raw == null) {
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

  /// [mode]: `quick` (width+length) or `chain` (four walls A→D).
  static Future<ArRoomMeasure> measureRoom({String mode = 'quick'}) async {
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
}
