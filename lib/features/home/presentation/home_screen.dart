import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../leaks/presentation/leak_community_providers.dart';
import '../../leaks/presentation/leak_report_controller.dart';
import '../../leaks/presentation/leak_report_screen.dart';
import '../../leaks/presentation/recent_activity_card.dart';
import '../../leaks/presentation/recent_activity_providers.dart';
import '../../map/presentation/map_screen.dart';
import '../../water/domain/water_event_type.dart';
import '../../water/presentation/water_register_screen.dart';
import 'community_summary_providers.dart';

/// Pantalla principal: pulso de la comunidad (fallas activas, resueltas hoy
/// y estado del agua) y las tres acciones principales.
///
/// El orden responde al "¿qué hago aquí?": primero el estado actual, después
/// la acción primaria (reportar fuga, tarjeta sólida) y las secundarias.
/// El listado de fugas cercanas ya no vive aquí: `RecentLeaksList` se
/// conserva para montarlo en su página definitiva.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openReport(BuildContext context) async {
    // Reinicia el borrador para este nuevo reporte.
    final container = ProviderScope.containerOf(context, listen: false);
    container.invalidate(leakReportProvider);
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const LeakReportScreen(),
        fullscreenDialog: true,
      ),
    );
    // S10-B/S10-C: el resumen depende del reporte recién creado; la lista
    // (donde vuelva a montarse) se invalida en el mismo punto.
    if (created == true) {
      container.invalidate(recentLeaksProvider);
      container.invalidate(communitySummaryProvider);
      container.invalidate(latestActivityProvider);
    }
  }

  void _openMap(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const MapScreen()));
  }

  void _openWater(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WaterRegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _GotaHeader(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                children: [
                  const _Entrance(index: 0, child: _CommunitySummaryCard()),
                  SizedBox(height: AppSpacing.lg),
                  _Entrance(
                    index: 1,
                    child: _ActionCard(
                      icon: Icons.water_drop,
                      title: 'Reportar fuga',
                      subtitle: 'Ayúdanos a cuidar el agua',
                      accent: AppColors.accent,
                      emphasised: true,
                      onTap: () => _openReport(context),
                    ),
                  ),
                  SizedBox(height: AppSpacing.md),
                  _Entrance(
                    index: 2,
                    child: _ActionCard(
                      icon: Icons.waves,
                      title: 'Reportar agua',
                      subtitle: 'Indica si llegó o se fue en tu sector',
                      accent: AppColors.primary,
                      onTap: () => _openWater(context),
                    ),
                  ),
                  SizedBox(height: AppSpacing.md),
                  _Entrance(
                    index: 3,
                    child: _ActionCard(
                      icon: Icons.map_outlined,
                      title: 'Fugas activas en el mapa',
                      subtitle: 'Explora las fallas en tu comunidad',
                      accent: AppColors.success,
                      onTap: () => _openMap(context),
                    ),
                  ),
                  SizedBox(height: AppSpacing.md),
                  const _Entrance(index: 4, child: RecentActivityCard()),
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
            'Juntos cuidamos cada gota.',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: AppSpacing.sm),
          Text(
            'Isla de Margarita · Nueva Esparta',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }
}

/// Entrada escalonada (fade + desplazamiento corto) para que el contenido
/// aparezca con ritmo en lugar de golpe. Animación finita: 320 ms + 70 ms
/// por índice, así que no deja controladores vivos ni bloquea pumpAndSettle.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Feedback físico al presionar: la tarjeta encoge levemente y vuelve.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Tarjeta de acción. `solid: true` es la acción primaria (gradiente de su
/// propio acento con texto blanco); el resto usa tinte suave del acento,
/// borde de pelo y texto oscuro.
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.emphasised = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  /// Acción principal: mismo lenguaje que las secundarias, con el borde de
  /// su acento un poco más marcado.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          // Fondo blanco, en línea con el resto de la app: el color del
          // acento vive en el borde, el icono y el chevron.
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: accent.withValues(alpha: emphasised ? 0.45 : 0.32),
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: emphasised ? 0.10 : 0.07),
              blurRadius: emphasised ? 14 : 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            splashColor: accent.withValues(alpha: 0.12),
            highlightColor: accent.withValues(alpha: 0.06),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: textTheme.titleMedium?.copyWith(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 15,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clave estable del reintento de la tarjeta (pruebas de UI).
const communitySummaryRetryKey = Key('community-summary-retry');

/// Tarjeta "Resumen de hoy": fallas activas (reportadas + validadas),
/// resueltas hoy y estado del agua del ámbito efectivo. Solo agregados,
/// sin identidades (REQ-100). Sin iconos: la jerarquía la cargan el número,
/// la etiqueta y el color.
class _CommunitySummaryCard extends ConsumerWidget {
  const _CommunitySummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(communitySummaryProvider);

    return Container(
      decoration: BoxDecoration(
        // Fondo blanco y el color solo en el borde y las cifras.
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen de hoy',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          summaryAsync.when(
            loading: () => const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Cargando actividad…',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No pudimos cargar la actividad de hoy.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                TextButton(
                  key: communitySummaryRetryKey,
                  onPressed: () => ref.invalidate(communitySummaryProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
            data: (summary) => IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Metric(
                      color: AppColors.danger,
                      value: '${summary.activeTotal}',
                      label: 'Fallas activas',
                      detail:
                          '${summary.activeReported} reportadas'
                          ' · ${summary.activeValidated} validadas',
                    ),
                  ),
                  const _MetricDivider(),
                  Expanded(
                    child: _Metric(
                      color: AppColors.success,
                      value: '${summary.resolvedToday}',
                      label: 'Resueltas hoy',
                    ),
                  ),
                  const _MetricDivider(),
                  const Expanded(child: _WaterMetric()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    margin: EdgeInsets.symmetric(horizontal: AppSpacing.md),
    color: AppColors.border,
  );
}

/// Métrica del resumen: valor grande, etiqueta y detalle opcional.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.color,
    required this.value,
    required this.label,
    this.detail,
  });

  final Color color;
  final String value;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: textTheme.headlineMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        if (detail != null)
          Text(
            detail!,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.3,
            ),
          ),
      ],
    );
  }
}

/// Estado del agua del ámbito efectivo (último evento comunitario).
/// Si la consulta falla o no hay eventos, degrada a un texto honesto.
class _WaterMetric extends ConsumerWidget {
  const _WaterMetric();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(sectorWaterStatusProvider);
    final textTheme = Theme.of(context).textTheme;
    final event = statusAsync.value;

    final arrived = event?.type == WaterEventType.arrived;
    final color = event == null
        ? AppColors.textMuted
        : (arrived ? AppColors.success : AppColors.danger);
    final value = event == null ? '—' : (arrived ? 'Llegó' : 'Se fue');
    final detail = event == null
        ? 'Sin información del agua'
        : _timeAgo(event.eventTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: textTheme.headlineMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          'Agua en tu sector',
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.text,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        Text(
          detail,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            height: 1.3,
          ),
          maxLines: 2,
        ),
      ],
    );
  }
}

/// Tiempo transcurrido en formato corto ("hace 3 h", "hace 2 d").
String _timeAgo(DateTime utcTime) {
  final elapsed = DateTime.now().toUtc().difference(utcTime);
  if (elapsed.inMinutes < 60) {
    return 'hace ${elapsed.inMinutes.clamp(0, 59)} min';
  }
  if (elapsed.inHours < 24) return 'hace ${elapsed.inHours} h';
  return 'hace ${elapsed.inDays} d';
}
