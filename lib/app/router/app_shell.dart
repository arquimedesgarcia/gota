import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/leaks/presentation/leak_report_controller.dart';
import '../../features/leaks/presentation/leak_report_screen.dart';
import '../../features/water/presentation/water_screen.dart';
import '../../shared/widgets/placeholder_screen.dart';

/// Shell de navegación con cinco posiciones:
/// Inicio · Mapa · Reportar (acción central) · Agua · Más.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void resetLeakReportDraft() {
    // Reinicia el borrador del reporte para el próximo flujo.
    final container =
        ProviderScope.containerOf(context, listen: false);
    container.invalidate(leakReportProvider);
  }

  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    PlaceholderScreen(title: 'Mapa'),
    PlaceholderScreen(title: 'Reportar'),
    WaterScreen(),
    PlaceholderScreen(title: 'Más'),
  ];

  /// Abre el flujo completo de Reportar fuga (Sprint 02) y reinicia el
  /// borrador al volver, para que el próximo reporte empiece limpio.
  Future<void> _openReportFlow() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LeakReportScreen(),
        fullscreenDialog: true,
      ),
    );
    if (mounted) {
      resetLeakReportDraft();
    }
  }

  void _onDestinationSelected(int index) {
    if (index == 2) {
      // "Reportar" es una acción, no un destino navegable.
      _openReportFlow();
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Reportar',
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        onPressed: _openReportFlow,
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
