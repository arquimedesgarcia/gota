import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../location/presentation/location_providers.dart';
import '../data/push_service.dart';
import 'notification_providers.dart';
import 'notifications_screen.dart';
import 'sector_selection_screen.dart';

/// Contenido de la pestaña "Más": ajustes, sector de interés y permisos de
/// notificación.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pushStatus = ref.watch(pushBootstrapProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Notificaciones', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Elige qué avisos quieres recibir sobre el servicio de agua.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const _InboxCard(),
          const SizedBox(height: 12),
          const _SectorCard(),
          const SizedBox(height: 12),
          const _WaterNotificationsCard(),
          if (pushStatus.value == PushPermissionStatus.denied) ...[
            const SizedBox(height: 12),
            const _PermissionDeniedCard(),
          ],
        ],
      ),
    );
  }
}

class _InboxCard extends ConsumerWidget {
  const _InboxCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return Card(
      child: ListTile(
        leading: Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          backgroundColor: AppColors.accent,
          child: const Icon(Icons.notifications_outlined),
        ),
        title: const Text('Bandeja de notificaciones'),
        subtitle: Text(unread > 0 ? '$unread sin leer' : 'Sin notificaciones nuevas'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
          );
        },
      ),
    );
  }
}

class _SectorCard extends ConsumerWidget {
  const _SectorCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesControllerProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sector de interés', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            prefs.when(
              loading: () => const LoadingView(),
              error: (error, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error is AppException
                        ? error.userMessage
                        : 'No pudimos cargar tus preferencias. Intenta de nuevo.',
                    style: theme.textTheme.bodySmall,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      notificationPreferencesControllerProvider,
                    ),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
              data: (data) {
                final sectorId = data?.preferredSectorId;
                if (sectorId == null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No tienes un sector de interés seleccionado.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Selecciona un sector para recibir avisos sobre el '
                        'servicio de agua.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () => _openSectorSelection(context, ref),
                        child: const Text('Seleccionar sector'),
                      ),
                    ],
                  );
                }
                final sectorName = ref.watch(sectorNameProvider(sectorId));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sectorName.value ?? 'Sector',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => _openSectorSelection(context, ref),
                          child: const Text('Cambiar sector'),
                        ),
                        OutlinedButton(
                          onPressed: () => _confirmClear(context, ref),
                          child: const Text('Quitar sector'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSectorSelection(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SectorSelectionScreen()),
    );
    ref.invalidate(notificationPreferencesProvider);
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Quitar tu sector de interés?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(notificationPreferencesControllerProvider.notifier)
          .clearSector();
    }
  }
}

class _WaterNotificationsCard extends ConsumerWidget {
  const _WaterNotificationsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesControllerProvider);
    final enabled = prefs.value?.waterNotificationsEnabled ?? false;
    final saving = prefs.isLoading;

    return Card(
      child: SwitchListTile(
        title: const Text('Notificaciones de agua'),
        subtitle: Text(
          'Recibirás avisos cuando llegue o se vaya el agua en tu sector de '
          'interés.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        value: enabled,
        onChanged: saving
            ? null
            : (value) => ref
                  .read(notificationPreferencesControllerProvider.notifier)
                  .setWaterNotificationsEnabled(value),
      ),
    );
  }
}

class _PermissionDeniedCard extends StatelessWidget {
  const _PermissionDeniedCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No concediste permiso de notificaciones. Puedes activarlo '
                'más tarde desde los ajustes de tu dispositivo. Seguirás '
                'recibiendo avisos dentro de Gota.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
