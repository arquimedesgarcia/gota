# IMPLEMENTATION PLAN — B1 BETA HARDENING

> Generado por Claude Code (Sonnet) inspeccionando main @ 0e31130. Sin cambios en el repo.

## 1. CURRENT FLOW

- Step 1 **LocationStepView**: "Usar mi ubicación" → GPS (`geolocator_location_service.dart`) → reverse-geocode (`reverse_geocoding_service.dart`) → `LocationSuggestion` guardado en `LeakReportState`. Card de sugerencia (`displayText`, `municipality`, `state` de nominatim) se renderiza **aquí**, debajo del mapa.
- Step 2 **PhotosStepView**: fotos (mín 1).
- Step 3 **DataStepView**: dropdowns de municipio y sector. Ambos inician `null`. La sugerencia ya **no es visible**. No hay matching entre texto nominatim y catálogo. `municipalitiesProvider` carga lista completa; `sectorsProvider(municipalityId)` carga sectores del municipio elegido.
- Step 4 **ReviewStepView** / Step 5 **ResultStepView**.
- `LocationSuggestion.municipalityId` y `sectorId` siempre devuelven `null` por diseño explícito. No existe lógica de preselección.

## 2. ROOT CAUSE

**A. Visibilidad:** La Card de sugerencia vive en Step 1. En Step 3 (donde el usuario elige municipio/sector) la referencia de ubicación ya desapareció de pantalla.

**B. Matching ausente:** `LocationSuggestion.municipality` ("Municipio Arismendi" desde nominatim) nunca se cruza con `Municipality.name` del catálogo. Aunque la información existe en estado, los dropdowns no la usan.

## 3. EXACT FILES

**Modificar:**

| Archivo | Motivo |
|---|---|
| `lib/features/leaks/presentation/leak_report_screen.dart` | Agregar Card compacta en DataStepView; aplicar preselección condicional a los dropdowns |
| `lib/features/leaks/presentation/leak_report_controller.dart` | Agregar `suggestedMunicipalityId` y `suggestedSectorId` a `LeakReportState`; agregar lógica de matching post-sugerencia |

**Modificar (tests):**

| Archivo | Motivo |
|---|---|
| `test/features/leaks/leak_report_flow_test.dart` | Agregar 6 casos B1 (ver §7) |

**No tocar:**
`location_suggestion.dart`, `geolocator_location_service.dart`, `reverse_geocoding_service.dart`, `leak_report_repository.dart`, `municipality_repository.dart`, `sector_repository.dart`, `location_providers.dart`, MapLibre, DB.

## 4. MINIMAL CHANGES

**Controller (`leak_report_controller.dart`):**

- Añadir a `LeakReportState`: `String? suggestedMunicipalityId`, `String? suggestedSectorId` (ambos nullable, default `null`; `copyWith` con defaults).
- En el método que recibe la `LocationSuggestion` (post reverse-geocode OK): correr matching de texto contra la lista de municipios ya cargada → si hay match único, setear `suggestedMunicipalityId`. Si hay `suggestedMunicipalityId`, cargar sectores vía `sectorsProvider` y correr matching → `suggestedSectorId`.
- `selectMunicipality(id)` y `selectSector(id)` existentes no cambian.

**UI (`leak_report_screen.dart` — solo DataStepView):**

- Encima del dropdown de municipio: Card de una línea con `locationSuggestion.displayText` (si no null).
- Dropdown municipio: si `draft.municipalityId == null && state.suggestedMunicipalityId != null` → usar `suggestedMunicipalityId` como `value`. Añadir texto pequeño "Sugerido por GPS" junto al label.
- Dropdown sector: misma lógica con `suggestedSectorId`.
- LocationStepView (Step 1) permanece sin cambios.

## 5. MUNICIPALITY/SECTOR SUGGESTION LOGIC

**Matching municipio:**
- Candidato: `suggestion.municipality ?? suggestion.city`
- Normalización: `toLowerCase()`, trim, strip prefijo `"municipio "` si existe
- Comparación: `Municipality.name.toLowerCase().contains(normalized)` OR `normalized.contains(Municipality.name.toLowerCase())`
- Resultado único → `suggestedMunicipalityId = municipality.id`; ambigüedad o sin match → `null`

**Matching sector** (solo si hay `suggestedMunicipalityId`):
- Candidato: `suggestion.locality ?? suggestion.neighborhood ?? suggestion.city`
- Lista: sectores del `suggestedMunicipalityId` (ya disponibles en `sectorsProvider`)
- Mismo criterio `contains`
- Resultado único → `suggestedSectorId = sector.id`; sino `null`

**Guardia anti-override:**
- La sugerencia preselecciona solo si `draft.municipalityId == null` (resp. `draft.sectorId == null`).
- Una vez el usuario toca el dropdown (`selectMunicipality(id)` / `selectSector(id)`), su elección queda en `draft.*Id`; la UI ignora los `suggested*Id` porque `draft.*Id != null`.
- Cambio manual de municipio ya resetea `sectorId = null` (comportamiento existente conservado).

## 6. UI INTEGRATION

**DataStepView — encima del dropdown de municipio:**
- `if (state.locationSuggestion != null)` → Card compacta: icono pin + `displayText` (1 línea, overflow ellipsis, ~40 dp de alto). No expandible. No interactiva.

**Dropdown municipio:**
- `value`: `draft.municipalityId ?? state.suggestedMunicipalityId`
- Si `state.suggestedMunicipalityId != null && draft.municipalityId == null`: mostrar subtexto "Sugerido según ubicación GPS" debajo del dropdown (12 dp, color `AppColors.textMuted`).

**Dropdown sector:**
- Idéntica lógica; el sector sugerido se aplica solo si el municipio activo coincide con `suggestedMunicipalityId`.

**Android pequeño:** Card de una línea es suficiente (no rediseño); el contenido existente de DataStepView ya scrollea.

## 7. TESTS REQUIRED

En `test/features/leaks/leak_report_flow_test.dart` agregar:

- **[B1-01]** `suggestion.municipality` coincide con catálogo → `suggestedMunicipalityId` seteado en estado.
- **[B1-02]** `suggestion.municipality` sin match → `suggestedMunicipalityId == null`, dropdowns vacíos, sin excepción.
- **[B1-03]** Usuario llama `selectMunicipality(otherId)` antes de DataStep → `draft.municipalityId != null`, `suggestedMunicipalityId` ignorado en UI.
- **[B1-04]** `locationSuggestion == null` (fallback) → no crash, dropdowns vacíos, flujo continúa.
- **[B1-05]** `suggestion.incomplete == true` con `municipality == null` → matching no se ejecuta, `suggestedMunicipalityId == null`.
- **[B1-06]** `suggestedSectorId` solo se setea si el `suggestedMunicipalityId` coincide con el municipio activo del draft.

En `test/features/leaks/data/reverse_geocoding_test.dart`: añadir assertion que el campo `municipality` del JSON llega intacto en el DTO (sin transformación).

## 8. D2 SAFETY CHECK

| Invariante D2 | Estado post-B1 |
|---|---|
| GPS es fuente de verdad geométrica | ✅ Coordenadas no se modifican; `p_latitude`/`p_longitude` del payload intactos |
| `reverse_geocoding_service.dart` sin cambios | ✅ No se toca |
| `LocationSuggestion.municipalityId` y `sectorId` siempre null | ✅ DTO no cambia |
| Matching no sustituye coordenadas | ✅ Matching solo afecta dropdowns de metadata |
| Fallback funciona si sugerencia falla/null | ✅ Si `locationSuggestion == null` o no hay match, dropdowns vacíos exactamente como hoy |
| No nueva Edge Function / no cambios DB | ✅ |
| 89 tests existentes | Riesgo bajo: solo riesgo es que mocks de `LeakReportState` fallen si los 2 campos nuevos no tienen default `null` en `copyWith` — mitigable con defaults explícitos |

## 9. OUT OF SCOPE

- Nueva Edge Function
- Geocoding manual o resolución de IDs en servidor
- Cambios de DB / schema / modelo `LeakReportDraft`
- Modificaciones MapLibre
- Reabrir D2, R1–R4
- Matching fuzzy avanzado (Levenshtein, soundex) — `contains` es suficiente
- Guardar `locationSuggestion` en el payload del reporte
- Internacionalización
- Rediseño de pantallas
- Animaciones adicionales
