import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/gota_icon_tile.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../water/domain/water_event_type.dart';
import '../../water/presentation/water_event_detail_screen.dart';
import '../domain/water_notification.dart';
import 'notification_providers.dart';

/// Bandeja de notificaciones del usuario (Sprint 06).
///
/// Sprint 09-UI: patrón de lista del prototipo §notif — icono en caja
/// cuadrada teñida por tipo, punto de unread + título con peso diferenciado
/// y fondo de superficie para las no leídas. Las acciones funcionales
/// (marcado individual, marcar todas, paginación, pull-to-refresh) no
/// cambian.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationInboxControllerProvider);
    final items = state.items.value ?? const <WaterNotification>[];
    final hasUnread = items.any((n) => n.isUnread);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (hasUnread)
            IconButton(
              tooltip: 'Marcar todas como leídas',
              icon: const Icon(Icons.done_all),
              onPressed: () {
                for (final n in items.where((n) => n.isUnread)) {
                  ref
                      .read(notificationInboxControllerProvider.notifier)
                      .markRead(n.id);
                }
              },
            ),
        ],
      ),
      body: _buildBody(context, ref, state, items),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    NotificationInboxState state,
    List<WaterNotification> items,
  ) {
    if (state.items.hasError && items.isEmpty) {
      final error = state.items.error;
      return ErrorView(
        message: error is AppException
            ? error.userMessage
            : 'No pudimos cargar tus notificaciones.',
        onRetry: () =>
            ref.read(notificationInboxControllerProvider.notifier).refresh(),
      );
    }
    if (state.items.isLoading && items.isEmpty) {
      return const LoadingView(message: 'Cargando notificaciones…');
    }
    if (items.isEmpty) {
      return const _EmptyInbox();
    }
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(notificationInboxControllerProvider.notifier).refresh(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: items.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return _LoadMoreFooter(
              isLoading: state.isLoadingMore,
              onPressed: () => ref
                  .read(notificationInboxControllerProvider.notifier)
                  .loadMore(),
            );
          }
          final notification = items[index];
          return _NotificationTile(
            notification: notification,
            onTap: () async {
              if (notification.isUnread) {
                await ref
                    .read(notificationInboxControllerProvider.notifier)
                    .markRead(notification.id);
              }
              if (!context.mounted || notification.eventId == null) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      WaterEventDetailScreen(eventId: notification.eventId!),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GotaIconTile(
              icon: Icons.notifications_none,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Aún no tienes notificaciones.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Cuando haya avisos del servicio de agua en tu sector de '
              'interés aparecerán aquí.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, this.onTap});

  final WaterNotification notification;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = notification.isUnread;
    final arrived = notification.type == WaterEventType.arrived;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: unread
              ? AppColors.primary.withValues(alpha: 0.05)
              : AppColors.surface,
          border: Border.all(
            color: unread ? AppColors.primary : AppColors.border,
            width: unread ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GotaIconTile(
              icon: arrived ? Icons.water_drop : Icons.water_drop_outlined,
              color: arrived ? AppColors.success : AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          notification.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        _formatDateTime(notification.eventTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    notification.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _subtitle(notification),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(WaterNotification notification) {
    final place = <String>[
      if (notification.sectorName != null) notification.sectorName!,
      if (notification.municipalityName != null) notification.municipalityName!,
    ].join(' · ');
    final date = _formatDateTime(notification.eventTime);
    return place.isEmpty ? date : '$place · $date';
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(onPressed: onPressed, child: const Text('Cargar más')),
      ),
    );
  }
}

/// `dd/MM/yyyy · hh:mm` (24 h), sin dependencias.
String _formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final day = _twoDigits(local.day);
  final month = _twoDigits(local.month);
  final year = local.year;
  final hour = _twoDigits(local.hour);
  final minute = _twoDigits(local.minute);
  return '$day/$month/$year · $hour:$minute';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
