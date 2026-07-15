import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../domain/units.dart';
import '../services/ai_scanner_service.dart';
import '../services/free_vision_scanner.dart';
import '../services/huggingface_vision_scanner.dart';
import '../services/cloud_sync_service.dart';
import '../services/prefs_service.dart';
import '../services/training_export_service.dart';
import 'feedback_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _geminiKeyController = TextEditingController();
  final _groqKeyController = TextEditingController();
  final _hfKeyController = TextEditingController();
  final _prefs = PrefsService();
  UnitSystem _units = UnitSystem.feet;
  final _cloud = CloudSyncService();
  bool _cloudBusy = false;
  String? _cloudUserEmail;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final gemini = await AIScannerService.loadApiKey();
    final groq = await FreeVisionScanner.loadApiKey();
    final hf = await HuggingFaceVisionScanner.loadApiKey();
    final units = await _prefs.loadUnitSystem();
    await _cloud.ensureReady();
    if (!mounted) return;
    setState(() {
      _geminiKeyController.text = gemini ?? '';
      _groqKeyController.text = groq ?? '';
      _hfKeyController.text = hf ?? '';
      _units = units;
      _cloudUserEmail = _cloud.currentUser?.email;
    });
  }

  Future<void> _cloudSignIn() async {
    setState(() => _cloudBusy = true);
    try {
      final u = await _cloud.signInWithGoogle();
      if (!mounted) return;
      setState(() => _cloudUserEmail = u?.email);
      if (u != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signed in as ${u.email}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _cloudBackup() async {
    setState(() => _cloudBusy = true);
    try {
      final n = await _cloud.backupAllLocalRooms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backed up $n plan(s) to cloud')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _cloudRestore() async {
    setState(() => _cloudBusy = true);
    try {
      final n = await _cloud.restoreFromCloud();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored $n plan(s) from cloud')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  Future<void> _cloudSignOut() async {
    await _cloud.signOut();
    if (mounted) setState(() => _cloudUserEmail = null);
  }

  Future<void> _saveKeys() async {
    await AIScannerService.saveApiKey(_geminiKeyController.text);
    await FreeVisionScanner.saveApiKey(_groqKeyController.text);
    await HuggingFaceVisionScanner.saveApiKey(_hfKeyController.text);
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
    _hfKeyController.dispose();
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
          Card(
            color: Colors.green.shade50,
            child: const ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.green),
              title: Text('Free accurate scan — no key needed'),
              subtitle: Text(
                'Measured layout sketch (not LiDAR/CAD). Enter exact width × length — '
                'the plan always uses those measurements. Furniture assist uses a '
                'bundled free key when available; otherwise an empty correct plan '
                '(add pieces from the catalog). Optional keys below are stored securely on device.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cloud backup (Phase 1)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _cloudUserEmail == null
                        ? 'Sign in with Google to back up plans across devices. '
                            'Needs Firebase SHA fingerprints + Google provider '
                            '(maintainers: docs/PLAY_AND_SIGNING.md).'
                        : 'Signed in as $_cloudUserEmail',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (_cloudBusy)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    ))
                  else if (_cloudUserEmail == null)
                    FilledButton.icon(
                      onPressed: _cloudSignIn,
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with Google'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _cloudBackup,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('Backup plans to cloud'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _cloudRestore,
                      icon: const Icon(Icons.cloud_download),
                      label: const Text('Restore from cloud'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cloudSignOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Optional keys (advanced)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Not required for free scan. Only paste if you want your own free '
            'vision quota. Room size always stays exact either way.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _groqKeyController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Groq API key (optional free furniture AI)',
              helperText: 'console.groq.com — Llama 4 Scout (primary)',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hfKeyController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Hugging Face token (optional free VLM)',
              helperText:
                  'huggingface.co/settings/tokens — Qwen2.5-VL if Groq empty',
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _geminiKeyController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Gemini API key (optional)',
              helperText: 'aistudio.google.com — third fallback',
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
            'Improve AI accuracy',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ratings and plan snapshots stay on this device until you export them '
            'for model training.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined, color: Colors.teal),
            title: const Text('Export training data'),
            subtitle: const Text('Share JSONL of scan feedback + plans'),
            onTap: () async {
              try {
                final n = await TrainingExportService().eventCount();
                if (!context.mounted) return;
                if (n == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No events yet — rate scans in Review first'),
                    ),
                  );
                  return;
                }
                await TrainingExportService().shareExport();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$e')),
                );
              }
            },
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
            subtitle: const Text('Report bugs with screenshots'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FeedbackScreen()),
              );
            },
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
