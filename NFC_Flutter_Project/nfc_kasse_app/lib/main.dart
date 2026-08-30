import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/api_config.dart';
import 'providers/providers.dart';
import 'screens/kiosk_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/app_logger.dart';
import 'services/app_storage.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'utils/id_generator.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Catches errors Flutter's own framework surfaces (widget build/layout/
    // paint errors) — still shows the usual red error screen via
    // presentError, just also buffers a FATAL entry for shipping.
    FlutterError.onError = (details) {
      AppLogger.fatal(
        details.exceptionAsString(),
        logger: 'flutter',
        error: details.exception,
        stackTrace: details.stack,
      );
      FlutterError.presentError(details);
    };

    // Catches errors escaping the platform-message layer (async callbacks
    // outside any Dart try/catch). Returning true marks it as handled so it
    // doesn't also crash the platform-side process.
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.fatal('Unhandled platform error', logger: 'platform', error: error, stackTrace: stack);
      return true;
    };

    await NotificationService().init();

    final prefs = await SharedPreferences.getInstance();
    final storage = AppStorage(prefs);
    await AppLogger.loadPersisted(prefs);

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
    final initialSidebarCollapsed =
        (await storage.read(key: 'display_sidebarCollapsed')) == 'true';
    final cartWidthStr = await storage.read(key: 'display_cartWidth');
    final pagerWidthStr = await storage.read(key: 'display_pagerWidth');
    final initialCartWidth = double.tryParse(cartWidthStr ?? '') ?? 300.0;
    final initialPagerWidth = double.tryParse(pagerWidthStr ?? '') ?? 260.0;

    // Restore (or generate + persist once) this device's stable log-correlation ID.
    var deviceId = await storage.read(key: 'log_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = generateId('dev');
      await storage.write(key: 'log_device_id', value: deviceId);
    }
    final initialLogLevel = LogLevel.fromLabel(await storage.read(key: 'log_local_level'));
    final initialDeviceLabel = await storage.read(key: 'log_device_label');

    runApp(ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        serverUrlProvider.overrideWith((ref) => initialUrl),
        textScaleProvider.overrideWith((ref) => initialTextScale),
        gridColumnsProvider.overrideWith((ref) => initialGridColumns),
        cartTextScaleProvider.overrideWith((ref) => initialCartTextScale),
        buttonMaxLinesProvider.overrideWith((ref) => initialButtonMaxLines),
        sidebarCollapsedProvider.overrideWith((ref) => initialSidebarCollapsed),
        cartWidthProvider.overrideWith((ref) => initialCartWidth),
        pagerWidthProvider.overrideWith((ref) => initialPagerWidth),
        deviceIdProvider.overrideWith((ref) => deviceId!),
        localLogLevelProvider.overrideWith((ref) => initialLogLevel),
        deviceLabelProvider.overrideWith((ref) => initialDeviceLabel),
      ],
      child: const NfcKasseApp(),
    ));
  }, (error, stack) {
    AppLogger.fatal('Uncaught zone error', logger: 'zone', error: error, stackTrace: stack);
  });
}

/// Root widget. ProviderScope is set up in main() so all descendant widgets
/// can access Riverpod providers.
class NfcKasseApp extends ConsumerWidget {
  const NfcKasseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textScale = ref.watch(textScaleProvider);
    // Must be read here rather than after login, so the shipping timer is
    // already running (and can eager-flush a login failure) before the user
    // ever reaches the login screen.
    ref.watch(loggingProvider);
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
      data: (user) {
        if (user == null) return const LoginScreen();
        if (user.isKiosk) return const KioskScreen();
        return const MainShell();
      },
    );
  }
}
