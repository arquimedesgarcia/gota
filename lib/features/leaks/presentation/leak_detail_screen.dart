import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../home/presentation/community_summary_providers.dart';
import '../data/leak_community_repository.dart';
import '../domain/leak_age.dart';
import '../domain/leak_community.dart';
import '../domain/leak_community_errors.dart';
import '../domain/leak_photo.dart';
import 'leak_community_microcopy.dart';
import 'leak_community_providers.dart';
import 'recent_activity_providers.dart';

const leakValidateButtonKey = Key('leak-validate-button');
const leakConfirmButtonKey = Key('leak-confirm-button');
const leakActionProgressKey = Key('leak-action-progress');

/// Detalle de una fuga con las acciones comunitarias: validar y confirmar
/// resolución (docs/FUNCTIONAL_SPEC.md §4, §5 y §6).
class LeakDetailScreen extends ConsumerStatefulWidget {
  const LeakDetailScreen({super.key, required this.reportId});
  final String reportId;

  @override
  ConsumerState<LeakDetailScreen> createState() => _LeakDetailScreenState();
}

class _LeakDetailScreenState extends ConsumerState<LeakDetailScreen> {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message(result))));
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _actionError = _messageFor(error);
      });
      _refresh();
    }
  }

  void _refresh() {
    ref.invalidate(leakDetailProvider(widget.reportId));
    ref.invalidate(recentLeaksProvider);
    ref.invalidate(communitySummaryProvider);
    ref.invalidate(latestActivityProvider);
  }

  String _messageFor(Object error) {
    if (error is LeakCommunityException) return error.userMessage;
    if (error is AppException) return error.userMessage;
    return LeakCommunityCopy.actionError;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final detailAsync = ref.watch(leakDetailProvider(widget.reportId));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          detailAsync.when(
            loading: () => const SafeArea(
              child: LoadingView(message: 'Cargando la fuga…'),
            ),
            error: (error, _) => SafeArea(
              child: ErrorView(
                message: _messageFor(error),
                onRetry: _refresh,
              ),
            ),
            data: (detail) => _buildDetail(context, detail),
          ),
          // Botón de retroceso fijo sobre la foto
          Positioned(
            left: 16,
            top: topPadding + 12,
            child: const _BackButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetail(BuildContext context, LeakDetail detail) {
    final topPadding = MediaQuery.of(context).padding.top;

    return CustomScrollView(
      slivers: [
        // Foto edge-to-edge, extendiéndose bajo la status bar
        SliverToBoxAdapter(
          child: _PhotoCarousel(
            reportId: widget.reportId,
            topPadding: topPadding,
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusRow(detail: detail),
                const SizedBox(height: AppSpacing.md),
                _AddressLine(detail: detail),
                if (detail.description != null &&
                    detail.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    detail.description!,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.text,
                      height: 1.65,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _InfoGrid(detail: detail),
                // Leyenda cuando la fuga aún no fue validada
                if (!detail.isValidated && !detail.isResolved) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const _PendingValidationNote(),
                ],
                const SizedBox(height: AppSpacing.md),
                _ConfirmationCard(detail: detail),
                if (_actionError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _InlineMessage(
                    message: _actionError!,
                    color: AppColors.danger,
                    icon: Icons.error_outline,
                  ),
                ],
                if (detail.isResolved) ...[
                  const SizedBox(height: AppSpacing.md),
                  _InlineMessage(
                    message: detail.resolvedAt == null
                        ? 'La comunidad marcó esta fuga como resuelta.'
                        : LeakCommunityCopy.resolvedAt(detail.resolvedAt!),
                    color: AppColors.success,
                    icon: Icons.task_alt,
                  ),
                ],
                if (!detail.isResolved) ...[
                  const SizedBox(height: AppSpacing.xl),
                  _ActionRow(
                    detail: detail,
                    running: _running,
                    onValidate: _validate,
                    onConfirm: _confirmResolution,
                  ),
                  if (_running) ...[
                    const SizedBox(height: AppSpacing.md),
                    const LinearProgressIndicator(
                      key: leakActionProgressKey,
                      minHeight: 3,
                    ),
                  ],
                  // Razón por la que el botón de validar está deshabilitado
                  if (_disabledReason(detail) != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _disabledReason(detail)!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  // Aviso B3: confirmar resolución requiere validación previa
                  if (!detail.isValidated) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      LeakCommunityCopy.confirmRequiresValidation,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
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

// ─── Carrusel de fotos ────────────────────────────────────────────────────────

/// Carrusel de fotos del reporte: deslizable manualmente, rotación automática
/// cada 4 s, indicador numérico de posición. Siempre se intenta cargar las
/// fotos aunque `photoCount` en el detalle sea 0 (workaround por RPC).
class _PhotoCarousel extends ConsumerStatefulWidget {
  const _PhotoCarousel({required this.reportId, required this.topPadding});
  final String reportId;
  final double topPadding;

  @override
  ConsumerState<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends ConsumerState<_PhotoCarousel> {
  late final PageController _pageController;
  int _currentIndex = 0;
  Timer? _timer;
  bool _timerStarted = false;

  static const double _photoHeight = 260;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoRotation(int count) {
    _timer?.cancel();
    if (count <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_currentIndex + 1) % count;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  void _openViewer(List<LeakPhoto> photos, int index) {
    _timer?.cancel();
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                _PhotoViewer(photos: photos, initialIndex: index),
          ),
        )
        .then((_) => _startAutoRotation(photos.length));
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(leakPhotosProvider(widget.reportId));
    final totalHeight = _photoHeight + widget.topPadding;

    return SizedBox(
      height: totalHeight,
      child: photosAsync.when(
        loading: () => _Placeholder(topPadding: widget.topPadding),
        error: (_, _) => _Placeholder(topPadding: widget.topPadding),
        data: (photos) {
          if (photos.isEmpty) {
            return _Placeholder(topPadding: widget.topPadding);
          }

          // Inicio de rotación automática (solo la primera vez que carga)
          if (!_timerStarted) {
            _timerStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _startAutoRotation(photos.length);
            });
          }

          // Renovar URLs próximas a expirar
          if (photos.any((p) => p.isExpiringSoon())) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ref.invalidate(leakPhotosProvider(widget.reportId));
              }
            });
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // Páginas de fotos
              PageView.builder(
                controller: _pageController,
                itemCount: photos.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openViewer(photos, i),
                  child: CachedNetworkImage(
                    imageUrl: photos[i].displayThumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => const ColoredBox(
                      color: AppColors.border,
                    ),
                    errorWidget: (_, _, _) => const ColoredBox(
                      color: AppColors.border,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Gradiente inferior sutil para los indicadores
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 72,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.24),
                      ],
                    ),
                  ),
                ),
              ),
              // Indicador de posición (n / total)
              if (photos.length > 1)
                Positioned(
                  right: 16,
                  top: widget.topPadding + 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.50),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${photos.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              // Indicadores de puntos
              if (photos.length > 1)
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(photos.length, (i) {
                      final active = i == _currentIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        width: active ? 18 : 6,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: active ? 0.95 : 0.45,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Placeholder cuando no hay fotos o aún están cargando.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.topPadding});
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD0E6F2), Color(0xFFC2D9EA)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.water_drop_outlined,
                color: Color(0xFF8AAFC6),
                size: 44,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Botón retroceso ──────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 17,
          color: AppColors.text,
        ),
      ),
    );
  }
}

// ─── Secciones del detalle ────────────────────────────────────────────────────

/// Pill de estado + tiempo relativo desde el reporte.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.detail});
  final LeakDetail detail;

  @override
  Widget build(BuildContext context) {
    final resolved = detail.isResolved;
    final statusColor = resolved ? AppColors.success : AppColors.accent;
    final statusLabel = resolved
        ? LeakCommunityCopy.resolvedStatus
        : LeakCommunityCopy.activeStatus;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.34)),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          describeLeakAge(detail.createdAt),
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Dirección de la fuga: preferencia al nombre GPS del sector.
/// Formato: Sector · Municipio (sin prefijo "Fuga en").
class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.detail});
  final LeakDetail detail;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (detail.sectorName != null && detail.sectorName!.isNotEmpty)
        detail.sectorName!,
      if (detail.municipalityName != null &&
          detail.municipalityName!.isNotEmpty)
        detail.municipalityName!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(
            Icons.location_on_outlined,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
              height: 1.25,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Cuadrícula de dos tarjetas: Reportada y Validaciones.
class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.detail});
  final LeakDetail detail;

  static const _kMinValidation = 1; // isValidated = validationCount >= 1

  @override
  Widget build(BuildContext context) {
    final local = detail.createdAt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final dateStr = '$day/$month/${local.year}';

    final valCount = detail.validationCount;
    final valText = valCount < _kMinValidation
        ? '$valCount de $_kMinValidation'
        : '$valCount o más';

    return Row(
      children: [
        Expanded(
          child: _InfoTile(label: 'Reportada', value: dateStr),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoTile(
            label: 'Validaciones',
            value: valText,
            valueColor: detail.isValidated
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    this.valueColor,
  });
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Leyenda pequeña y tenue cuando la fuga aún no ha sido validada.
class _PendingValidationNote extends StatelessWidget {
  const _PendingValidationNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Icon(
          Icons.info_outline_rounded,
          size: 12,
          color: AppColors.textMuted,
        ),
        SizedBox(width: 5),
        Text(
          'Pendiente de validación comunitaria',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Tarjeta de confirmaciones con barra de progreso.
/// Mismo formato de texto que _InfoGrid: "X de N" / "X o más".
class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({required this.detail});
  final LeakDetail detail;

  @override
  Widget build(BuildContext context) {
    final threshold = detail.threshold <= 0 ? 3 : detail.threshold;
    final confirmed = detail.resolutionConfirmationCount;

    final confText = confirmed < threshold
        ? '$confirmed de $threshold'
        : '$confirmed o más';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8FB),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: const Color(0xFFD5E8F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CONFIRMACIONES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.7,
                ),
              ),
              Text(
                confText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (confirmed / threshold).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFFD5E8F1),
              color: detail.isResolved ? AppColors.success : AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Se requieren al menos $threshold confirmaciones para cerrar la fuga.',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ─── Fila de acciones ─────────────────────────────────────────────────────────

/// Botones "Validar" y "Resuelta" lado a lado, con el lenguaje visual
/// de las tarjetas del Home: fondo gris tenue, borde del color de la acción.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.detail,
    required this.running,
    required this.onValidate,
    required this.onConfirm,
  });
  final LeakDetail detail;
  final bool running;
  final VoidCallback onValidate;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            widgetKey: leakValidateButtonKey,
            label: detail.alreadyValidated
                ? LeakCommunityCopy.alreadyValidated
                : 'Validar',
            icon: Icons.thumb_up_alt_outlined,
            accentColor: AppColors.accent,
            enabled: detail.canValidate && !running,
            onTap: detail.canValidate && !running ? onValidate : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionTile(
            widgetKey: leakConfirmButtonKey,
            label: detail.alreadyConfirmed
                ? LeakCommunityCopy.alreadyConfirmed
                : 'Resuelta',
            icon: Icons.task_alt_outlined,
            accentColor: AppColors.success,
            enabled: detail.canConfirmResolution && !running,
            onTap: detail.canConfirmResolution && !running ? onConfirm : null,
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatefulWidget {
  const _ActionTile({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.enabled,
    required this.onTap,
    this.widgetKey,
  });
  final String label;
  final IconData icon;
  final Color accentColor;
  final bool enabled;
  final VoidCallback? onTap;
  final Key? widgetKey;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.enabled
        ? widget.accentColor.withValues(alpha: 0.52)
        : AppColors.border;
    final fgColor = widget.enabled ? widget.accentColor : AppColors.textMuted;
    final bgColor = widget.enabled
        ? const Color(0xFFF3F6F8)
        : const Color(0xFFF8FAFB);

    return GestureDetector(
      key: widget.widgetKey,
      onTapDown: (_) => widget.enabled
          ? setState(() => _pressed = true)
          : null,
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: widget.enabled
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.09),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: fgColor, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mensaje inline ───────────────────────────────────────────────────────────

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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Visor a pantalla completa ────────────────────────────────────────────────

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initialIndex});
  final List<LeakPhoto> photos;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.photos.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.photos[i].url,
              fit: BoxFit.contain,
              placeholder: (_, _) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, _, _) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
