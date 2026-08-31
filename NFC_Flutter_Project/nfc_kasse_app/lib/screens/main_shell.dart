import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/dialogs/update_dialog.dart';
import '../widgets/help_button.dart';
import 'account_screen.dart';
import 'article_admin_screen.dart';
import 'log_viewer_screen.dart';
import 'pos_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'users_screen.dart';

/// Outer shell that holds the navigation structure after login.
///
/// On screens ≥ 600 px wide (tablets) the [AppSidebar] is always visible as a
/// persistent rail. On narrower screens it collapses into a [Drawer] opened via
/// the AppBar hamburger button.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    final info = await ref.read(updateServiceProvider).checkForUpdate();
    if (info != null && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(
          info: info,
          service: ref.read(updateServiceProvider),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentScreen = ref.watch(currentScreenProvider);
    final user = ref.watch(authProvider).valueOrNull;

    final screenTitle = switch (currentScreen) {
      AppScreen.pos => 'Kasse',
      AppScreen.stats => 'Statistik',
      AppScreen.users => 'Benutzer',
      AppScreen.settings => 'Einstellungen',
      AppScreen.account => user?.displayLabel ?? 'Konto',
      AppScreen.logs => 'Protokolle',
      AppScreen.articleAdmin => 'Artikelverwaltung',
    };

    final body = switch (currentScreen) {
      AppScreen.pos => const PosScreen(),
      AppScreen.stats => const StatsScreen(),
      AppScreen.users => const UsersScreen(),
      AppScreen.settings => const SettingsScreen(),
      AppScreen.account => const AccountScreen(),
      AppScreen.logs => const LogViewerScreen(),
      AppScreen.articleAdmin => const ArticleAdminScreen(),
    };

    final sidebarCollapsed = ref.watch(sidebarCollapsedProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                if (!sidebarCollapsed) ...[
                  const AppSidebar(showCollapseButton: true),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(screenTitle),
                      centerTitle: false,
                      automaticallyImplyLeading: false,
                      leading: sidebarCollapsed
                          ? IconButton(
                              icon: const Icon(Icons.menu),
                              tooltip: 'Seitenleiste einblenden',
                              onPressed: () => setSidebarCollapsed(ref, false),
                            )
                          : null,
                      actions: [
                        const HelpButton(),
                        _BleReaderIndicator(),
                        const SizedBox(width: 8),
                        _ConnectionIndicator(),
                        const SizedBox(width: 8),
                      ],
                    ),
                    body: Stack(
                      children: [
                        body,
                        const HelpResponderOverlay(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return Scaffold(
            appBar: AppBar(
              title: Text(screenTitle),
              centerTitle: false,
              actions: [
                const HelpButton(),
                _BleReaderIndicator(),
                const SizedBox(width: 8),
                _ConnectionIndicator(),
                const SizedBox(width: 8),
              ],
            ),
            drawer: const Drawer(child: AppSidebar()),
            body: Stack(
              children: [
                body,
                const HelpResponderOverlay(),
              ],
            ),
          );
        }
      },
    );
  }
}

/// Shows the BLE NFC reader's connection + battery status. Hidden entirely
/// if no reader has ever been paired (Settings → NFC-Lesegerät).
class _BleReaderIndicator extends ConsumerWidget {
  static IconData _batteryIcon(int pct) {
    if (pct >= 95) return Icons.battery_full;
    if (pct >= 80) return Icons.battery_6_bar;
    if (pct >= 65) return Icons.battery_5_bar;
    if (pct >= 50) return Icons.battery_4_bar;
    if (pct >= 35) return Icons.battery_3_bar;
    if (pct >= 20) return Icons.battery_2_bar;
    if (pct >= 10) return Icons.battery_1_bar;
    return Icons.battery_alert;
  }

  static Color _batteryColor(int pct, ColorScheme cs) {
    if (pct <= 10) return cs.error;
    if (pct <= 25) return Colors.orange;
    return cs.onSurface.withValues(alpha: 0.55);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble = ref.watch(bleReaderProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!ble.isPaired) return const SizedBox.shrink();

    final connected = ble.isConnected;
    final battery = ble.batteryPercent;

    return Tooltip(
      message: connected
          ? '${ble.deviceName ?? 'BLE-Lesegerät'} verbunden'
              '${battery != null ? ' · Akku $battery%' : ''}'
          : '${ble.deviceName ?? 'BLE-Lesegerät'} getrennt',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            size: 20,
            color: connected
                ? cs.onSurface.withValues(alpha: 0.4)
                : cs.error,
          ),
          if (connected && battery != null) ...[
            const SizedBox(width: 3),
            Icon(
              _batteryIcon(battery),
              size: 18,
              color: _batteryColor(battery, cs),
            ),
            const SizedBox(width: 1),
            Text(
              '$battery%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _batteryColor(battery, cs),
                fontWeight: battery <= 25 ? FontWeight.bold : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider);
    final theme = Theme.of(context);

    final connected = status.valueOrNull ?? true;

    return Tooltip(
      message: connected ? 'Server erreichbar' : 'Keine Verbindung zum Server',
      child: Icon(
        connected ? Icons.wifi : Icons.wifi_off,
        size: 20,
        color: connected
            ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
            : theme.colorScheme.error,
      ),
    );
  }
}
