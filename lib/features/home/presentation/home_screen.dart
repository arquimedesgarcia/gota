import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../leaks/presentation/leak_report_controller.dart';
import '../../leaks/presentation/leak_report_screen.dart';
import '../../leaks/presentation/recent_leaks_list.dart';

/// Pantalla principal: estado de agua, acciones principales y secciones
/// comunitarias (por ahora con estados vacíos honestos).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _soonMessage = 'Esta función estará disponible próximamente.';

  void _showSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(_soonMessage)),
    );
  }

  void _openReport(BuildContext context) {
    // Reinicia el borrador para este nuevo reporte.
    final container = ProviderScope.containerOf(context, listen: false);
    container.invalidate(leakReportProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const LeakReportScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _GotaHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _WaterStatusCard(),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _openReport(context),
                      child: const Text('Reportar fuga'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => _showSoon(context),
                      child: const Text('Llegó / Se fue el agua'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Fugas cerca de ti', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const RecentLeaksList(),
                  const SizedBox(height: 24),
                  Text('Resumen comunitario', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const _EmptyStateCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GotaHeader extends StatelessWidget {
  const _GotaHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primaryDark,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          const Icon(Icons.water_drop, color: Colors.white, size: 28),
          const SizedBox(width: 8),
          Text(
            'GOTA',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
          ),
        ],
      ),
    );
  }
}

class _WaterStatusCard extends StatelessWidget {
  const _WaterStatusCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warning,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado de agua',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sin datos todavía',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Sin datos todavía',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      ),
    );
  }
}
