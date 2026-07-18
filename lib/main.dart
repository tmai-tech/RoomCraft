import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/analytics_service.dart';
import 'services/prefs_service.dart';
import 'services/secure_key_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort: analytics + key migration must never block launch.
  try {
    await SecureKeyStore().migrateFromPrefsIfNeeded();
  } catch (_) {}
  try {
    await AnalyticsService.instance.init();
  } catch (_) {}
  runApp(const ProviderScope(child: RoomCraftApp()));
}

class RoomCraftApp extends StatefulWidget {
  const RoomCraftApp({super.key});

  @override
  State<RoomCraftApp> createState() => RoomCraftAppState();

  /// Allow Settings to flip theme without full restart.
  static RoomCraftAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<RoomCraftAppState>();
  }
}

class RoomCraftAppState extends State<RoomCraftApp> {
  ThemeMode _themeMode = ThemeMode.system;
  final _prefs = PrefsService();

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final mode = await _prefs.loadThemeMode();
    if (!mounted) return;
    setState(() => _themeMode = mode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await _prefs.saveThemeMode(mode);
  }

  ThemeMode get themeMode => _themeMode;

  @override
  Widget build(BuildContext context) {
    final seed = Colors.blueGrey;
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _AppBootstrap(),
    );
  }
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late final Future<bool> _onboardingDone;

  @override
  void initState() {
    super.initState();
    _onboardingDone = PrefsService().isOnboardingDone();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _onboardingDone,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final done = snap.data ?? false;
        return done ? const HomeScreen() : const OnboardingScreen();
      },
    );
  }
}
