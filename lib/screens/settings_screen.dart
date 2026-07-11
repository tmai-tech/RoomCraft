import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../domain/units.dart';
import '../services/ai_scanner_service.dart';
import '../services/prefs_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _prefs = PrefsService();
  UnitSystem _units = UnitSystem.feet;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final key = await AIScannerService.loadApiKey();
    final units = await _prefs.loadUnitSystem();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = key ?? '';
      _units = units;
    });
  }

  Future<void> _saveApiKey() async {
    await AIScannerService.saveApiKey(_apiKeyController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API Key saved successfully!')),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
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
            'Gemini API Key',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional. Room scan works offline for free without a key. '
            'Gemini (if enabled in Scan) needs a key from aistudio.google.com — stored only on this device.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Enter Gemini API Key',
              helperText: 'Paste your API key from Google AI Studio',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveApiKey,
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
          const Divider(height: 32),
          const Text(
            'Privacy & Legal',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip, color: Colors.blue),
            title: const Text('Read Privacy Policy'),
            subtitle: const Text('Camera & AI photo processing'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _openUrl(AppConfig.privacyPolicyUrl),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restart_alt),
            title: const Text('Show onboarding again'),
            onTap: () async {
              await _prefs.setOnboardingDone(false);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Onboarding will show on next app launch'),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            '${AppConfig.appName} ${AppConfig.versionLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          Text(
            AppConfig.packageId,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
        'body':
            'Version: ${AppConfig.versionLabel}\nDevice:\n\nWhat happened?\n\nSteps to reproduce:\n',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email ${AppConfig.feedbackEmail}')),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }
}
