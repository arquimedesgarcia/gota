import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../shared/widgets/placeholder_screen.dart';

/// Shell de navegación con cinco posiciones:
/// Inicio · Mapa · Reportar (acción central) · Agua · Más.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _soonMessage = 'Esta función estará disponible próximamente.';

  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    PlaceholderScreen(title: 'Mapa'),
    PlaceholderScreen(title: 'Reportar'),
    PlaceholderScreen(title: 'Agua'),
    PlaceholderScreen(title: 'Más'),
  ];

  void _onDestinationSelected(int index) {
    if (index == 2) {
      // "Reportar" es una acción, no un destino navegable todavía.
      _showSoon();
      return;
    }
    setState(() => _index = index);
  }

  void _showSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(_soonMessage)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Reportar',
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: _showSoon,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Mapa',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline, color: AppColors.accent),
            label: 'Reportar',
          ),
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: 'Agua',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}
