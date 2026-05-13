import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config/api_config.dart';
import 'providers/providers.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore the server URL the user last entered, or fall back to the default.
  const storage = FlutterSecureStorage();
  final savedUrl = await storage.read(key: 'server_url');
  final initialUrl = (savedUrl != null && savedUrl.isNotEmpty)
      ? savedUrl
      : ApiConfig.defaultBaseUrl;

  runApp(ProviderScope(
    overrides: [
      serverUrlProvider.overrideWith((ref) => initialUrl),
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
    return MaterialApp(
      title: 'NFC Kasse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
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
