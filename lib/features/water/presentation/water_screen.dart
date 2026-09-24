import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/gota_icon_tile.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../home/presentation/community_summary_providers.dart';
import '../domain/water_errors.dart';
import '../domain/water_event.dart';
import '../domain/water_event_age.dart';
import '../domain/water_event_type.dart';
import 'water_copy.dart';
import 'water_event_detail_screen.dart';
import 'water_providers.dart';
import 'water_register_controller.dart';
import 'water_register_screen.dart';

/// Claves estables para las pruebas de UI.
Key waterTileKey(String id) => ValueKey('water-tile-$id');

const waterArrivedButtonKey = Key('water-arrived-button');
const waterLeftButtonKey = Key('water-left-button');
const waterLoadMoreKey = Key('water-load-more');
const waterLoadMoreProgressKey = Key('water-load-more-progress');

/// Pestaña Agua (Sprint 04): acciones rápidas (Llegó / Se fue), tarjeta de
/// resumen con estadísticas descriptivas y el historial de eventos
/// comunitarios (docs/FUNCTIONAL_SPEC.md §10).
///
/// Todo el contenido del historial y los contadores vienen del backend.
///
/// Sprint 09-UI: tarjetas de acción tipo selector del prototipo
/// (superficie blanca + borde + icono teñido, sin bloques de color),
/// resumen con jerarquía numérica y tiles de evento con icono en caja.
/// Sin cambios funcionales.
class WaterScreen extends ConsumerWidget {
  const WaterScreen({super.key});

  Future<void> _openRegister(
    BuildContext context,
    WidgetRef ref,
    WaterEventType? initialType,
  ) async {
    // El flujo de registro siempre abre en limpio: el controller no es
    // autoDispose y conservaría municipio, sector y hora de un registro
    // anterior (H-01).
    ref.invalidate(waterRegisterControllerProvider);
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WaterRegisterScreen(initialType: initialType),
        fullscreenDialog: true,
      ),
    );
    if (created ?? false) {
      // El historial se refresca solo después de que el backend confirmó
      // la creación del evento.
      ref.invalidate(waterHistoryControllerProvider);
      // El "Estado del agua" del resumen de Home depende del evento nuevo.
      ref.invalidate(sectorWaterStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(waterHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(WaterCopy.screenTitle)),
      body: SafeArea(
        child: history.events.when(
          loading: () => const LoadingView(message: 'Cargando el historial…'),
          error: (error, _) => ErrorView(
            message: _messageFor(error),
            onRetry: () =>
                ref.read(waterHistoryControllerProvider.notifier).refresh(),
          ),
          data: (_) => _WaterBody(
            history: history,
            onRegister: (type) => _openRegister(context, ref, type),
          ),
        ),
      ),
    );
  }

  String _messageFor(Object error) {
    if (error is WaterException) return error.userMessage;
    if (error is AppException) return error.userMessage;
    return WaterCopy.loadError;
  }
}

class _WaterBody extends ConsumerWidget {
  const _WaterBody({required this.history, required this.onRegister});

  final WaterHistoryState history;
  final ValueChanged<WaterEventType?> onRegister;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = history.events.value ?? const <WaterEventSummary>[];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: WaterEventCard(
                key: waterArrivedButtonKey,
                label: WaterEventType.arrived.label,
                icon: Icons.water_drop,
                tint: AppColors.success,
                onTap: () => onRegister(WaterEventType.arrived),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: WaterEventCard(
                key: waterLeftButtonKey,
                label: WaterEventType.left.label,
                icon: Icons.water_drop_outlined,
                tint: AppColors.danger,
                onTap: () => onRegister(WaterEventType.left),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const _StatisticsCard(),
        const SizedBox(height: AppSpacing.xl),
        Text(
          WaterCopy.historyTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (events.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text(
                WaterCopy.emptyList,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          )
        else ...[
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: WaterEventTile(event: event),
            ),
        ],
        if (history.hasMore) ...[
          const SizedBox(height: AppSpacing.xs),
          history.isLoadingMore
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Center(
                    child: SizedBox(
                      key: waterLoadMoreProgressKey,
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  key: waterLoadMoreKey,
                  onPressed: () => ref
                      .read(waterHistoryControllerProvider.notifier)
                      .loadMore(),
                  child: const Text(WaterCopy.loadMore),
                ),
        ],
      ],
    );
  }
}

/// Botón de acción del ciclo de agua: icono al lado del texto,
/// borde con acento de color, lenguaje visual alineado con el Home.
class WaterEventCard extends StatelessWidget {
  const WaterEventCard({
    super.key,
    required this.label,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        splashColor: tint.withValues(alpha: 0.12),
        highlightColor: tint.withValues(alpha: 0.06),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: tint.withValues(alpha: 0.38)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: tint, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryDark,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de resumen con estadísticas DESCRIPTIVAS sobre los eventos
/// cargados (REQ-077: sin predicción).
///
/// Sprint 09-UI: pareja ficha izquierda/derecha con divisor vertical,
/// usando la jerarquía del prototipo (valor acentuado + caption).
class _StatisticsCard extends ConsumerWidget {
  const _StatisticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(waterStatisticsProvider);
    final now = DateTime.now();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statRow(
              context,
              '${WaterCopy.totalArrivals}: ${stats.arrivedCount}',
              '${WaterCopy.totalDepartures}: ${stats.leftCount}',
            ),
            const SizedBox(height: AppSpacing.sm),
            _statRow(
              context,
              '${WaterCopy.lastArrival}: '
                  '${stats.lastArrival == null ? '—' : describeWaterEventTime(stats.lastArrival!, now: now)}',
              '${WaterCopy.lastDeparture}: '
                  '${stats.lastDeparture == null ? '—' : describeWaterEventTime(stats.lastDeparture!, now: now)}',
            ),
            const SizedBox(height: AppSpacing.sm),
            _statRow(
              context,
              '${WaterCopy.averageSupply}: '
                  '${stats.averageSupplyDuration == null ? WaterCopy.noData : WaterCopy.duration(stats.averageSupplyDuration)}',
              '${WaterCopy.averageOutage}: '
                  '${stats.averageOutageDuration == null ? WaterCopy.noData : WaterCopy.duration(stats.averageOutageDuration)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(BuildContext context, String left, String right) {
    final style = const TextStyle(fontSize: 13, color: AppColors.text);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(left, style: style)),
        Expanded(
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 1,
                  color: AppColors.border,
                  margin: const EdgeInsets.only(right: AppSpacing.md),
                ),
                Expanded(child: Text(right, style: style)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Tile de un evento en el historial: entrada al detalle, donde vive la
/// validación comunitaria.
///
/// Sprint 09-UI: icono en caja cuadrada teñida (patrón prototipo §agua),
/// jerarquía fecha/hora/sector y comentario recortado. Copia centralizada
/// en [WaterCopy] — no se inventan textos.
class WaterEventTile extends StatelessWidget {
  const WaterEventTile({super.key, required this.event});

  final WaterEventSummary event;

  @override
  Widget build(BuildContext context) {
    final arrived = event.type == WaterEventType.arrived;
    final place = [
      if (event.sectorName != null) event.sectorName!,
      if (event.municipalityName != null) event.municipalityName!,
    ].join(' · ');

    return Card(
      child: InkWell(
        key: waterTileKey(event.id),
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WaterEventDetailScreen(eventId: event.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GotaIconTile(
                icon: arrived ? Icons.water_drop : Icons.water_drop_outlined,
                color: arrived ? AppColors.success : AppColors.danger,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.type.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${describeWaterEventTime(event.eventTime, now: DateTime.now())} '
                      '· ${WaterCopy.validationCount(event.validationCount)}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        place,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    if (event.comment != null && event.comment!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        event.comment!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
