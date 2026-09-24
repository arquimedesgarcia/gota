# GOTA v0.2 — AUDITORÍA DE INGENIERÍA Y CALIDAD DE CÓDIGO PRE-BETA

**Fecha:** 2026-09-24 | **Rama auditada:** `fix/map-r5-r6` | **Auditor:** Claude Sonnet 4.6

---

## A. Executive Summary

El código está en **buen estado general** para una aplicación en beta controlada.
`flutter analyze` no reporta ningún issue, todos los tests pasan, y la arquitectura
tiene una separación de capas limpia y coherente (UI → Notifier → Repository → Database → Supabase).
No existen credenciales hardcodeadas ni secretos en el repositorio.

**Principales riesgos identificados:**
- Un **bug funcional** en el formulario de registro de agua (P1): `waterRegisterControllerProvider`
  no se reinicia entre aperturas del flujo; en la segunda visita el formulario reutiliza datos de
  la sesión anterior, incluyendo el `submitStatus: done` que no bloquea un reenvío accidental.
- **Keyset pagination parcialmente no implementada** (P1): `WaterHistoryController.loadMore()`
  siempre envía `cursor: null`, obteniendo siempre la primera página en lugar de la siguiente.
- **Duplicación sistemática** en tres repositorios (P2): `_rateLimitMessage` y el helper `_rpc`
  se repiten con leves variaciones, aumentando el riesgo de divergencia.
- **Uso de API privada de Riverpod** (P2): `copyWithPrevious` suprimido con
  `ignore: invalid_use_of_internal_member` podría romperse en upgrades.

**No hay bloqueantes de seguridad críticos. No hay P0 funcionales que impidan operar.**

---

## B. Validación del estado actual

```
flutter analyze   → No issues found (ran in 5.3s)
flutter test      → Todos los tests pasan
TODOs activos     → 1 (leak_detail_screen.dart línea ~126: Photo carousel)
Deprecated APIs   → Theme.of(context).primaryColor en 4 lugares (water step widgets)
ignore suprimidos → 2
  - invalid_use_of_internal_member en notification_providers.dart
  - unused_element en leak_report_screen.dart
```

No hay fallos preexistentes. Los dos `ignore:` son conocidos y preexistentes.

---

## C. Hallazgos

### H-01 — Bug: formulario de agua no se reinicia entre sesiones
```
Prioridad:          P1 — Alto
Categoría:          Flutter / Riverpod / Estado
Archivo:            lib/features/water/presentation/water_screen.dart
                    lib/features/water/presentation/water_register_controller.dart
Símbolo/método:     waterRegisterControllerProvider, WaterScreen._openRegister()
Problema:           waterRegisterControllerProvider no es autoDispose y no tiene lógica
                    de reset al abrir el flujo. Cuando el usuario completa un registro
                    (submitStatus = done), cierra la pantalla y la vuelve a abrir,
                    la UI inicia con _currentStep = 0 (estado local) pero el controller
                    tiene los datos del evento anterior (municipio, sector, hora,
                    submitStatus: done). submit() solo bloquea si submitStatus == submitting;
                    con done pasa la validación local y re-envía el evento anterior.
Evidencia:          WaterRegisterController.build() devuelve WaterRegisterState(
                    eventTime: DateTime.now()), pero solo se ejecuta una vez por
                    ciclo de vida del provider. WaterScreen._openRegister() invalida
                    waterHistoryControllerProvider pero no waterRegisterControllerProvider.
Riesgo:             Doble registro silencioso si el usuario toca Confirmar en el
                    paso 3 de una segunda visita sin rellenar nada nuevo.
Mejora:             Añadir ref.invalidate(waterRegisterControllerProvider) en
                    WaterScreen._openRegister() antes del push, igual que AppShell
                    invalida leakReportProvider antes de abrir LeakReportScreen.
Complejidad:        Trivial — una línea.
```

### H-02 — Bug: loadMore() no avanza páginas (cursor siempre null)
```
Prioridad:          P1 — Alto
Categoría:          Supabase / Paginación
Archivo:            lib/features/water/presentation/water_providers.dart
                    lib/core/network/gota_water_database.dart
Símbolo/método:     WaterHistoryController.loadMore(), fetchRecentWaterEvents()
Problema:           loadMore() invoca repository.recentEvents(cursor: null) siempre.
                    El cursor se construye en recentEvents() como nextCursor en
                    WaterEventsPage, pero loadMore() nunca lo usa. Cada "cargar más"
                    obtiene la primera página de 20 eventos. El dedup por id los filtra
                    y hasMore puede quedar true indefinidamente.
Evidencia:          water_providers.dart ~línea 105:
                    cursor: null, // Implementación futura: keyset pagination con cursor
Riesgo:             Usuarios con historial > 20 eventos no ven el historial completo.
                    Posible loop de requests idénticos.
Mejora:             Guardar nextCursor en WaterHistoryState y pasarlo en loadMore().
Complejidad:        Pequeña.
```

### H-03 — Duplicación: _rateLimitMessage en tres repositorios
```
Prioridad:          P2 — Medio
Categoría:          Mantenibilidad / Duplicación
Archivos:           lib/features/leaks/data/leak_community_repository.dart (línea ~202)
                    lib/features/leaks/data/leak_report_repository.dart    (línea ~234)
                    lib/features/water/data/water_event_repository.dart    (línea ~239)
Problema:           La función _rateLimitMessage está copiada con el mismo cuerpo en
                    tres archivos. Solo difiere el mensaje por defecto.
Mejora:             Extraer a lib/core/utils/rate_limit.dart.
Complejidad:        Pequeña.
```

### H-04 — Duplicación: helper _rpc en tres repositorios
```
Prioridad:          P2 — Medio
Categoría:          Mantenibilidad / Duplicación
Archivos:           lib/features/leaks/data/leak_community_repository.dart
                    lib/features/water/data/water_event_repository.dart
                    lib/features/notifications/data/notification_repository.dart
Problema:           Los tres repositorios definen un método _rpc idéntico que envuelve
                    llamadas async traduciendo TimeoutException, SocketException,
                    http.ClientException, PostgrestException y AuthException.
Mejora:             Extraer como función o clase en lib/core/utils/rpc_helper.dart,
                    parametrizando los mensajes de error opcionales.
Complejidad:        Pequeña-media.
```

### H-05 — API privada de Riverpod suprimida con ignore
```
Prioridad:          P2 — Medio
Categoría:          Riverpod / API privada
Archivo:            lib/features/notifications/presentation/notification_providers.dart
Símbolo/método:     NotificationPreferencesController._save() ~línea 69
Problema:           Uso de copyWithPrevious con ignore: invalid_use_of_internal_member.
                    API no garantizada entre versiones menores de flutter_riverpod.
Mejora:             Guardar el estado previo manualmente en _save() y restaurarlo en
                    el catch, sin necesidad de copyWithPrevious.
Complejidad:        Pequeña.
```

### H-06 — Duplicación: switch de filtros entre mapReportsProvider y listReportsProvider
```
Prioridad:          P2 — Medio
Categoría:          Mantenibilidad / Duplicación
Archivo:            lib/features/map/presentation/map_providers.dart
Símbolo/método:     mapReportsProvider, listReportsProvider
Problema:           Los dos providers contienen un switch idéntico sobre
                    filterState.filterType. La única diferencia es que mapReportsProvider
                    pasa bounds y listReportsProvider los pasa null.
Mejora:             Extraer la construcción de parámetros en _buildQueryParams().
Complejidad:        Trivial.
```

### H-07 — Lógica de navegación a ReportFlow duplicada
```
Prioridad:          P2 — Medio
Categoría:          Duplicación / Arquitectura
Archivos:           lib/app/router/app_shell.dart
                    lib/features/home/presentation/home_screen.dart
Símbolo/método:     AppShell._openReportFlow(), HomeScreen._openReport()
Problema:           Ambos métodos invalidan providers y abren LeakReportScreen con
                    lógica post-retorno. HomeScreen no invalida mapReportsProvider;
                    AppShell sí. Inconsistencia: mapa desactualizado si se reporta
                    desde Home.
Mejora:             Centralizar en AppShell o función compartida. Home llama al shell.
Complejidad:        Pequeña.
```

### H-08 — Lifecycle: listener onCircleTapped no se remueve en dispose
```
Prioridad:          P2 — Medio
Categoría:          MapLibre / Lifecycle
Archivo:            lib/features/map/presentation/widgets/gota_map_view.dart
Símbolo/método:     _MapLibreMapViewState._onMapCreated, dispose()
Problema:           controller.onCircleTapped.add(callback) nunca se elimina en
                    dispose(). La guardia _mapCreated = false reduce el riesgo pero
                    onCircleTapped no la consulta antes de dispararse.
Mejora:             Guardar referencia al callback y llamar remove() en dispose().
Complejidad:        Trivial.
```

### H-09 — _currentStep local puede desincronizarse del controller en rotación
```
Prioridad:          P2 — Medio
Categoría:          Flutter / Estado inconsistente
Archivo:            lib/features/water/presentation/water_register_screen.dart
Símbolo/método:     _WaterRegisterScreenState._currentStep
Problema:           _currentStep es estado local del widget. Un cambio de configuración
                    (rotación) lo resetea a 0 mientras el controller conserva los datos
                    del paso 3. La UI muestra paso 1 pero el controller tiene municipio
                    y sector ya rellenos.
Mejora:             Mover _currentStep al WaterRegisterController como campo del estado,
                    o usar PageStorageKey.
Complejidad:        Pequeña.
```

### H-10 — Home hace 4 queries HTTP separadas por carga
```
Prioridad:          P2 — Medio
Categoría:          Supabase / Eficiencia
Archivos:           lib/features/home/presentation/community_summary_providers.dart
                    lib/features/leaks/data/community_summary_repository.dart
Símbolo/método:     communitySummaryProvider, CommunitySummaryRepository.todaySummary()
Problema:           todaySummary() realiza 4 queries HTTP separadas. Un cambio de
                    preferencias dispara 5 queries (communitySummary + sectorWaterStatus).
Mejora:             Deuda post-beta: consolidar en RPC get_home_summary en Supabase.
Complejidad:        Media (requiere migración Supabase).
```

### H-11 — Anon key embebida en APK: riesgo documentado
```
Prioridad:          P2 — Medio
Categoría:          Seguridad / Información
Problema:           SUPABASE_ANON_KEY queda embebida en el APK (dart-define estándar).
                    La anon key es por diseño pública, pero conviene documentar que
                    la seguridad descansa en RLS y no en el secreto de la clave.
Mejora:             Crear docs/SECURITY.md documentando el modelo de seguridad.
Complejidad:        Documentación (trivial).
```

### H-12 — sectorWaterStatusProvider captura ALL exceptions silenciosamente
```
Prioridad:          P2 — Medio
Categoría:          Manejo de errores
Archivo:            lib/features/home/presentation/community_summary_providers.dart
Símbolo/método:     sectorWaterStatusProvider
Problema:           catch (_) captura todo, incluyendo errores de programación
                    (NullPointerException, assertion errors). La UI muestra "Sin
                    información" sin ninguna pista de que hay un bug real.
Mejora:             Capturar solo AppException, TimeoutException y SocketException.
Complejidad:        Trivial.
```

### H-13 — Nomenclatura confusa: dx/dy para diferencias lat/lng en setBounds
```
Prioridad:          P2 — Medio (nomenclatura GIS crítica)
Categoría:          Mantenibilidad / Nomenclatura
Archivo:            lib/features/map/presentation/map_providers.dart
Símbolo/método:     MapFilterNotifier.setBounds()
Problema:           dx, dy, dx2, dy2 son diferencias de latitud y longitud, no
                    coordenadas x/y del plano. Confusión clásica GIS.
Mejora:             Renombrar a dMinLat, dMinLng, dMaxLat, dMaxLng.
Complejidad:        Trivial.
```

### H-14 — Theme.of(context).primaryColor deprecated en Material 3
```
Prioridad:          P3 — Bajo
Categoría:          Mantenibilidad / Deprecated API
Archivos:           lib/features/water/presentation/water_register_step_municipality.dart
                    lib/features/water/presentation/water_register_step_sector.dart
Problema:           primaryColor deprecated en Material 3. La API correcta es
                    colorScheme.primary o AppColors.primary.
Complejidad:        Trivial.
```

### H-15 — Comentario TODO obsoleto en build.gradle.kts
```
Prioridad:          P3 — Bajo
Categoría:          Configuración
Archivo:            android/app/build.gradle.kts
Problema:           Comentario heredado "TODO: Specify your own unique Application ID"
                    cuando el ID ya está correctamente especificado.
Complejidad:        Trivial.
```

### H-16 — Sin test para WaterHistoryController.loadMore()
```
Prioridad:          P3 — Bajo
Categoría:          Tests
Archivo:            test/features/water/water_screen_test.dart
Problema:           loadMore() no tiene tests. El bug H-02 pasó sin detectarse.
Mejora:             Test que verifique avance de página con cursor.
Complejidad:        Pequeña.
```

### H-17 — Sin test para MapFilterNotifier.setBounds() con tolerancia
```
Prioridad:          P3 — Bajo
Categoría:          Tests
Archivo:            test/features/map/leak_map_status_test.dart (o nuevo archivo)
Problema:           La lógica de deduplicación por tolerancia 1e-5 no está cubierta.
Complejidad:        Trivial.
```

### H-18 — TODO activo sin ticket en leak_detail_screen
```
Prioridad:          P3 — Bajo
Categoría:          Mantenibilidad
Archivo:            lib/features/leaks/presentation/leak_detail_screen.dart
Problema:           // TODO: Photo carousel - reintroduce after test refactoring
                    Sin fecha ni referencia de backlog.
Complejidad:        Documentación.
```

### H-19 — Parámetro cursor declarado pero nunca usado en fetchRecentWaterEvents
```
Prioridad:          P3 — Bajo (relacionado con H-02)
Categoría:          Supabase / Implementación incompleta
Archivo:            lib/core/network/gota_water_database.dart
Símbolo/método:     SupabaseGotaWaterDatabase.fetchRecentWaterEvents()
Problema:           El método acepta WaterEventCursor? cursor pero nunca aplica
                    un filtro basado en él. API engañosa: cualquier caller que pase
                    un cursor no nulo obtiene siempre la primera página.
Complejidad:        Pequeña (implementar el filtro real).
```

### H-20 — Nomenclatura interna: supabaseAnonKey vs publishableKey de la librería
```
Prioridad:          P3 — Bajo
Categoría:          Mantenibilidad
Archivos:           lib/core/config/app_config.dart, main.dart
Problema:           El campo de AppConfig se llama supabaseAnonKey pero el parámetro
                    de supabase_flutter ahora es publishableKey. Confusión de lectura.
Complejidad:        Trivial (renombrado).
```

### H-21 — Dependencias con updates disponibles
```
Prioridad:          P3 — Bajo
Categoría:          Dependencias
Problema:           geolocator 13.0.4 → 14.0.3 (major, evaluar CHANGELOG).
                    firebase_core 4.14.0 → 4.15.0 (minor, seguro).
                    firebase_messaging 16.6.0 → 16.7.0 (minor, seguro).
Complejidad:        Trivial para los minor bumps de Firebase.
```

### H-22 — ARCHITECTURE.md referencia features/information/ que no existe
```
Prioridad:          P3 — Bajo
Categoría:          Documentación
Archivo:            docs/ARCHITECTURE.md (línea 54)
Problema:           El diagrama lista features/information/ pero el directorio real
                    es features/contact/. Un agente futuro crearía código en el lugar
                    equivocado.
Complejidad:        Trivial (edición de documentación).
```

### H-23 — MIGRATION_NOTES documenta keyset pagination como implementada
```
Prioridad:          P3 — Bajo
Categoría:          Documentación
Archivo:            docs/MIGRATION_NOTES.md (línea ~111)
Problema:           La doc describe la intención (cursor: event_time + id) sin indicar
                    que el cursor nunca se aplica en el cliente (H-02, H-19).
                    Un agente futuro asumirá que loadMore() ya funciona correctamente.
Complejidad:        Trivial (nota aclaratoria).
```

---

## D. Resumen de prioridades

| ID   | Prioridad | Complejidad | Fase |
|------|-----------|-------------|------|
| H-01 | P1        | Trivial     | 1    |
| H-02 | P1        | Pequeña     | 1    |
| H-19 | P1/P3     | Pequeña     | 1    |
| H-05 | P2        | Pequeña     | 2    |
| H-08 | P2        | Trivial     | 2    |
| H-12 | P2        | Trivial     | 2    |
| H-07 | P2        | Pequeña     | 3    |
| H-03 | P2        | Pequeña     | 3    |
| H-04 | P2        | Media       | 3    |
| H-06 | P2        | Trivial     | 3    |
| H-16 | P3        | Pequeña     | 4    |
| H-17 | P3        | Trivial     | 4    |
| H-09 | P3        | Pequeña     | 5    |
| H-13 | P3        | Trivial     | 5    |
| H-14 | P3        | Trivial     | 5    |
| H-11 | P2        | Trivial     | 5    |
| H-15 | P3        | Trivial     | 5    |
| H-18 | P3        | Trivial     | 5    |
| H-20 | P3        | Trivial     | 5    |
| H-21 | P3        | Trivial     | 5    |
| H-22 | P3        | Trivial     | 5    |
| H-23 | P3        | Trivial     | 5    |
| H-10 | P2        | Media       | post-beta |
