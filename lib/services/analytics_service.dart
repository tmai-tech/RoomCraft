import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Light funnel analytics. No-ops when Firebase is unavailable (tests / offline).
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  bool _ready = false;
  bool _initAttempted = false;

  /// Call once at app start. Safe if Firebase is not configured.
  Future<void> init() async {
    if (_initAttempted) return;
    _initAttempted = true;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _analytics = FirebaseAnalytics.instance;
      _ready = true;
      await logEvent('app_open');
    } catch (e) {
      _ready = false;
      debugPrint('Analytics unavailable: $e');
    }
  }

  Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    if (!_ready || _analytics == null) {
      if (kDebugMode) {
        debugPrint('analytics[$name] ${params ?? {}}');
      }
      return;
    }
    try {
      await _analytics!.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('analytics log failed: $e');
    }
  }

  Future<void> scanStart({required String mode}) =>
      logEvent('scan_start', {'mode': mode});

  Future<void> scanSuccess({
    required String mode,
    required int furnitureCount,
    required bool emptyFurniture,
  }) =>
      logEvent('scan_success', {
        'mode': mode,
        'furniture_count': furnitureCount,
        'empty_furniture': emptyFurniture ? 1 : 0,
      });

  Future<void> scanFail({required String mode, required String reason}) =>
      logEvent('scan_fail', {
        'mode': mode,
        'reason': reason.length > 80 ? reason.substring(0, 80) : reason,
      });

  Future<void> autoArrange({required String type}) =>
      logEvent('auto_arrange', {'type': type});

  Future<void> exportPng() => logEvent('export');

  Future<void> openEditorFromScan() => logEvent('open_editor_from_scan');
}
