# Gota — Consolidation Notes

This document records the important consolidation decisions.

## Replaced decisions

| Previous material | Consolidated decision |
|---|---|
| Firebase | Supabase |
| Phone OTP | Anonymous Auth |
| Firestore | PostgreSQL + PostGIS |
| Firebase Storage | Supabase Storage |
| Cloud Functions | Supabase Edge Functions |
| Hive/WorkManager mandatory offline queue | Deferred; not Sprint 01 |
| 1–2 photos | 1–3 photos |
| 2 validation confirmations | Validation is independent; resolution requires 3 distinct users |
| PENDIENTE/CONFIRMADA/CERRADA_* | ACTIVE/RESOLVED |
| Phone hash as public identity | Supabase anonymous user ID, never public |
| Google Maps | MapLibre + OpenStreetMap abstraction |
| Parroquia as mandatory MVP relation | Municipality + configurable sector; do not invent geography |

## Reused from previous material

- visual identity and color tokens;
- screen composition;
- community-oriented microcopy;
- review checklist discipline;
- small-task construction workflow;
- prototype interaction patterns;
- accessibility rules;
- explicit handling of offline/empty/error states as UX concerns.

## Prototype status

`prototipo/index.html` is a visual/interaction reference only.

If prototype behavior contradicts this documentation, this documentation wins.

## Sprint 02 — decisiones de almacenamiento y validación

Revisión posterior al commit `06fe3bd` (correcciones de cierre de Sprint 02):

| Tema | Decisión |
|---|---|
| Rutas de fotos | `report_photos/{auth_user_id}/{upload_key}/{photo_id}.jpg`. La pertenencia se deriva de la ruta, que es lo que exige la política RLS. |
| Lectura de binarios | Sprint 02 no los publica: cada usuario solo lee los suyos. El detalle/mapa de un sprint posterior los resolverá server-side (URLs firmadas). |
| Escritura | Un usuario solo sube a su carpeta. Sin `service_role` en el cliente. |
| Borrado | Permitido solo sobre la carpeta propia: habilita la limpieza de temporales. |
| DML directo | Supabase bloquea `delete`/`update` directos sobre `storage.objects`; la limpieza se hace por la API de Storage (lo que ya hace `_cleanupUploaded()`). |
| Limpieza | Se ejecuta cuando falla la RPC, cuando se detecta `POSSIBLE_DUPLICATE` o cuando el backend rechaza el reporte. Si el borrado falla, se reintenta una vez y el error se muestra al usuario: nunca se dejan huérfanos en silencio. |
| Validación de fotos | Doble capa: cliente (formato/tamaño/cantidad inmediatos) y servidor (autoridad). La RPC verifica cada foto contra `storage.objects` (existencia, pertenencia, `mimetype` y `size`) y contra `system_config.photo_limits` (`max_count`, `max_bytes`, `allowed_mime_types`). Los metadatos persistidos se toman del binario real, no de lo que declare el cliente. |
| Duplicados | REQ-025: el candidato nunca bloquea en silencio. La RPC devuelve `POSSIBLE_DUPLICATE` y solo crea el reporte con `p_ignore_duplicate = true`, que la app envía cuando el usuario confirma "es otra fuga". |
| Operación crítica | Sigue siendo SQL protegido (`security definer`) como en Sprint 01, no una Edge Function: no añade infraestructura nueva y es la costura ya establecida. |
| Supuesto | La RPC lee `storage.objects`, así que el rol que aplica las migraciones necesita lectura sobre ese esquema (es el caso en Supabase local y hospedado; verificado contra la base local). Si no la tuviera, la RPC devuelve `STORAGE_ERROR` (falla cerrado) y no se crea nada. |

### Cierre de auditoría Sprint 02 (`docs/audits/AUDITORIA_SPRINT_02.md`)

Correcciones aplicadas en la migración `20260911000016_audit_sprint02_fixes.sql`
(sin reescribir migraciones previas: solo `GRANT` por columnas y `CREATE OR REPLACE`
de la RPC `create_leak_report` con la **misma firma y mismos `status_code`**).

| Hallazgo | Decisión de cierre |
|---|---|
| AUD-S2-01 / AUD-S2-02 (privacidad, BLOQUEANTE) | `revoke all` + `grant select (columnas no sensibles)` en `public.reports`; se excluye `created_by` (y cualquier columna de identidad). En `public.report_photos` se retira **toda** lectura del cliente (el detalle ya expone `photo_count` vía RPC). Cubierto por `create_leak_report_test.sql` (4a-priv, 4a-priv2, 4d-priv, 9b/9c/9d/9e). |
| AUD-S2-03 (ubicación manual) | Cerrado con **desviación documentada**: manual = coordenadas hasta Sprint 05 (MapLibre). No se añade geofence bbox porque los docs no definen el bbox de Nueva Esparta y la auditoría prohíbe inventarlo; la validación de rango (`INVALID_LOCATION`) ya existe en la RPC. |
| AUD-S2-07 (candidatos sin `ORDER BY`) | El `LIMIT 5` se aplica sobre una subconsulta ya ordenada por distancia; `candidates.first` es siempre el más cercano. Cubierto por `OK 10`. |
| AUD-S2-08 (miniaturas / dimensiones) | Cerrado de forma **honesta**: se excluyen las miniaturas en este sprint y `width`/`height` se persisten solo cuando el binario los aporta (la RPC no los inventa). El comentario de `photo_service.dart` ya no promete que \"el servidor determina las dimensiones\". No se sube un segundo binario a Storage (no hay ruta de thumbnail definida en RLS). |
| AUD-S2-10 (longitud `description`) | La RPC devuelve `VALIDATION_ERROR` si `char_length(description) > 500` (antes `check_violation`). |
| AUD-S2-11 (`LIKE` con `_`) | La pertenencia de la foto se comprueba con `starts_with`, no con `LIKE`. |
| AUD-S2-18 / AUD-S2-19 (deuda/prueba) | `audit_events.user_id` NO se migra en esta sesión (riesgo): sigue usando `auth.uid()`; la inconsistencia con `app_users.id` queda documentada. La aserción 3b del test SQL se endureció (ya no acepta `when others` como éxito). |

**Deuda declarada (no resuelta en Sprint 02):** rutas de Storage que contienen
`auth.uid()` (`report_photos/{auth_user_id}/…`); dejar de exponerlo exige cambiar las
rutas o publicar solo por URLs firmadas server-side (previsto para el sprint de fotos
públicas). MapLibre y el plist de cámara iOS quedan fuera de alcance.

## Sprint 03 — decisiones de validación y resolución

Implementación del ciclo comunitario sobre el patrón de Sprint 02 (RPC SQL
protegida, sin Edge Functions ni infraestructura nueva).

| Tema | Decisión |
|---|---|
| Validación | `REQ-040`–`REQ-044` implementadas tal cual: cualquier identidad anónima no bloqueada valida una fuga ACTIVE de otro usuario, una sola vez por reporte, con el creador excluido. La regla vive en la RPC `validate_leak`, no en la UI. |
| Duplicados | La autoridad real es `UNIQUE (report_id, user_id)` en `report_validations` / `resolution_confirmations`. La segunda acción devuelve `DUPLICATE_ACTION` (resultado de dominio, no error genérico) y no altera contadores ni estado. |
| Umbral | Sigue siendo **3 identidades distintas** (REQ-053). Se guarda en `system_config.resolution = {"threshold": 3}` en lugar de quedar hard-codeado en la función; la RPC lo lee con respaldo 3. |
| Ambigüedad de REQ-051 | El texto ("el creador puede participar solo si no está confirmando su propio reporte como mecanismo de validación de existencia") es ambiguo. Decisión mínima compatible: `confirm-leak-resolution` en `API_SPEC.md` **no** excluye al creador (a diferencia de `validate-leak`, que sí lo hace) y REQ-050 dice "cualquier usuario". Por tanto el creador **no** puede validar la existencia de su fuga, pero **sí** puede confirmar su resolución, una sola vez y con las mismas garantías que cualquier otra identidad. La decisión está cubierta por prueba (`OK 4i`). |
| Estados | Solo ACTIVE/RESOLVED, sin estados nuevos. Ninguna operación permite `RESOLVED → ACTIVE`; una fuga resuelta responde `REPORT_ALREADY_RESOLVED`. |
| Atomicidad y concurrencia | Cada RPC: identidad → `for update` sobre la fila del reporte → inserción con `on conflict do nothing` → incremento de contador y (si procede) `status`/`resolved_at` en la misma sentencia → auditoría. Todo en una transacción; el bloqueo de fila serializa accesos concurrentes. Verificado con dos y cuatro sesiones reales en paralelo (`supabase/tests/community_concurrency_e2e.sh`). |
| Privacidad de las tablas de acciones | `report_validations` y `resolution_confirmations` no son legibles ni escribibles por el cliente (RLS sin políticas + `REVOKE ALL`). El estado propio ("¿ya validé?") llega por la RPC `get_leak_report_detail`, evitando exponer qué validó cada identidad. |
| Lecturas de la UI | El listado de "Fugas cerca de ti" usa una lectura sencilla por SDK con RLS (recursos embebidos `sectors(name)` / `municipalities(name)`); el detalle y las acciones pasan por RPC. |
| Pendiente declarado (fuera de Sprint 03) | Las fotografías siguen sin publicarse entre usuarios: el detalle muestra el conteo, no binarios ajenos. Publicarlas exige URLs firmadas server-side (Sprint 02 lo dejó explícitamente para un sprint posterior). |

## Sprint 04 — Eventos de agua (validación comunitaria)

Implementación del ciclo de eventos de agua (llegada/salida del suministro) sobre
el patrón de Sprint 02/03 (RPC SQL protegida, validación comunitaria, estadísticas
descriptivas sin predicción).

| Tema | Decisión |
|---|---|
| Modelo de datos | `water_events` (id, created_by, municipality_id, sector_id, event_type, event_time, comment, validation_count, created_at, updated_at) + `water_event_validations` (id, water_event_id, user_id, created_at) con `UNIQUE (water_event_id, user_id)`. |
| event_time vs created_at | Separados por diseño (REQ-072): `event_time` es la hora efectiva del evento (lo que el usuario declara), `created_at` es el timestamp de inserción. Nunca colapsan. |
| Tipo de evento | Solo `WATER_ARRIVED` y `WATER_LEFT` (REQ-070), validado en la tabla y la RPC. |
| Comentario | Opcional, máx 500 caracteres (REQ-031 del prototipo anterior), normalizado a NULL si es vacío. |
| Validación | Patrón idéntico a Sprint 03: `UNIQUE (water_event_id, user_id)`, creador excluido (server-side en RPC), `DUPLICATE_ACTION` determinista. |
| Contador | `validation_count` se incremente atómicamente con la inserción en `water_event_validations` dentro de la misma transacción (RPC). |
| Privacidad de created_by | La identidad del creador se persiste pero NUNCA se expone en consultas públicas (ni en `fetchRecentWaterEvents` ni en `get_water_event_detail`). |
| Estadísticas | Descriptivas puras (REQ-077): cuentas, últimas llegadas/salidas, duraciones promedio de pares consecutivos (ARRIVED→LEFT, LEFT→ARRIVED) del mismo sector. Sin predicción, sin tendencias. Muestra "Sin datos suficientes" si no hay pares. |
| Rate limiting | Declarado para Sprint 07 (mismo precedente Sprint 03). REQ-091 lo asigna a "Security & abuse". |
| Paginación | Keyset (cursor: event_time + id), default limit 20. Implementación simplificada sin filtros OR anidados (compatibilidad client SDK). El filtro lte('event_time') aplica el keyset en la query. WaterHistoryController.loadMore() usa state.nextCursor. [Corregido en auditoría pre-beta 2026-09-24: H-02, H-19] |
| Lectura de la UI | Lista pública de eventos por `fetchRecentWaterEvents` (sin `created_by`); detalle y estado propio vía RPC `get_water_event_detail`. |
| RLS | `water_events` lectura pública, INSERT/UPDATE/DELETE solo por RPC. `water_event_validations` sin acceso cliente (igual que `report_validations`). |
| Operación crítica | SQL protegido (`security definer`, `set search_path = ''`) para `register_water_event`, `validate_water_event`, `get_water_event_detail`. GRANT EXECUTE solo a `authenticated`. |
| Pestaña "Agua" | Integrada en AppShell (índice 3), reemplaza PlaceholderScreen. |

## Auditoría Sprint 01 — decisiones de corrección (AUD-S1-*)

Correcciones aplicadas en la migración `20260911000015_audit_sprint01_fixes.sql`
(aditiva e idempotente; no reescribe migraciones ya aplicadas).

| Tema | Decisión |
|---|---|
| `INTERNET` en release (AUD-S1-01) | Permisos añadidos al `AndroidManifest.xml` principal; verificado en el APK release. |
| Sectores (AUD-S1-02) | **Sin siembra de datos.** Documentado el hueco operativo: el catálogo se carga por migración futura solo con fuente validada; sin sectores, `create_leak_report` responde `INVALID_SECTOR` y el flujo es inejecutable. |
| `SUPABASE_ENV` (AUD-S1-03) | Se mantiene como **metadato de despliegue** (`isProduction` disponible, sin efecto en reglas de negocio): no altera runtime ni backend. |
| INSERT en `app_users` (AUD-S1-04) | Retirados el GRANT de `insert` a `authenticated` y la política "Usuario crea su propio perfil". La fila la crean el trigger `handle_new_user` y `ensure_app_user()` (ambas `security definer`). |
| PostGIS (AUD-S1-05) | `20260911000015` falla cerrado (`raise exception`) si `postgis` no está habilitada. La migración original `00001` ya aplicada no se reescribe. |
| `ensure_app_user` sin `auth.uid()` (AUD-S1-06) | La RPC ahora firma `jsonb` y devuelve `{"status_code": "UNAUTHORIZED", "message": …}` si no hay sesión, alineada con el patrón de `validate_leak`. No inserta filas y no expone la violación NOT NULL. El cliente ya maneja el valor como excepción de dominio. |
| `fetchAppUserByAuthId` (AUD-S1-07) | Eliminada de la interfaz, la implementación y los fakes (ningún repositorio la usaba). |
| CI (AUD-S1-08) | Workflow GitHub Actions mínimo: `flutter analyze` + `flutter test`. Sin secretos ni deploy. |
| README (AUD-S1-09) | Estado y lista de migraciones sincronizados con HEAD. |

## Sprint 05 — Mapa (decisiones de diseño)

| Tema | Decisión |
|---|---|
| Migración | **No se creó migración de esquema** para la feature de mapa (tablas, columnas, índices). El índice espacial `reports_location_gix` y el campo `location` ya existían. Sí se creó `20260911000017_map_reports.sql` para la RPC `get_map_reports` (solo lógica de función, sin DDL de tablas). |
| SECURITY DEFINER en `get_map_reports` | Necesario para JOIN con `sectors` y `municipalities` respetando `search_path = ''`. La función no expone filas que el SELECT directo sobre `reports` no mostraría (RLS pública). No relaja ni sustituye RLS. GRANT EXECUTE a `anon` y `authenticated` (mapa público). |
| Water Events fuera del mapa | Los `water_events` son eventos de sector/municipio sin coordenadas geoespaciales. No se añaden coordenadas ni se renderizan en el mapa. La cadena usuario → sector de interés → notificación pertenece a Sprint 06. |
| "Mi sector" sin modelo de sector del usuario | No existe en Sprint 05 un modelo de "sector preferido del usuario". "Mi sector" requiere selección explícita vía `setSectorId()`. La inferencia GPS fue evaluada y descartada: tomar el sector del primer reporte cercano es heurísticamente incorrecta y haría doble llamada al backend. Dependencia: Sprint 06 (Notifications). |
| "Mi sector" UX mejorada | Cuando `filterType == mySector` y `selectedSectorId == null`, la UI muestra un mensaje específico ("Configura tu sector") en lugar del mensaje genérico. Esto guía al usuario a entender por qué la lista está vacía y qué acción tomar (ir al perfil). Implementado en `_MapEmptyView`. |
| Bounding box del viewport (Sprint 05 hardening) | Implementada captura de viewport bounds desde MapLibre (`onCameraIdle`) y flujo completo a PostGIS RPC. `GotaMapView` recibe `onBoundsChanged` callback, `_MapLibreMapView._onCameraIdle()` captura `getVisibleRegion()`, fluye a `MapFilterState.{minLat, minLng, maxLat, maxLng}`, y `mapReportsProvider` pasa los bounds a `repository.mapReports()`. El índice espacial `reports_location_gix` optimiza la consulta cuando bbox está presente. En tests, el `_testMapBuilder` no implementa cámara, por lo que bounds permanece null y la RPC retorna todos los reportes (hasta limit). |
| Tile URL configurable | `MAP_TILE_STYLE_URL` es un dart-define con defecto a los tiles de demo de MapLibre. En producción debe suministrarse una URL real. No se almacena en `AppConfig` para no requerir cambios en el ciclo de validación de la config (URL de tiles no es crítica para el arranque de la app). |
| Estado visual "Validada" derivado en cliente (beta) | El backend solo mantiene `ACTIVE`/`RESOLVED` (00007); no existe estado ni umbral de validación que dispare transición. Para la leyenda de 3 estados del mapa se deriva en cliente: `ACTIVE` con `validation_count >= 3` se muestra como **Validada**; el umbral replica `system_config.resolution.threshold` (= 3, 00013) y vive en `kValidatedCountThreshold` (`lib/features/map/domain/leak_map_status.dart`). No introduce status de backend ni altera las RPC. |
| Colores de estado del mapa (beta) | Paleta corregida: Reportada=azul (`AppColors.primary`), Validada=rojo (`AppColors.danger`), Resuelta=verde (`AppColors.success`). Mapeo único en `leakMapStatusColor`, compartido por markers, leyenda y lista del mapa. |
| Basemap productivo (beta) | El defecto de `MAP_TILE_STYLE_URL` cambia de los demotiles de MapLibre al estilo vectorial **Liberty de OpenFreeMap** (`https://tiles.openfreemap.org/styles/liberty`): calles, nombres, edificaciones, parques y agua. Gratuito, sin API key; la atribución (© OpenStreetMap / OpenFreeMap) la muestra MapLibre desde el propio estilo. |
| Zoom programático y bounds (beta) | Se añadieron botones +/− sobre el mapa (`_zoomBy` con `moveCamera` sobre el controlador existente, sin segundo mapa). Tras cada zoom se emiten los bounds visibles explícitamente (`_emitVisibleBounds`, dos emisiones 350 ms/700 ms) porque `onCameraIdle` del plugin Android no siempre dispara con cámaras programáticas y `getVisibleRegion` puede devolver la región previa. |
| Deadlock del estado vacío con bbox (beta) | Si el viewport quedaba sin reportes, el estado vacío desmonta el mapa y el bbox quedaba fijo en la zona vacía: ningún filtro, gesto o botón podía recuperar los reportes (solo reiniciar la app). Ahora, al entrar en estado vacío en modo mapa, se limpia el bbox (`MapFilterNotifier.clearBounds`) para que el refetch vuelva a consultar sin límite espacial; si realmente no hay reportes es un no-op (sin bucle). Comportamiento de ocultar el mapa en vacío se mantiene por decisión del usuario. |
| Acoplamiento de excepciones | `MapLocationAction` captura `Exception` genérico (no `LeakFlowException`). La clase de ubicación (`LocationService`) vive en el feature leaks; la dependencia es de datos (la abstracción), no de dominio. Refactorizar la abstracción de ubicación a un módulo compartido queda fuera del alcance de Sprint 05. |
| `didUpdateWidget` en markers | Comparación por IDs de lista en lugar de referencia de objeto para evitar redraws innecesarios cuando Riverpod retorna instancias nuevas con los mismos datos. |
| Fuentes de verdad mapa/lista | Ambas vistas consumen `mapReportsProvider` (mismo FutureProvider). Filtros coherentes garantizados; no es posible divergencia entre vistas. |
| Límite de reportes | Default 100, cap server-side 200 (validado en RPC). No se implementa paginación keyset para el mapa en Sprint 05; el límite es suficiente para el MVP. Paginación incremental del mapa (viewport-based) queda para cuando el volumen lo justifique. |

## Actividad reciente en el Home — global (migración 00029)

| Tema | Decisión |
|---|---|
| Umbral de validación en `system_config` | Hasta hoy el umbral "validada" solo vivía en el cliente (`validatedThreshold = 3`); el servidor no lo conocía. 00029 siembra `system_config.validation = {"threshold": 3}` y expone `public.validation_threshold()` copiando el patrón de `resolution_threshold()` (00013): función **interna** (`revoke execute … from public, anon, authenticated`), `security definer`, `search_path = ''`, respaldo `greatest(coalesce(…, 3), 1)`. |
| Evento VALIDATED = **cruce** del umbral | "Validada" es un estado derivado (el `validation_count` alcanzó el umbral), así que el evento es el momento en que lo cruzó: el `created_at` de la N-ésima validación (N = umbral), orden `(created_at, id)`. La 1ª y la 2ª validación con umbral 3 **no** son evento; la 3ª sí. Cubierto por prueba (`OK 2`, `OK 3` en `supabase/tests/community_activity_test.sql`). |
| Limitación aceptada: recálculo si cambia el umbral | `validation_count` es monótono (no existe RPC para des-validar), pero el umbral es configurable. Si se cambiara en el futuro, el `at` histórico del evento VALIDATED se **recalcularía** con el umbral nuevo. Es el precio de derivar el estado en vez de persistirlo; se acepta mientras el umbral no cambie en el piloto (probado en `OK 5b`). |
| Deuda: el cliente sigue usando su default `3` | Traer el umbral del servidor al cliente para reemplazar el `3` hard-codeado (`gota_community_database.dart`, `community_summary_repository.dart`, `kValidatedCountThreshold`) queda **documentado como pendiente, no implementado** (fuera de alcance). Mientras el umbral no cambie, cliente y servidor coinciden. |
| RPC `get_latest_community_activity` | Global (sin filtro de sector), `returns table` con 0 o 1 fila, `security definer`, `search_path = ''`. No usa `union all` sobre TODOS los `reports`: cada tipo resuelve su candidato con `order by … limit 1` (`reports_created_at_idx` para REPORTED; el índice parcial `reports_resolved_at_idx` nuevo para RESOLVED) y VALIDATED usa un `join lateral` posicional sobre `report_validations` — la única lectura de esa tabla, válida por ser definer (el cliente sigue sin acceso). Grants `anon, authenticated` (lectura pública, como `get_map_reports`). Privacidad REQ-100: el DTO no expone ninguna identidad (probado en `OK 7`). |
| Estado real vs tipo de evento en la fila | La tarjeta pinta la fila con el `status` **actual** de la falla (`ACTIVE`/`RESOLVED`), no con el tipo de evento: un REPORTED o VALIDATED de una falla que sigue ACTIVE se muestra como activa. |
