import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/ai_scanner_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final key = await AIScannerService.loadApiKey();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = key ?? '';
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
          const Text(
            'Gemini API Key',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Required for AI Room Scanning. Get a free key at aistudio.google.com. '
            'Your key is stored only on this device (MVP). Photos are sent to Google Gemini when you scan.',
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
          const Divider(height: 48),
          const Text(
            'Privacy & Legal',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip, color: Colors.blue),
            title: const Text('Read Privacy Policy'),
            subtitle: const Text('Camera & AI photo processing'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: _launchPrivacyPolicy,
          ),
          const Divider(height: 48),
          Text(
            '${AppConfig.appName} 1.0.0+1 · MVP Phase 0',
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

  Future<void> _launchPrivacyPolicy() async {
    const url =
        'https://raw.githubusercontent.com/tmai-tech/RoomCraft/dev/PRIVACY_POLICY.md';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the privacy policy link.')),
      );
    }
  }
}
