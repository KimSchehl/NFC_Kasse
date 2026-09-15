import 'package:flutter/material.dart';

import 'bon_layout_screen.dart';
import 'config_screen.dart';
import 'dashboard_screen.dart';
import 'info_screen.dart';

/// Root layout: a persistent NavigationRail (this tool is desktop/admin-only,
/// no phone-narrow layout needed) switching between the four screens.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    ConfigScreen(),
    BonLayoutScreen(),
    InfoScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.point_of_sale, size: 32, color: theme.colorScheme.primary),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Konfiguration'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('Bon-Layout'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.info_outline),
                selectedIcon: Icon(Icons.info),
                label: Text('Info'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _screens[_index]),
        ],
      ),
    );
  }
}
