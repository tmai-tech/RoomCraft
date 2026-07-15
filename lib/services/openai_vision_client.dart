import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';

/// Shared OpenAI-compatible multimodal chat client (Groq, HF router, etc.).
class OpenAiVisionClient {
  OpenAiVisionClient({
    required this.chatCompletionsUrl,
    required this.model,
    this.timeout = const Duration(seconds: 90),
    this.maxImageSide = 1280,
    this.jpegQuality = 88,
  });

  final String chatCompletionsUrl;
  final String model;
  final Duration timeout;
  final int maxImageSide;
  final int jpegQuality;

  Future<Map<String, dynamic>> completeJson({
    required String apiKey,
    required List<File> frames,
    required String prompt,
    required String system,
    double temperature = 0.05,
  }) async {
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
    ];

    for (final image in frames) {
      final prepared = await prepareImageDataUrl(image);
      if (prepared == null) continue;
      content.add({
        'type': 'image_url',
        'image_url': {'url': prepared},
      });
    }
    if (content.length < 2) {
      throw Exception('Could not read any frames');
    }

    final body = {
      'model': model,
      'temperature': temperature,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': content},
      ],
    };

    final response = await http
        .post(
          Uri.parse(chatCompletionsUrl),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('Vision key rejected (${response.statusCode})');
    }
    if (response.statusCode == 429) {
      throw Exception('Vision rate limit — try again shortly');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Vision error ${response.statusCode}: ${_short(response.body)}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('Vision returned no choices');
    }
    final message = (choices.first as Map)['message'];
    final text = message is Map ? message['content']?.toString() : null;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Vision returned empty content');
    }
    return extractJsonMap(text);
  }

  Future<String?> prepareImageDataUrl(File image) async {
    try {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) return null;
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        final mime = lookupMimeType(image.path) ?? 'image/jpeg';
        return 'data:$mime;base64,${base64Encode(bytes)}';
      }
      var frame = decoded;
      if (frame.width > maxImageSide || frame.height > maxImageSide) {
        frame = frame.width >= frame.height
            ? img.copyResize(frame, width: maxImageSide)
            : img.copyResize(frame, height: maxImageSide);
      }
      final jpg = Uint8List.fromList(img.encodeJpg(frame, quality: jpegQuality));
      return 'data:image/jpeg;base64,${base64Encode(jpg)}';
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> extractJsonMap(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      t = t.replaceFirst(RegExp(r'\s*```$'), '');
    }
    // Some providers wrap JSON in prose — take first object span.
    final start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    if (start >= 0 && end > start) {
      t = t.substring(start, end + 1);
    }
    final decoded = jsonDecode(t);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception('Vision JSON was not an object');
  }

  static String _short(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= 160) return t;
    return '${t.substring(0, 160)}…';
  }
}
