import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Extract diverse keyframes from a walkthrough video for room scanning.
class ScanKeyframes {
  /// Sample the video every [intervalMs] up to [maxFrames], skipping near-duplicates.
  static Future<List<File>> fromVideo(
    File video, {
    int maxFrames = 8,
    int intervalMs = 1200,
    int maxDurationMs = 90000,
  }) async {
    if (!await video.exists()) {
      throw Exception('Video file not found');
    }

    final dir = await getTemporaryDirectory();
    final outDir = Directory(
      '${dir.path}/roomcraft_frames_${DateTime.now().millisecondsSinceEpoch}',
    );
    await outDir.create(recursive: true);

    final frames = <File>[];
    final signatures = <List<int>>[];

    for (var t = 0; t < maxDurationMs && frames.length < maxFrames; t += intervalMs) {
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: video.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 1280,
          timeMs: t,
          quality: 85,
        );
        if (bytes == null || bytes.isEmpty) {
          // End of video or decode failure
          if (t > 0) break;
          continue;
        }

        final sig = _signature(bytes);
        if (sig != null && _isDuplicate(sig, signatures)) {
          continue;
        }
        if (sig != null) signatures.add(sig);

        final f = File('${outDir.path}/frame_${frames.length.toString().padLeft(2, '0')}.jpg');
        await f.writeAsBytes(bytes, flush: true);
        frames.add(f);
      } catch (_) {
        if (t > intervalMs * 2) break;
      }
    }

    if (frames.isEmpty) {
      throw Exception(
        'Could not extract frames from video. Try a shorter clip or use still photos.',
      );
    }
    return frames;
  }

  /// Coarse perceptual signature for near-duplicate rejection.
  static List<int>? _signature(Uint8List jpegBytes) {
    try {
      final decoded = img.decodeImage(jpegBytes);
      if (decoded == null) return null;
      final small = img.copyResize(decoded, width: 16, height: 16);
      final sig = <int>[];
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final p = small.getPixel(x, y);
          sig.add(((p.r + p.g + p.b) / 3).round());
        }
      }
      return sig;
    } catch (_) {
      return null;
    }
  }

  static bool _isDuplicate(List<int> sig, List<List<int>> existing) {
    for (final e in existing) {
      if (e.length != sig.length) continue;
      var sum = 0;
      for (var i = 0; i < sig.length; i++) {
        sum += (sig[i] - e[i]).abs();
      }
      final mean = sum / sig.length;
      if (mean < 12) return true; // very similar frames
    }
    return false;
  }

  /// Pick up to [maxKeep] sharpest frames (higher local contrast).
  static Future<List<File>> pickSharpest(List<File> files, {int maxKeep = 6}) async {
    if (files.length <= maxKeep) return files;
    final scored = <({File f, double score})>[];
    for (final f in files) {
      try {
        final bytes = await f.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          scored.add((f: f, score: 0));
          continue;
        }
        scored.add((f: f, score: _sharpness(decoded)));
      } catch (_) {
        scored.add((f: f, score: 0));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(maxKeep).map((e) => e.f).toList();
  }

  static double _sharpness(img.Image im) {
    // Laplacian-ish variance on downscaled grayscale
    final s = img.copyResize(im, width: 64, height: 64);
    var sum = 0.0;
    var sumSq = 0.0;
    var n = 0;
    for (var y = 1; y < s.height - 1; y++) {
      for (var x = 1; x < s.width - 1; x++) {
        final c = s.getPixel(x, y);
        final g = (c.r + c.g + c.b) / 3;
        final l = s.getPixel(x - 1, y);
        final r = s.getPixel(x + 1, y);
        final u = s.getPixel(x, y - 1);
        final d = s.getPixel(x, y + 1);
        final gl = (l.r + l.g + l.b) / 3;
        final gr = (r.r + r.g + r.b) / 3;
        final gu = (u.r + u.g + u.b) / 3;
        final gd = (d.r + d.g + d.b) / 3;
        final lap = (gl + gr + gu + gd - 4 * g).abs();
        sum += lap;
        sumSq += lap * lap;
        n++;
      }
    }
    if (n == 0) return 0;
    final mean = sum / n;
    return math.max(0, sumSq / n - mean * mean);
  }
}
