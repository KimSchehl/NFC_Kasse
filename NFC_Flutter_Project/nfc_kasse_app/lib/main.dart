import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/api_config.dart';
import 'providers/providers.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/app_storage.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService().init();

  final prefs = await SharedPreferences.getInstance();
  final storage = AppStorage(prefs);

  // Restore server URL.
  final savedUrl = await storage.read(key: 'server_url');
  final initialUrl = (savedUrl != null && savedUrl.isNotEmpty)
      ? savedUrl
      : ApiConfig.defaultBaseUrl;

  // Restore display settings.
  final textScaleStr = await storage.read(key: 'display_textScale');
  final gridColumnsStr = await storage.read(key: 'display_gridColumns');
  final cartTextScaleStr = await storage.read(key: 'display_cartTextScale');
  final buttonMaxLinesStr = await storage.read(key: 'display_buttonMaxLines');
  final initialTextScale = double.tryParse(textScaleStr ?? '') ?? 1.0;
  final initialGridColumns = int.tryParse(gridColumnsStr ?? '') ?? 3;
  final initialCartTextScale = double.tryParse(cartTextScaleStr ?? '') ?? 1.0;
  final initialButtonMaxLines = int.tryParse(buttonMaxLinesStr ?? '') ?? 2;

  runApp(ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      serverUrlProvider.overrideWith((ref) => initialUrl),
      textScaleProvider.overrideWith((ref) => initialTextScale),
      gridColumnsProvider.overrideWith((ref) => initialGridColumns),
      cartTextScaleProvider.overrideWith((ref) => initialCartTextScale),
      buttonMaxLinesProvider.overrideWith((ref) => initialButtonMaxLines),
    ],
    child: const NfcKasseApp(),
  ));
}

/// Root widget. ProviderScope is set up in main() so all descendant widgets
/// can access Riverpod providers.
class NfcKasseApp extends ConsumerWidget {
  const NfcKasseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScale = ref.watch(textScaleProvider);
    return MaterialApp(
      title: 'NFC Kasse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: const _AuthGate(),
    );
  }
}

/// Routes between [LoginScreen] and [MainShell] based on the auth state.
///
/// On cold start, [authProvider] checks for stored tokens and tries to restore
/// the session silently — showing a spinner rather than flashing the login
/// screen. If the token is missing or expired, [LoginScreen] is shown.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return auth.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, e) => const LoginScreen(),
      data: (user) => user == null ? const LoginScreen() : const MainShell(),
    );
  }
}
