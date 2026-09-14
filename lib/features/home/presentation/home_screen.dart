import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/app_components.dart';
import '../../leaks/presentation/leak_report_controller.dart';
import '../../leaks/presentation/leak_report_screen.dart';
import '../../leaks/presentation/recent_leaks_list.dart';

/// Pantalla principal: estado de agua, acciones principales y secciones
/// comunitarias (por ahora con estados vacíos honestos).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _soonMessage = 'Esta función estará disponible próximamente.';

  void _showSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(_soonMessage)));
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
                padding: EdgeInsets.all(AppSpacing.lg),
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: AppComponents.largeButtonStyle(
                        backgroundColor: AppColors.accent,
                      ),
                      onPressed: () => _openReport(context),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reportar fuga',
                                  style: textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Toma menos de un minuto',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: AppSpacing.md),
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1.0,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _ActionCard(
                        icon: Icons.water_drop_outlined,
                        label: 'Llegó / Se fue\nel agua',
                        color: AppColors.success,
                        onTap: () => _showSoon(context),
                      ),
                      _ActionCard(
                        icon: Icons.map_outlined,
                        label: 'Mapa de\nfugas',
                        color: AppColors.primary,
                        onTap: () => Navigator.of(context)
                            .pushNamed('/map'), // placeholder
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpacing.lg),
                  const _CommunityStatsCard(),
                  SizedBox(height: AppSpacing.lg),
                  Text('Fugas cerca de ti', style: textTheme.titleLarge),
                  SizedBox(height: AppSpacing.sm),
                  const RecentLeaksList(),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 1.0],
          colors: [AppColors.primaryDark, AppColors.primary],
          transform: GradientRotation(170 * 3.14159 / 180),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white,
                ),
                child: const Icon(
                  Icons.water_drop,
                  color: AppColors.primaryDark,
                  size: 20,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Text(
                'GOTA',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Text(
            'Juntos encontramos y cuidamos cada gota.',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Isla de Margarita · Nueva Esparta',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 22),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommunityStatsCard extends StatelessWidget {
  const _CommunityStatsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Hoy en tu comunidad',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                  child: Text(
                    'Maneiro',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.04,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.lg),
            GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 1.0,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StatColumn(
                  value: '8',
                  label: 'fugas reportadas',
                  color: AppColors.primary,
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 1,
                      height: 48,
                      color: AppColors.border,
                    ),
                  ],
                ),
                _StatColumn(
                  value: '3',
                  label: 'fugas resueltas',
                  color: AppColors.success,
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 1,
                      height: 48,
                      color: AppColors.border,
                    ),
                  ],
                ),
                _StatColumn(
                  value: '12',
                  label: 'reportes validados',
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: color,
            fontSize: 24,
          ),
        ),
        SizedBox(height: AppSpacing.xs),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
