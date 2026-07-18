import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// In-app privacy + Play Data safety summary (free / store-readiness path).
class PrivacyDataSafetyScreen extends StatelessWidget {
  const PrivacyDataSafetyScreen({super.key});

  Future<void> _openPolicy() async {
    final uri = Uri.parse(AppConfig.privacyPolicyUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & data safety')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'RoomCraft ${AppConfig.versionLabel}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Plain-language summary for testers and Play Data safety. '
            'Full legal text is linked below.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _section(
            context,
            icon: Icons.phone_android,
            title: 'Data stored on your device',
            body:
                'Blueprints, furniture layouts, units, and optional API keys '
                'stay in local app storage. Deleting the app removes them.',
          ),
          _section(
            context,
            icon: Icons.photo_camera,
            title: 'Camera & photos',
            body:
                'Camera is used for AR measure / place (ARCore) and optional '
                'photo scan. Offline accurate plan does not upload photos. '
                'Optional free vision assist may send photos to Groq and/or '
                'Gemini only when you use that mode.',
          ),
          _section(
            context,
            icon: Icons.cloud_outlined,
            title: 'Cloud (optional)',
            body:
                'Google Sign-In + Firestore backup is optional. Feedback you '
                'submit may include version, device OS, and text/screenshots '
                'you attach. Firebase App Distribution is used for beta installs.',
          ),
          _section(
            context,
            icon: Icons.analytics_outlined,
            title: 'Analytics',
            body:
                'Lightweight product events (e.g. scan start, export) may be '
                'logged to improve the beta. No advertising ID sale.',
          ),
          _section(
            context,
            icon: Icons.shield_outlined,
            title: 'What we do not do',
            body:
                'We do not sell personal data. We do not run a permanent photo '
                'archive of your rooms on RoomCraft servers.',
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('privacy_open_full_policy'),
            onPressed: _openPolicy,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open full privacy policy'),
          ),
          const SizedBox(height: 12),
          Text(
            'Contact: ${AppConfig.feedbackEmail}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.teal.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(body, style: const TextStyle(fontSize: 13, height: 1.35)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
