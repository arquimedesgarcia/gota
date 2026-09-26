import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../features/notifications/data/daily_digest_service.dart';
import '../../features/home/presentation/community_summary_providers.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/leaks/presentation/leak_community_providers.dart';
import '../../features/leaks/presentation/leak_report_controller.dart';
import '../../features/leaks/presentation/leak_report_screen.dart';
import '../../features/leaks/presentation/recent_activity_providers.dart';
import '../../features/map/presentation/map_providers.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/notifications/presentation/settings_screen.dart';
import '../../features/water/presentation/water_screen.dart';
import '../../shared/widgets/placeholder_screen.dart';

/// Notifier para la navegación entre pestañas del shell.
class _ShellTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setTab(int index) {
    state = index;
  }
}

/// Provider que permite a cualquier widget dentro del árbol solicitar
/// un cambio de pestaña del shell. [AppShell] escucha los cambios y
/// actualiza [_index] en consecuencia. Se mantiene en sincronía con
/// la pestaña activa real para que cambios repetidos al mismo valor
/// no sean ignorados por el listener.
final shellTabProvider = NotifierProvider<_ShellTabNotifier, int>(
  _ShellTabNotifier.new,
);

/// Shell de navegación con cinco posiciones:
/// Inicio · Mapa · Reportar (acción central) · Agua · Más.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    MapScreen(),
    PlaceholderScreen(title: 'Reportar'),
    WaterScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Sincroniza el provider con el índice inicial.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(shellTabProvider.notifier).setTab(_index);
    });
  }

  /// Abre el flujo completo de Reportar fuga.
  Future<void> _openReportFlow() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const LeakReportScreen(),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    if (created == true) {
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(recentLeaksProvider);
      container.invalidate(communitySummaryProvider);
      container.invalidate(latestActivityProvider);
      container.invalidate(mapReportsProvider);
    }
    _resetLeakReportDraft();
  }

  void _resetLeakReportDraft() {
    final container = ProviderScope.containerOf(context, listen: false);
    container.invalidate(leakReportProvider);
  }

  void _onDestinationSelected(int index) {
    if (index == 2) {
      _openReportFlow();
      return;
    }
    setState(() => _index = index);
    // Sincroniza el provider para que el listener no vuelva a dispararse.
    ref.read(shellTabProvider.notifier).setTab(index);
  }

  @override
  Widget build(BuildContext context) {
    // Escucha solicitudes de navegación de pestaña desde widgets hijos.
    ref.listen<int>(shellTabProvider, (prev, next) {
      if (_index != next) setState(() => _index = next);
    });

    // Arranca el servicio de resumen diario (notificación a las 8 pm).
    ref.watch(dailyDigestBootstrapProvider);

    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
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
          NavigationDestination(icon: Icon(Icons.menu), label: 'Más'),
        ],
      ),
    );
  }
}
