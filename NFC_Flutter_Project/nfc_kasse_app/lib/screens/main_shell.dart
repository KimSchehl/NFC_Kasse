import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/app_sidebar.dart';
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
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          // Persistent side rail on tablets
          return Scaffold(
            body: Row(
              children: [
                const AppSidebar(),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        } else {
          // Drawer on phones
          return Scaffold(
            appBar: AppBar(
              title: Text(screenTitle),
              centerTitle: false,
            ),
            drawer: const Drawer(child: AppSidebar()),
            body: body,
          );
        }
      },
    );
  }
}
