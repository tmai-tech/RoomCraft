/// Filters raw vision JSON furniture lists to reduce model hallucination.
class FurnitureVisionFilter {
  /// Raised from 0.72 — free vision was inventing random freeform pieces.
  static const double minConfidence = 0.80;

  /// Returns kept furniture maps and count dropped.
  static ({List<Map<String, dynamic>> kept, int dropped}) filter(
    List<dynamic>? raw, {
    double minConfidence = FurnitureVisionFilter.minConfidence,
  }) {
    if (raw == null) return (kept: <Map<String, dynamic>>[], dropped: 0);

    final kept = <Map<String, dynamic>>[];
    var dropped = 0;

    for (final item in raw) {
      if (item is! Map) {
        dropped++;
        continue;
      }
      final m = Map<String, dynamic>.from(item);

      final confRaw = m['confidence'] ?? m['conf'] ?? m['score'];
      double? conf;
      if (confRaw is num) conf = confRaw.toDouble();
      if (confRaw is String) conf = double.tryParse(confRaw);

      if (conf == null) {
        final evidence = (m['evidence'] ?? m['why'] ?? m['seenAs'])?.toString();
        if (evidence == null || evidence.trim().length < 8) {
          dropped++;
          continue;
        }
        conf = 0.75;
      }

      if (conf < minConfidence) {
        dropped++;
        continue;
      }

      final type = m['type']?.toString();
      if (type == null || type.trim().isEmpty) {
        dropped++;
        continue;
      }

      kept.add(m);
    }

    return (kept: kept, dropped: dropped);
  }
}
