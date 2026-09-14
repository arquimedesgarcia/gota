import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../water/domain/water_event_type.dart';
import '../domain/water_notification.dart';
import 'notification_providers.dart';

/// Bandeja de notificaciones del usuario (Sprint 06).
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
        padding: const EdgeInsets.all(16),
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
            onTap: notification.isUnread
                ? () => ref
                      .read(notificationInboxControllerProvider.notifier)
                      .markRead(notification.id)
                : null,
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_none,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Aún no tienes notificaciones.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: unread
              ? AppColors.primary.withValues(alpha: 0.05)
              : AppColors.surface,
          border: Border.all(
            color: unread ? AppColors.primary : AppColors.border,
            width: unread ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              notification.type == WaterEventType.arrived
                  ? Icons.water_drop
                  : Icons.water_drop_outlined,
              color: notification.type == WaterEventType.arrived
                  ? AppColors.success
                  : AppColors.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
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
      if (notification.municipalityName != null)
        notification.municipalityName!,
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
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonal(
                onPressed: onPressed,
                child: const Text('Cargar más'),
              ),
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
