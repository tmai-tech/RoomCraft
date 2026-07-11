import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../domain/units.dart';
import '../services/ai_scanner_service.dart';
import '../services/free_vision_scanner.dart';
import '../services/prefs_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _geminiKeyController = TextEditingController();
  final _groqKeyController = TextEditingController();
  final _prefs = PrefsService();
  UnitSystem _units = UnitSystem.feet;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final gemini = await AIScannerService.loadApiKey();
    final groq = await FreeVisionScanner.loadApiKey();
    final units = await _prefs.loadUnitSystem();
    if (!mounted) return;
    setState(() {
      _geminiKeyController.text = gemini ?? '';
      _groqKeyController.text = groq ?? '';
      _units = units;
    });
  }

  Future<void> _saveKeys() async {
    await AIScannerService.saveApiKey(_geminiKeyController.text);
    await FreeVisionScanner.saveApiKey(_groqKeyController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  void dispose() {
    _geminiKeyController.dispose();
    _groqKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          if (AppConfig.isBeta) ...[
            Card(
              color: Colors.amber.shade50,
              child: const ListTile(
                leading: Icon(Icons.science_outlined),
                title: Text('Closed beta'),
                subtitle: Text(
                  'Features may change. Plans stay on this device. Thanks for testing!',
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Free AI (Groq) — recommended',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional free vision for real furniture from photos (Llama 4 Scout). '
            'Get a free key at console.groq.com. Room width × length always stay exact. '
            'Stored only on this device.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _groqKeyController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Groq API key (free)',
              helperText: 'console.groq.com → API Keys',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          const Text(
            'Gemini API key (optional)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional. Offline scan works without any key. '
            'Gemini needs a key from aistudio.google.com.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _geminiKeyController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Gemini API key',
              helperText: 'Paste from Google AI Studio',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveKeys,
              child: const Text('Save Settings'),
            ),
          ),
          const Divider(height: 32),
          const Text(
            'Units',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<UnitSystem>(
            segments: const [
              ButtonSegment(value: UnitSystem.feet, label: Text('Feet (ft)')),
              ButtonSegment(value: UnitSystem.meters, label: Text('Meters (m)')),
            ],
            selected: {_units},
            onSelectionChanged: (s) async {
              final u = s.first;
              setState(() => _units = u);
              await _prefs.saveUnitSystem(u);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Internal layout stays in feet; labels convert for display.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const Divider(height: 32),
          const Text(
            'Support',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.feedback_outlined, color: Colors.blue),
            title: const Text('Send feedback'),
            subtitle: const Text('Email the beta team'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: _sendFeedback,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.new_releases_outlined),
            title: const Text("What's new"),
            subtitle: Text(AppConfig.versionLabel),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _openUrl(AppConfig.changelogUrl),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Known issues'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _openUrl(AppConfig.knownIssuesUrl),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _openUrl(AppConfig.privacyPolicyUrl),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restart_alt),
            title: const Text('Replay onboarding'),
            onTap: () async {
              await _prefs.setOnboardingDone(false);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Onboarding will show on next launch'),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            AppConfig.versionLabel,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.feedbackEmail,
      queryParameters: {
        'subject': AppConfig.feedbackSubject,
        'body': 'App version: ${AppConfig.versionLabel}\n\n',
      },
    );
    await _openUri(uri);
  }

  Future<void> _openUrl(String url) async {
    await _openUri(Uri.parse(url));
  }

  Future<void> _openUri(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $uri')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }
}
