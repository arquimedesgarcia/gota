# GOTA v0.2 — Plan de Correcciones Pre-Beta

**Basado en:** `INFORME_AUDITORIA.md` (2026-09-24)

---

## Principio rector

Toda corrección debe ser **behavior-preserving**: mismo comportamiento para el usuario,
mismas reglas de negocio, mismas APIs, mismo modelo de datos, misma seguridad,
mismas rutas, mismo package Android.

El orden de las fases garantiza que cada cambio puede testearse independientemente
antes de pasar al siguiente y que los cambios de refactor (Fase 3) no se mezclan
con los cambios de bugfix (Fase 1-2).

---

## Estructura del plan

```
Fase 1 — Correcciones críticas (P1)       → FASE_1_CRITICOS_PROMPT.md
Fase 2 — Estabilidad (P2 urgentes)        → FASE_2_ESTABILIDAD_PROMPT.md
Fase 3 — Mantenibilidad (refactors P2)    → FASE_3_MANTENIBILIDAD_PROMPT.md
Fase 4 — Cobertura de tests               → FASE_4_TESTS_PROMPT.md
Fase 5 — Polish técnico y documentación   → FASE_5_POLISH_PROMPT.md
```

---

## Fase 1 — Correcciones críticas (P1)

**Hallazgos:** H-01, H-02, H-19
**Duración estimada:** 1 sesión de codificación
**Riesgo de regresión:** Bajo (cambios muy localizados)

| Corrección | Descripción | Archivo principal |
|-----------|-------------|-------------------|
| C1-01     | Reset de waterRegisterControllerProvider al abrir el flujo | water_screen.dart |
| C1-02     | Añadir nextCursor a WaterHistoryState | water_providers.dart |
| C1-03     | Usar nextCursor en loadMore() | water_providers.dart |
| C1-04     | Implementar filtro de cursor en fetchRecentWaterEvents | gota_water_database.dart |

**Prerequisito para Fase 2:** Que `flutter test` pase en verde.

---

## Fase 2 — Estabilidad (P2 urgentes)

**Hallazgos:** H-05, H-08, H-12
**Duración estimada:** 1 sesión de codificación
**Riesgo de regresión:** Bajo

| Corrección | Descripción | Archivo principal |
|-----------|-------------|-------------------|
| C2-01     | Eliminar copyWithPrevious (API privada Riverpod) | notification_providers.dart |
| C2-02     | Remover listener onCircleTapped en dispose() | gota_map_view.dart |
| C2-03     | Estrechar catch en sectorWaterStatusProvider | community_summary_providers.dart |

**Prerequisito para Fase 3:** Que `flutter test` pase en verde.

---

## Fase 3 — Mantenibilidad (refactors P2)

**Hallazgos:** H-03, H-04, H-06, H-07
**Duración estimada:** 1-2 sesiones de codificación
**Riesgo de regresión:** Medio (cambios transversales a múltiples archivos)
**Orden obligatorio:** C3-01 y C3-02 primero (crean la infraestructura);
C3-03 y C3-04 después (consumen la infraestructura).

| Corrección | Descripción | Archivo principal |
|-----------|-------------|-------------------|
| C3-01     | Extraer _rateLimitMessage a core/utils/rate_limit.dart | NUEVO archivo |
| C3-02     | Extraer helper _rpc a core/utils/rpc_helper.dart | NUEVO archivo |
| C3-03     | Reemplazar _rateLimitMessage local en los 3 repos | leak_community_repository.dart, leak_report_repository.dart, water_event_repository.dart |
| C3-04     | Reemplazar _rpc local en los 3 repos | mismo set de archivos + notification_repository.dart |
| C3-05     | Extraer _buildQueryParams en map_providers.dart | map_providers.dart |
| C3-06     | Unificar navegación a LeakReportScreen | app_shell.dart, home_screen.dart |

**Prerequisito para Fase 4:** Que `flutter test` pase en verde.

---

## Fase 4 — Cobertura de tests

**Hallazgos:** H-16, H-17
**Duración estimada:** 1 sesión de codificación
**Riesgo de regresión:** Ninguno (solo añade tests)

| Corrección | Descripción | Archivo |
|-----------|-------------|---------|
| C4-01     | Test de loadMore() con cursor real | test/features/water/water_screen_test.dart |
| C4-02     | Test de MapFilterNotifier.setBounds() con tolerancia | NUEVO: test/features/map/map_filter_notifier_test.dart |

---

## Fase 5 — Polish técnico y documentación

**Hallazgos:** H-09, H-11, H-13, H-14, H-15, H-18, H-20, H-21, H-22, H-23
**Duración estimada:** 1 sesión de codificación
**Riesgo de regresión:** Muy bajo (cambios de nomenclatura, documentación, deps)

| Corrección | Descripción |
|-----------|-------------|
| C5-01     | Mover _currentStep al WaterRegisterController (H-09) |
| C5-02     | Renombrar dx/dy a dMinLat/dMinLng en setBounds (H-13) |
| C5-03     | Reemplazar primaryColor deprecated por colorScheme.primary (H-14) |
| C5-04     | Eliminar TODO obsoleto en build.gradle.kts (H-15) |
| C5-05     | Crear docs/SECURITY.md (H-11) |
| C5-06     | Limpiar TODO de carrusel en leak_detail_screen (H-18) |
| C5-07     | Renombrar supabaseAnonKey a supabasePublishableKey (H-20) |
| C5-08     | Actualizar Firebase deps (minor bumps) (H-21) |
| C5-09     | Corregir features/information/ en ARCHITECTURE.md (H-22) |
| C5-10     | Añadir nota de estado real de paginación en MIGRATION_NOTES (H-23) |

---

## H-10 — Deuda post-beta

La consolidación de las 4 queries HTTP de Home en una RPC `get_home_summary` en
Supabase requiere una migración de base de datos y no es necesaria para la beta
controlada. Se documenta aquí para planificación futura.

---

## Instrucciones generales para el agente de codificación

1. Ejecutar `flutter test` antes de iniciar cada fase como baseline.
2. Aplicar **una corrección a la vez** dentro de cada fase, ejecutar tests después de cada una.
3. **No cambiar comportamiento visible para el usuario.**
4. **No introducir nuevas dependencias.**
5. **No modificar RLS, RPCs de Supabase ni el modelo de datos.**
6. Al terminar cada fase, ejecutar `flutter analyze` y `flutter test`.
7. Si algún test falla después de una corrección, revertir ese cambio específico
   antes de continuar con el siguiente.
8. Crear un commit por fase con el mensaje `fix(quality): fase N — descripción`.
