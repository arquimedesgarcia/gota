import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/municipality.dart';
import '../../../shared/models/sector.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../leaks/presentation/location_map_picker.dart';
import '../../location/presentation/location_providers.dart';
import 'water_register_controller.dart';

/// Segundo paso del registro de agua: ubicación por GPS + reverse geocoding
/// (paridad con Reportar fuga). El municipio y el sector se autocompletan
/// desde la ubicación y pueden corregirse (municipio con un desplegable,
/// sector con una caja de búsqueda que filtra el catálogo en tiempo real).
class WaterRegisterStepLocation extends ConsumerWidget {
  const WaterRegisterStepLocation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(waterRegisterControllerProvider);
    final controller = ref.read(waterRegisterControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Mi ubicación'),
                onPressed: controller.requestGps,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.pin_drop_outlined),
              label: const Text('Manual'),
              onPressed: controller.enterManualMode,
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (state.suggestionLoading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Text(
            'Buscando una ubicación aproximada…',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
        ],

        // Tarjeta con la dirección aproximada (address que se guardará).
        if (state.address != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.address!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Mapa de ajuste (visible cuando ya hay una ubicación).
        if (state.hasLocation) ...[
          SizedBox(
            height: 200,
            child: ref.watch(locationMapBuilderProvider)(
              latitude: state.latitude!,
              longitude: state.longitude!,
              onMapTapped: (point) => controller.setManualLocation(
                latitude: point.latitude,
                longitude: point.longitude,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            state.isGpsLocation
                ? 'Toca el mapa para ajustar el punto.'
                : 'Ubicación indicada manualmente. Toca el mapa para ajustar.',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
        ] else if (!state.suggestionLoading) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      state.manualModeEnabled
                          ? Icons.edit_location_alt_outlined
                          : Icons.info_outline,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.manualModeEnabled
                          ? 'Selecciona el municipio y sector de la falla en los campos de abajo.'
                          : 'Sin ubicación todavía. Usa tu GPS o toca "Manual" para continuar.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Municipio (desplegable, prellenado desde la ubicación).
        _MunicipalityDropdown(
          selectedId: state.municipalityId,
          onSelected: controller.selectMunicipality,
        ),
        const SizedBox(height: 12),

        // Sector (caja de búsqueda que filtra el catálogo del municipio).
        if (state.municipalityId != null)
          _SectorSearchField(
            municipalityId: state.municipalityId!,
            selectedId: state.sectorId,
            selectedName: state.sectorName,
            onSelected: controller.selectSector,
          )
        else
          const Text(
            'Elige un municipio para ver sus sectores.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
      ],
    );
  }

}

class _MunicipalityDropdown extends ConsumerWidget {
  const _MunicipalityDropdown({
    required this.selectedId,
    required this.onSelected,
  });

  final String? selectedId;
  final ValueChanged<Municipality> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final municipalitiesState = ref.watch(municipalitiesProvider);
    return municipalitiesState.when(
      loading: () => const LoadingView(message: 'Cargando municipios…'),
      error: (error, _) => ErrorView(
        message: 'No pudimos cargar los municipios.',
        onRetry: () => ref.invalidate(municipalitiesProvider),
      ),
      data: (municipalities) => DropdownButtonFormField<String>(
        key: ValueKey(selectedId),
        initialValue: selectedId,
        decoration: const InputDecoration(labelText: 'Municipio'),
        items: municipalities
            .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          final municipality = municipalities.firstWhere((m) => m.id == value);
          onSelected(municipality);
        },
      ),
    );
  }
}

/// Caja de búsqueda de sector: filtra el catálogo del municipio en tiempo
/// real y permite seleccionar de la lista. Fallback cuando el geocoding no
/// resuelve el sector exacto (docs/backlog/reporte-agua-gps.md).
class _SectorSearchField extends ConsumerStatefulWidget {
  const _SectorSearchField({
    required this.municipalityId,
    required this.selectedId,
    required this.selectedName,
    required this.onSelected,
  });

  final String municipalityId;
  final String? selectedId;
  final String? selectedName;
  final ValueChanged<Sector> onSelected;

  @override
  ConsumerState<_SectorSearchField> createState() => _SectorSearchFieldState();
}

class _SectorSearchFieldState extends ConsumerState<_SectorSearchField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.selectedName ?? '');
    _query = widget.selectedName ?? '';
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _SectorSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El sector se autocompletó por GPS o cambió el municipio: refleja el
    // nombre en la caja sin pisar lo que el usuario esté escribiendo.
    if (widget.selectedName != oldWidget.selectedName &&
        widget.selectedName != null &&
        !_focusNode.hasFocus) {
      _controller.text = widget.selectedName!;
      _query = widget.selectedName!;
    }
    if (widget.municipalityId != oldWidget.municipalityId &&
        widget.selectedId == null) {
      _controller.clear();
      _query = '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sectorsState = ref.watch(sectorsProvider(widget.municipalityId));

    return sectorsState.when(
      loading: () => const LoadingView(message: 'Cargando sectores…'),
      error: (e, _) => ErrorView(
        message: 'No pudimos cargar los sectores.',
        onRetry: () =>
            ref.invalidate(sectorsProvider(widget.municipalityId)),
      ),
      data: (sectors) {
        final normalizedQuery = _query.trim().toLowerCase();
        final selectedName = widget.selectedName;
        // Muestra la lista solo cuando el campo tiene foco y el texto no
        // coincide ya con el sector seleccionado.
        final showList = _focusNode.hasFocus &&
            !(selectedName != null &&
                normalizedQuery == selectedName.toLowerCase());
        final matches = normalizedQuery.isEmpty
            ? sectors
            : sectors
                .where((s) => s.name.toLowerCase().contains(normalizedQuery))
                .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: 'Sector',
                hintText: 'Escribe para buscar tu sector',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _controller.clear();
                            _query = '';
                          });
                        },
                      ),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            if (showList) ...[
              const SizedBox(height: 8),
              if (matches.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Sin sectores que coincidan.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final sector = matches[index];
                        final isSelected = sector.id == widget.selectedId;
                        return ListTile(
                          dense: true,
                          title: Text(sector.name),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () {
                            widget.onSelected(sector);
                            setState(() {
                              _controller.text = sector.name;
                              _query = sector.name;
                            });
                            _focusNode.unfocus();
                          },
                        );
                      },
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
