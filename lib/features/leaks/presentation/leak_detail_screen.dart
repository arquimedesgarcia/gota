import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../data/leak_community_repository.dart';
import '../domain/leak_age.dart';
import '../domain/leak_community.dart';
import '../domain/leak_community_errors.dart';
import 'leak_community_microcopy.dart';
import 'leak_community_providers.dart';

/// Claves estables para las pruebas de UI.
const leakValidateButtonKey = Key('leak-validate-button');
const leakConfirmButtonKey = Key('leak-confirm-button');
const leakActionProgressKey = Key('leak-action-progress');

/// Detalle de una fuga con las acciones comunitarias de Sprint 03:
/// validar y confirmar resolución (docs/FUNCTIONAL_SPEC.md §4, §5 y §6).
///
/// Toda la información y el resultado de las acciones vienen del backend:
/// la pantalla nunca anuncia éxito por su cuenta.
class LeakDetailScreen extends ConsumerStatefulWidget {
  const LeakDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<LeakDetailScreen> createState() => _LeakDetailScreenState();
}

class _LeakDetailScreenState extends ConsumerState<LeakDetailScreen> {
  /// Evita doble ejecución por doble tap mientras hay una acción en curso.
  bool _running = false;
  String? _actionError;

  LeakCommunityRepository get _repository =>
      ref.read(leakCommunityRepositoryProvider);

  Future<void> _validate() => _run(
    () => _repository.validateLeak(widget.reportId),
    (result) => LeakCommunityCopy.validatedMessage(result.validationCount),
  );

  Future<void> _confirmResolution() => _run(
    () => _repository.confirmResolution(widget.reportId),
    (result) => LeakCommunityCopy.confirmedMessage(
      resolved: result.isResolved,
      missing: (result.threshold - result.resolutionConfirmationCount).clamp(
        0,
        result.threshold,
      ),
    ),
  );

  Future<void> _run(
    Future<CommunityActionResult> Function() action,
    String Function(CommunityActionResult) message,
  ) async {
    if (_running) return;
    setState(() {
      _running = true;
      _actionError = null;
    });

    try {
      final result = await action();
      if (!mounted) return;
      setState(() => _running = false);
      _refresh();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message(result))));
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _actionError = _messageFor(error);
      });
      // El estado real puede haber cambiado (por ejemplo, otra persona ya
      // resolvió la fuga): se relee del backend.
      _refresh();
    }
  }

  void _refresh() {
    ref.invalidate(leakDetailProvider(widget.reportId));
    ref.invalidate(recentLeaksProvider);
  }

  String _messageFor(Object error) {
    if (error is LeakCommunityException) return error.userMessage;
    if (error is AppException) return error.userMessage;
    return LeakCommunityCopy.actionError;
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(leakDetailProvider(widget.reportId));

    return Scaffold(
      appBar: AppBar(title: const Text(LeakCommunityCopy.screenTitle)),
      body: SafeArea(
        child: detailAsync.when(
          loading: () => const LoadingView(message: 'Cargando la fuga…'),
          error: (error, _) =>
              ErrorView(message: _messageFor(error), onRetry: _refresh),
          data: _buildDetail,
        ),
      ),
    );
  }

  Widget _buildDetail(LeakDetail detail) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusCard(detail: detail),
        const SizedBox(height: 12),
        _InfoCard(detail: detail),
        const SizedBox(height: 12),
        _CommunityCard(detail: detail),
        if (_actionError != null) ...[
          const SizedBox(height: 12),
          _InlineMessage(
            message: _actionError!,
            color: AppColors.danger,
            icon: Icons.error_outline,
          ),
        ],
        if (detail.isResolved) ...[
          const SizedBox(height: 12),
          _InlineMessage(
            message: detail.resolvedAt == null
                ? 'La comunidad marcó esta fuga como resuelta.'
                : LeakCommunityCopy.resolvedAt(detail.resolvedAt!),
            color: AppColors.success,
            icon: Icons.task_alt,
          ),
        ],
        if (!detail.isResolved) ...[
          const SizedBox(height: 20),
          FilledButton(
            key: leakValidateButtonKey,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: detail.canValidate && !_running ? _validate : null,
            child: Text(
              detail.alreadyValidated
                  ? LeakCommunityCopy.alreadyValidated
                  : LeakCommunityCopy.validateButton,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: leakConfirmButtonKey,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: detail.canConfirmResolution && !_running
                ? _confirmResolution
                : null,
            child: Text(
              detail.alreadyConfirmed
                  ? LeakCommunityCopy.alreadyConfirmed
                  : LeakCommunityCopy.confirmButton,
            ),
          ),
          if (_disabledReason(detail) != null) ...[
            const SizedBox(height: 8),
            Text(
              _disabledReason(detail)!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_running) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              key: leakActionProgressKey,
              minHeight: 3,
            ),
          ],
        ],
      ],
    );
  }

  String? _disabledReason(LeakDetail detail) {
    if (detail.isBlocked) return LeakCommunityCopy.blocked;
    if (detail.isCreator) return LeakCommunityCopy.cannotValidateOwn;
    if (detail.alreadyValidated) return LeakCommunityCopy.alreadyValidated;
    return null;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.detail});

  final LeakDetail detail;

  @override
  Widget build(BuildContext context) {
    final resolved = detail.isResolved;
    final color = resolved ? AppColors.success : AppColors.accent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              resolved ? Icons.check_circle_outline : Icons.water_drop_outlined,
              color: color,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resolved
                        ? LeakCommunityCopy.resolvedStatus
                        : LeakCommunityCopy.activeStatus,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    describeLeakAge(detail.createdAt),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
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

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.detail});

  final LeakDetail detail;

  @override
  Widget build(BuildContext context) {
    final place = [
      if (detail.sectorName != null) detail.sectorName!,
      if (detail.municipalityName != null) detail.municipalityName!,
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              place.isEmpty ? 'Ubicación' : place,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (detail.description != null && detail.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(detail.description!),
              ),
            Text(
              '${LeakCommunityCopy.photoCount(detail.photoCount)} · '
              '${detail.latitude.toStringAsFixed(5)}, '
              '${detail.longitude.toStringAsFixed(5)}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({required this.detail});

  final LeakDetail detail;

  @override
  Widget build(BuildContext context) {
    final threshold = detail.threshold <= 0 ? 3 : detail.threshold;
    final confirmed = detail.resolutionConfirmationCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LeakCommunityCopy.validationCount(detail.validationCount),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              detail.validationCount == 0
                  ? LeakCommunityCopy.beFirstValidator
                  : LeakCommunityCopy.validating,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text(
              LeakCommunityCopy.resolveQuestion,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (confirmed / threshold).clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: AppColors.border,
              color: detail.isResolved ? AppColors.success : AppColors.primary,
            ),
            const SizedBox(height: 8),
            Text(
              LeakCommunityCopy.confirmationProgress(confirmed, threshold),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
