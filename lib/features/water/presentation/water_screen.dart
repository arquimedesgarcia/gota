import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../domain/water_errors.dart';
import '../domain/water_event.dart';
import '../domain/water_event_age.dart';
import '../domain/water_event_type.dart';
import 'water_copy.dart';
import 'water_event_detail_screen.dart';
import 'water_providers.dart';
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
class WaterScreen extends ConsumerWidget {
  const WaterScreen({super.key});

  Future<void> _openRegister(
    BuildContext context,
    WidgetRef ref,
    WaterEventType? initialType,
  ) async {
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
      padding: const EdgeInsets.all(16),
      children: [
        _ActionButton(
          key: waterArrivedButtonKey,
          label: WaterEventType.arrived.label,
          icon: Icons.water_drop,
          background: AppColors.primary,
          onPressed: () => onRegister(WaterEventType.arrived),
        ),
        const SizedBox(height: 12),
        _ActionButton(
          key: waterLeftButtonKey,
          label: WaterEventType.left.label,
          icon: Icons.water_drop_outlined,
          background: AppColors.danger,
          onPressed: () => onRegister(WaterEventType.left),
        ),
        const SizedBox(height: 20),
        Text(
          WaterCopy.summaryTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const _StatisticsCard(),
        const SizedBox(height: 20),
        Text(
          WaterCopy.historyTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                WaterCopy.emptyList,
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          )
        else ...[
          for (final event in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: WaterEventTile(event: event),
            ),
        ],
        if (history.hasMore) ...[
          const SizedBox(height: 4),
          history.isLoadingMore
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.background,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        onPressed: onPressed,
      ),
    );
  }
}

/// Tarjeta de resumen con estadísticas DESCRIPTIVAS sobre los eventos
/// cargados (REQ-077: sin predicción).
class _StatisticsCard extends ConsumerWidget {
  const _StatisticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(waterStatisticsProvider);
    final now = DateTime.now();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statRow(
              context,
              '${WaterCopy.totalArrivals}: ${stats.arrivedCount}',
              '${WaterCopy.totalDepartures}: ${stats.leftCount}',
            ),
            const SizedBox(height: 8),
            _statRow(
              context,
              '${WaterCopy.lastArrival}: '
                  '${stats.lastArrival == null ? '—' : describeWaterEventTime(stats.lastArrival!, now: now)}',
              '${WaterCopy.lastDeparture}: '
                  '${stats.lastDeparture == null ? '—' : describeWaterEventTime(stats.lastDeparture!, now: now)}',
            ),
            const SizedBox(height: 8),
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
      children: [
        Expanded(child: Text(left, style: style)),
        Expanded(child: Text(right, style: style)),
      ],
    );
  }
}

/// Tile de un evento en el historial: entrada al detalle, donde vive la
/// validación comunitaria.
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
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                arrived ? Icons.water_drop : Icons.water_drop_outlined,
                color: arrived ? AppColors.primary : AppColors.danger,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.type.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
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
                      const SizedBox(height: 4),
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
