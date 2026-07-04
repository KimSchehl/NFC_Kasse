import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/dialogs/update_dialog.dart';
import '../widgets/help_button.dart';
import 'account_screen.dart';
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
    };

    final body = switch (currentScreen) {
      AppScreen.pos => const PosScreen(),
      AppScreen.stats => const StatsScreen(),
      AppScreen.users => const UsersScreen(),
      AppScreen.settings => const SettingsScreen(),
      AppScreen.account => const AccountScreen(),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                const AppSidebar(),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(screenTitle),
                      centerTitle: false,
                      automaticallyImplyLeading: false,
                      actions: [
                        const HelpButton(),
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
