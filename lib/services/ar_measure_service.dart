import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result of an ARCore guided floor measure (width × length).
class ArRoomMeasure {
  final double widthFt;
  final double lengthFt;
  final double widthM;
  final double lengthM;
  final String source;

  const ArRoomMeasure({
    required this.widthFt,
    required this.lengthFt,
    required this.widthM,
    required this.lengthM,
    this.source = 'arcore',
  });

  factory ArRoomMeasure.fromMap(Map<dynamic, dynamic> map) {
    return ArRoomMeasure(
      widthFt: (map['widthFt'] as num).toDouble(),
      lengthFt: (map['lengthFt'] as num).toDouble(),
      widthM: (map['widthM'] as num?)?.toDouble() ?? 0,
      lengthM: (map['lengthM'] as num?)?.toDouble() ?? 0,
      source: map['source']?.toString() ?? 'arcore',
    );
  }

  /// Swap so width is the larger dimension when useful for display.
  ArRoomMeasure get normalized {
    if (widthFt >= lengthFt) return this;
    return ArRoomMeasure(
      widthFt: lengthFt,
      lengthFt: widthFt,
      widthM: lengthM,
      lengthM: widthM,
      source: source,
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

  /// Probe ARCore support (does not open camera).
  static Future<ArAvailability> isAvailable() async {
    if (!isPlatformSupported) {
      return const ArAvailability(
        supported: false,
        installNeeded: false,
        message: 'AR measure is available on Android devices with ARCore',
      );
    }
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('isAvailable');
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

  /// Opens native AR UI. User taps floor corners for width, then length.
  /// Throws [PlatformException] on cancel or failure.
  static Future<ArRoomMeasure> measureRoom() async {
    if (!isPlatformSupported) {
      throw PlatformException(
        code: 'UNSUPPORTED',
        message: 'AR measure requires Android + ARCore',
      );
    }
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('measureRoom');
    if (raw == null) {
      throw PlatformException(code: 'EMPTY', message: 'No measure result');
    }
    final m = ArRoomMeasure.fromMap(raw);
    if (m.widthFt < 1.5 || m.lengthFt < 1.5) {
      throw PlatformException(
        code: 'TOO_SMALL',
        message: 'Measured size looks too small — try again with clearer floor tracking',
      );
    }
    if (m.widthFt > 80 || m.lengthFt > 80) {
      throw PlatformException(
        code: 'TOO_LARGE',
        message: 'Measured size looks unrealistic — retake with both ends on the floor grid',
      );
    }
    return m;
  }
}
