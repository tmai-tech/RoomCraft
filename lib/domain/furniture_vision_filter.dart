/// Filters raw vision JSON furniture lists to reduce model hallucination
/// while preserving recall of clearly visible pieces.
class FurnitureVisionFilter {
  /// Keep threshold for free vision (was 0.80 — dropped real furniture).
  /// Feedback showed 0 furniture / sparse plans; 0.55 restores recall.
  static const double minConfidence = 0.55;

  /// Soft floor when model omits confidence but provides type + position.
  static const double defaultConfidenceWhenTyped = 0.65;

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

      final type = m['type']?.toString();
      if (type == null || type.trim().isEmpty) {
        dropped++;
        continue;
      }

      final confRaw = m['confidence'] ?? m['conf'] ?? m['score'];
      double? conf;
      if (confRaw is num) conf = confRaw.toDouble();
      if (confRaw is String) conf = double.tryParse(confRaw);

      if (conf == null) {
        final evidence = (m['evidence'] ?? m['why'] ?? m['seenAs'])?.toString();
        final hasPos = m['pos'] != null || m['position'] != null;
        final hasDim = m['dim'] != null || m['size'] != null;
        if (evidence != null && evidence.trim().length >= 6) {
          conf = 0.70;
        } else if (hasPos || hasDim) {
          // Typed + placed — keep with moderate default (models often omit conf).
          conf = defaultConfidenceWhenTyped;
        } else {
          dropped++;
          continue;
        }
        m['confidence'] = conf;
      }

      if (conf < minConfidence) {
        dropped++;
        continue;
      }

      kept.add(m);
    }

    return (kept: kept, dropped: dropped);
  }
}
