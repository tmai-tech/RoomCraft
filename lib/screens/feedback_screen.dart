import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/app_config.dart';
import '../services/feedback_service.dart';

/// Bug / crash feedback with optional screenshots for the team to diagnose.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _messageCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _picker = ImagePicker();
  final _service = FeedbackService();

  String _category = 'crash';
  final List<File> _shots = [];
  bool _busy = false;
  String? _lastReportId;

  static const _categories = <String, String>{
    'crash': 'App crash',
    'ar': 'AR measure problem',
    'scan': 'Scan / plan wrong',
    'ui': 'UI / usability',
    'other': 'Other',
  };

  @override
  void dispose() {
    _messageCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _addShot({required bool camera}) async {
    if (_shots.length >= FeedbackService.maxScreenshots) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Max ${FeedbackService.maxScreenshots} screenshots'),
        ),
      );
      return;
    }
    final x = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (x == null) return;
    setState(() => _shots.add(File(x.path)));
  }

  Future<void> _submit() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the problem')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _service.submit(
        category: _category,
        message: msg,
        contactEmail: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text,
        screenshots: List<File>.from(_shots),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastReportId = result.id;
      });
      final share = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(result.cloudOk || result.storageOk ? 'Feedback sent' : 'Feedback saved'),
          content: Text(
            '${result.message}\n\n'
            'Share the report (with screenshots) via email so the team can review?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Done'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Share report'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (share == true) {
        await _service.shareLocalReport(result.id);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send feedback')),
      body: _busy
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Uploading report…'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.blue.shade50,
                  child: const ListTile(
                    leading: Icon(Icons.bug_report_outlined),
                    title: Text('Help us fix issues'),
                    subtitle: Text(
                      'Describe what happened and attach screenshots of the crash, '
                      'error, or wrong plan. The team reviews these to identify bugs.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('What is it about?',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final e in _categories.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
                const SizedBox(height: 16),
                Text('What happened?',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _messageCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'Steps to reproduce, what you expected, what you saw…',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Screenshots (${_shots.length}/${FeedbackService.maxScreenshots})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Crash screens, error messages, or wrong floor plans help most.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _shots.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _shots[i],
                              width: 96,
                              height: 96,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: InkWell(
                              onTap: () => setState(() => _shots.removeAt(i)),
                              child: const CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (_shots.length < FeedbackService.maxScreenshots) ...[
                      OutlinedButton.icon(
                        onPressed: () => _addShot(camera: false),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _addShot(camera: true),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text('Contact email (optional)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'So we can follow up',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'App ${AppConfig.versionLabel} · ${Platform.operatingSystem}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit feedback'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (_lastReportId != null) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () =>
                        _service.shareLocalReport(_lastReportId!),
                    icon: const Icon(Icons.share),
                    label: Text('Share report $_lastReportId again'),
                  ),
                ],
              ],
            ),
    );
  }
}
