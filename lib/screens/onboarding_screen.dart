import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/prefs_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      icon: Icons.camera_alt_outlined,
      title: 'Scan your room',
      body:
          'Best: AR measure — tap floor corners for real-world size (no tape). Or film a walkaround for AI layout. Not LiDAR/CAD — tweak in Review if needed.',
    ),
    (
      icon: Icons.dashboard_customize_outlined,
      title: 'Arrange furniture',
      body:
          'Drag, rotate, and snap pieces. Collision and layout score help clear walkways. Auto-arrange suggests a bedroom, living, or office layout.',
    ),
    (
      icon: Icons.ios_share,
      title: 'Export & share',
      body:
          'Save plans on this device and export a PNG for family or contractors. Feedback helps us improve accuracy every build.',
    ),
  ];

  Future<void> _finish() async {
    await PrefsService().setOnboardingDone(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (ctx, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: Colors.blueGrey.shade50,
                          child: Icon(p.icon, size: 48, color: Colors.blueGrey.shade700),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          p.title,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.body,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Colors.black54,
                                height: 1.4,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page ? Colors.blueGrey : Colors.grey.shade300,
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  if (_page < _pages.length - 1) {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                    );
                  } else {
                    _finish();
                  }
                },
                child: Text(_page < _pages.length - 1 ? 'Next' : 'Get started'),
              ),
            ),
            Text(
              AppConfig.appName,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
