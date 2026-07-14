import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';

/// In-app crash/bug feedback with optional screenshots.
///
/// - Always saves a local report (for Share / email with attachments).
/// - Uploads to Firestore `feedback/{id}` when Firebase Auth works.
/// - Uploads images to Storage when the default bucket is configured
///   (requires Firebase Storage “Get Started” + billing on some projects).
class FeedbackService {
  static const maxScreenshots = 5;

  Future<bool> _ensureFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      return true;
    } catch (e) {
      debugPrint('Feedback Firebase init: $e');
      return false;
    }
  }

  Future<User?> _ensureUser() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null) return auth.currentUser;
      return (await auth.signInAnonymously()).user;
    } catch (e) {
      debugPrint('Feedback auth: $e');
      return FirebaseAuth.instance.currentUser;
    }
  }

  Future<({String id, bool cloudOk, bool storageOk, String message})> submit({
    required String category,
    required String message,
    String? contactEmail,
    required List<File> screenshots,
  }) async {
    final id = const Uuid().v4().substring(0, 12);
    final text = message.trim();
    if (text.isEmpty) {
      throw Exception('Please describe what went wrong');
    }

    final meta = <String, dynamic>{
      'id': id,
      'category': category,
      'message': text,
      'contactEmail': contactEmail?.trim() ?? '',
      'appVersion': AppConfig.appVersion,
      'buildNumber': AppConfig.buildNumber,
      'versionLabel': AppConfig.versionLabel,
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'screenshotCount': screenshots.length,
    };

    await _saveLocal(id, meta, screenshots);
    final previews = await _buildPreviews(screenshots);

    var cloudOk = false;
    var storageOk = false;
    final urls = <String>[];
    final notes = <String>[];

    if (await _ensureFirebase()) {
      try {
        await _ensureUser();
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';

        // Best-effort Storage (may fail if bucket not provisioned)
        for (var i = 0; i < screenshots.length; i++) {
          try {
            final file = screenshots[i];
            final ext =
                p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
            final ref = FirebaseStorage.instance
                .ref()
                .child('feedback')
                .child(id)
                .child('shot_$i$ext');
            await ref.putFile(
              file,
              SettableMetadata(contentType: _contentType(ext)),
            );
            urls.add(await ref.getDownloadURL());
            storageOk = true;
          } catch (e) {
            debugPrint('Feedback storage shot $i: $e');
          }
        }
        if (screenshots.isNotEmpty && !storageOk) {
          notes.add(
            'Screenshots saved on device only (Firebase Storage not set up). '
            'Please use Share to send them.',
          );
        }

        await FirebaseFirestore.instance.collection('feedback').doc(id).set({
          ...meta,
          'uid': uid,
          'screenshotUrls': urls,
          'screenshotPreviews': previews,
          'hasLocalScreenshots': screenshots.isNotEmpty,
          'createdAtServer': FieldValue.serverTimestamp(),
        });
        cloudOk = true;
      } catch (e) {
        notes.add('Cloud save failed — use Share to email the report.');
        debugPrint('Feedback cloud: $e');
      }
    } else {
      notes.add('Firebase offline — use Share to email the report.');
    }

    final msg = StringBuffer()
      ..write('Report $id · ${screenshots.length} screenshot(s). ');
    if (cloudOk) {
      msg.write('Details saved to Firebase. ');
    }
    if (storageOk) {
      msg.write('Screenshots uploaded. ');
    }
    if (notes.isNotEmpty) {
      msg.write(notes.join(' '));
    }

    return (
      id: id,
      cloudOk: cloudOk,
      storageOk: storageOk,
      message: msg.toString().trim(),
    );
  }

  Future<Directory> _saveLocal(
    String id,
    Map<String, dynamic> meta,
    List<File> screenshots,
  ) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'feedback', id));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'report.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(meta),
    );
    for (var i = 0; i < screenshots.length; i++) {
      final ext = p.extension(screenshots[i].path).isEmpty
          ? '.jpg'
          : p.extension(screenshots[i].path);
      await screenshots[i].copy(p.join(dir.path, 'shot_$i$ext'));
    }
    return dir;
  }

  Future<void> shareLocalReport(String id) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'feedback', id));
    if (!await dir.exists()) {
      throw Exception('Local report not found');
    }
    final files = <XFile>[];
    await for (final e in dir.list()) {
      if (e is File) files.add(XFile(e.path));
    }
    if (files.isEmpty) throw Exception('Nothing to share');
    await Share.shareXFiles(
      files,
      subject: '${AppConfig.feedbackSubject} [$id]',
      text:
          'RoomCraft feedback report $id\n'
          'Version ${AppConfig.versionLabel}\n'
          'To: ${AppConfig.feedbackEmail}\n\n'
          'Screenshots attached for crash/error diagnosis.',
    );
  }


  /// Small JPEG data-URLs for Firestore when Storage is unavailable (max 3).
  Future<List<String>> _buildPreviews(List<File> screenshots) async {
    final out = <String>[];
    for (final file in screenshots.take(3)) {
      try {
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        final thumb = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 480 : null,
          height: decoded.height > decoded.width ? 480 : null,
        );
        final jpg = img.encodeJpg(thumb, quality: 55);
        if (jpg.length > 180000) continue; // skip huge
        out.add('data:image/jpeg;base64,${base64Encode(jpg)}');
      } catch (e) {
        debugPrint('preview: $e');
      }
    }
    return out;
  }

  String _contentType(String ext) {
    switch (ext.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
