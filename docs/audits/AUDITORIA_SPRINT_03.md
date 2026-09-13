# Auditoría — Sprint 03 (Validation & Resolution)

**Proyecto:** Gota v0.2 — Flutter + Supabase
**Repositorio:** `github.com/arquimedesgarcia/gota` — rama `main`
**Commit auditado (HEAD):** `41d82a9 feat: implement sprint 04 water events`
**Alcance de este informe:** artefactos del Sprint 03 (`a732643`, migración `00013`, feature `lib/features/leaks/{data,domain,presentation}` del ciclo comunitario, `gota_community_database.dart`)
**Método:** auditoría estática *código vs. documentación fuente de verdad* + ejecución de las suites disponibles
**Fecha:** 2026-09-11

---

## 1. Alcance y criterios

Alcance del sprint según `docs/MVP_PLAN.md`: validación, confirmación de resolución, reglas atómicas e historial.

Reglas aplicables: REQ-040…044 (validación), REQ-050…055 (resolución), REQ-091/092/093/094 (antiabuso y auditoría), REQ-100 (privacidad), REQ-170/171/172. Contratos: `API_SPEC.md` §2 (`validate-leak`, `confirm-leak-resolution`, `get-leak-report-detail`), §4 (paginación); `DATA_MODEL.md` §5 (resolución) y §6 (RLS); `FUNCTIONAL_SPEC.md` §4/§5/§6/§10/§12; `UX_SPEC.md` §6.

## 2. Evidencia ejecutada

| Comprobación | Comando | Resultado real |
|---|---|---|
| Análisis estático | `flutter analyze` | **`No issues found!`** |
| Tests unitarios/widget | `flutter test` | **92/92 en verde**, incluidos `leak_community_repository_test.dart` (13 casos) y `leak_detail_screen_test.dart` (11 casos: contadores, umbral, creador, bloqueado, duplicado, doble tap, carga, error) |
| Migraciones | Lectura íntegra de `00013` y contraste con `00011` | Coherentes entre sí; `00013` es aditiva |
| No regresión por Sprint 04 | `grep` de `create|alter|drop|grant` en `00014` | Solo crea objetos `water_*`; **no modifica** ningún objeto de los Sprints 01–03 |
| Suites SQL/E2E | `validate_resolve_leak_test.sql` (663 líneas), `community_flow_e2e.sh`, `community_concurrency_e2e.sh` | **NO EJECUTADAS** (motor Docker no disponible: `npipe:////./pipe/dockerDesktopLinuxEngine`). Revisadas solo de forma estática. |

## 3. Resumen de hallazgos

| ID | Sev. | Tema | Ubicación |
|---|---|---|---|
| AUD-S3-01 | IMPORTANTE | El creador puede confirmar la resolución de su propia fuga: decisión documentada, pero exige validación del propietario del producto | `00013:237-307`, `MIGRATION_NOTES.md:66` |
| AUD-S3-02 | IMPORTANTE | "Fugas cerca de ti" no tiene criterio geográfico ni paginación: se degrada con el uso | `gota_community_database.dart:30-45` |
| AUD-S3-03 | IMPORTANTE | REQ-054 / `FUNCTIONAL_SPEC` §10: no existe historial de fugas resueltas ("Más" sigue siendo placeholder) | `app_shell.dart:35` |
| AUD-S3-04 | IMPORTANTE | La "identidad distinta" no está anclada al dispositivo: reinstalar/limpiar datos multiplica identidades | `00004`/`00013` (diseño) |
| AUD-S3-05 | IMPORTANTE | REQ-091 (rate limits configurables) no está ni siquiera definido en `system_config` | `00009`, `00013` |
| AUD-S3-06 | MENOR | Precedencia de errores: `REPORT_ALREADY_RESOLVED` eclipsa a `FORBIDDEN` (el creador no recibe la razón real) | `00013:153-168` |
| AUD-S3-07 | MENOR | `DUPLICATE_ACTION` del backend descarta los contadores y obliga a una segunda petición | `leak_community_repository.dart:99-102` |
| AUD-S3-08 | MENOR | Orden de la lista depende del orden alfabético de `status` | `gota_community_database.dart:41` |
| AUD-S3-09 | MENOR | Sin índice compuesto `(status, created_at desc)` para la consulta de Inicio | `00007`, `00011` |
| AUD-S3-10 | MENOR | Umbral de resolución duplicado en el cliente con respaldo `?? 3` (segunda fuente de verdad) | `leak_community.dart:79,145`, `leak_detail_screen.dart:307` |
| AUD-S3-11 | MENOR | `_run` solo captura `Exception`: un error de parseo escapa sin mensaje | `leak_detail_screen.dart:74` |
| AUD-S3-12 | MENOR | `recentReports` no traduce errores de parseo de las filas | `leak_community_repository.dart:38-51` |
| AUD-S3-13 | MENOR | El detalle no muestra fotos ni mapa (coordenadas en crudo) | `leak_detail_screen.dart:282-292` |
| AUD-S3-14 | MENOR | `audit_events.user_id` guarda `auth.uid()`, no `app_users.id` (heredado de S02) | `00013:204-208` |
| AUD-S3-15 | MENOR | Mensaje duplicado en la UI deshabilitada (etiqueta + razón con el mismo texto) | `leak_detail_screen.dart:176-207` |

## 4. Hallazgos detallados

### AUD-S3-01 — IMPORTANTE · El creador confirma su propia resolución

```sql
-- 00013:232-236 (comentario normativo de la implementación)
-- Decisión sobre la ambigüedad de REQ-051 (ver docs/MIGRATION_NOTES.md):
-- `confirm-leak-resolution` en API_SPEC.md no excluye al creador (a
-- diferencia de `validate-leak`, que sí lo hace), y REQ-050 dice
-- "cualquier usuario". Se implementa sin exclusión del creador…
```

Implementación: `confirm_leak_resolution` no compara `v_report.created_by` con `v_app_user.id` (a diferencia de `validate_leak`, que sí devuelve `FORBIDDEN` en `00013:165-168`). La decisión está declarada, justificada y **cubierta por prueba** (`OK 4i` en `validate_resolve_leak_test.sql:543-553`), lo que es un punto a favor de la trazabilidad.

**Impacto.** Con el umbral en 3, una fuga puede pasar a `RESOLVED` con **dos** terceros más el propio autor. Combinado con REQ-041 (el creador no puede validar su propia fuga como mecanismo de existencia), la asimetría es: el autor no puede avalar que su fuga existe, pero sí puede avalar que ya no existe — que es precisamente la acción con la que se cierra el ciclo y se deja de prestar atención al problema. REQ-053 dice "3 identidades distintas" sin aclarar si el creador cuenta.

**Recomendación.** No es un defecto de implementación (está documentado), pero **sí requiere una confirmación explícita del propietario del producto** antes de considerarlo cerrado, por su impacto en la integridad del indicador "resuelta". Si la respuesta es "no debe contar", basta excluirlo igual que en `validate_leak` y ajustar la prueba `4i`.

### AUD-S3-02 — IMPORTANTE · "Fugas cerca de ti" no es "cerca de ti"

```dart
// gota_community_database.dart:30-45
static const _listColumns = 'id, status, validation_count, '
    'resolution_confirmation_count, created_at, resolved_at, description, '
    'sectors(name), municipalities(name)';

final rows = await _client.from('reports').select(_listColumns)
    .order('status').order('created_at', ascending: false).limit(limit);
```

No hay filtro por municipio, sector, distancia ni estado: se traen los 20 reportes (ACTIVE y RESOLVED mezclados) más recientes de **toda** la base. `FUNCTIONAL_SPEC.md` §2 pide "fugas cercanas o recientes" (la ambigüedad permite "recientes"), pero el rótulo visible es "Fugas cerca de ti" (`home_screen.dart:82`) y no hay criterio geográfico alguno. Además, al ordenar primero por `status`, los 20 cupos se llenan con ACTIVE de todo el estado.

**Impacto.** A medida que crezca el uso (objetivo del piloto, Sprint 09), el vecino verá fugas de otros municipios y **puede dejar de ver las de su propio sector**, que es el caso de uso central. Se degrada justo cuando el producto empieza a funcionar.

**Recomendación.** Filtrar por municipio/sector (o por radio con `st_dwithin` sobre la ubicación del último reporte/dispositivo) y ordenar por `created_at`; ofrecer carga incremental (ver AUD-S3-08/09).

### AUD-S3-03 — IMPORTANTE · No existe historial de fugas resueltas

`MVP_PLAN.md` §Sprint 03 incluye **"historial"**; `REQ-054` dice "El historial de resueltas es público"; `FUNCTIONAL_SPEC.md` §10 lo ubica en "Más" ("Mis reportes; Historial de fugas resueltas; historial de eventos de agua; preferencias; información básica"). En la implementación:

```dart
// app_shell.dart:35
PlaceholderScreen(title: 'Más'),
```

No hay pantalla, ni filtro "Resueltas" en la lista, ni RPC/consulta dedicada al historial de resueltas. Las fugas resueltas solo aparecen mezcladas en la lista de Inicio (y quedan fuera de los 20 primeros en cuanto hay actividad). La única lectura parcial es `status = 'RESOLVED'` visible en la tarjeta.

**Recomendación.** Aclarar si "historial" en el alcance del Sprint 03 se refería a la persistencia del historial (sí cumplido: `report_validations`, `resolution_confirmations`, `resolved_at`, `audit_events`) o a una vista de usuario (no cumplido). Si es lo segundo, es un entregable faltante; si es lo primero, conviene precisar la redacción del `MVP_PLAN` para que el próximo cierre no arrastre la misma duda.

### AUD-S3-04 — IMPORTANTE · "Identidades distintas" sin anclaje al dispositivo

La autenticidad de "una identidad, una acción" descansa en `UNIQUE (report_id, user_id)` sobre `app_users.id`, que a su vez deriva de un usuario anónimo de Supabase Auth. La identidad persiste mientras dure la sesión; **desinstalar la app o borrar los datos crea una identidad nueva** y habilita volver a validar y a confirmar el mismo reporte.

**Impacto.** REQ-042/REQ-052/REQ-053 ("una identidad", "3 identidades **distintas**") se cumplen literalmente pero no en su intención: una sola persona puede confirmar la resolución de su propia fuga creando tres identidades. El propio `PROJECT_BRIEF.md` §4 reconoce que la identidad se usa para "evitar auto-validación" y "limitar acciones duplicadas": con identidad anónima pura, esa garantía es débil por diseño. Los rate limits del Sprint 07 (por identidad) tampoco lo cierran.

**Recomendación.** Registrar explícitamente el límite como riesgo aceptado y planificar mitigación en el Sprint 07/09: atar acciones a un identificador de dispositivo (por ejemplo el `vendor ID`/`ANDROID_ID` hasheado o un token de instalación), exigir teléfono verificado solo para *confirmar resolución*, o ponderar confirmaciones. Documentarlo en `REQUIREMENTS.md`/`MIGRATION_NOTES.md` para que no se descubra en el piloto.

### AUD-S3-05 — IMPORTANTE · REQ-091 sin materializar

`MIGRATION_NOTES.md:89` declara el rate limiting para el Sprint 07 y se apoya en que `REQ-091` lo asigna a "Security & abuse". Es correcto como decisión de secuencia, pero conviene notar que **nada** está preparado todavía: no existe una clave `rate_limits` en `system_config` (las sembradas son `duplicate_detection`, `photo_limits`, `resolution`), ni contadores por identidad/ventana, ni límite de creación de reportes o de eventos. REQ-091 dice "**deben existir** rate limits configurables para reportes, validaciones, resoluciones y eventos": hoy no existe ninguno de los cuatro.

**Recomendación.** Dejarlo como deuda explícita con el diseño ya esbozado (claves en `system_config` + comprobación en las RPC), y verificar en el Sprint 07 que cubre los cuatro tipos de acción que pide el requisito.

### AUD-S3-06 — MENOR · Precedencia de errores

```sql
-- 00013:148-168
if v_report.id is null then return … 'NOT_FOUND'; end if;
if v_report.status <> 'ACTIVE' then return … 'REPORT_ALREADY_RESOLVED'; end if;
-- ---------- 3. El creador no valida su propia fuga (REQ-041) ----------
if v_report.created_by = v_app_user.id then return … 'FORBIDDEN'; end if;
```

El creador que intente validar su propia fuga **ya resuelta** recibe `REPORT_ALREADY_RESOLVED` ("Esta fuga ya fue reportada como resuelta por la comunidad") en lugar de la razón real ("No puedes validar tu propio reporte"). La UI usa `is_creator` para deshabilitar el botón, así que el caso solo es alcanzable por API directa. Es coherente con el pitfall ya documentado (un usuario bloqueado recibe `FORBIDDEN` antes que `NOT_FOUND`), pero conviene fijar la precedencia por escrito.

### AUD-S3-07 — MENOR · `DUPLICATE_ACTION` descarta los contadores

```dart
// leak_community_repository.dart:99-102
case 'DUPLICATE_ACTION':
  throw DuplicateCommunityActionException(
    data['message'] as String? ?? duplicateFallback,
  );
```

El backend sí devuelve `status`, `validation_count`, `resolution_confirmation_count`, `resolved_at` y `threshold` en ese caso (`00013:178-188`), pero la capa de dominio los descarta y lanza una excepción con solo el mensaje. La pantalla compensa releyendo el detalle (`leak_detail_screen.dart:86-89`), de modo que funciona — a costa de una petición extra siempre y de perder la información si la relectura falla (el usuario ve el duplicado pero no los contadores actualizados).

### AUD-S3-08 — MENOR · Orden de la lista dependiente del texto del estado

`.order('status')` (ascendente) coloca ACTIVE antes que RESOLVED porque `'ACTIVE' < 'RESOLVED'` alfabéticamente. Funciona hoy, pero la intención ("ACTIVE primero") no está expresada en el código: cualquier estado nuevo que se agregue (o un cambio de nombre) altera el orden sin que nada lo detecte. Un `order by` explícito por prioridad o un `filter(status = ACTIVE)` sería robusto.

### AUD-S3-09 — MENOR · Falta el índice que sirve la consulta de Inicio

La lista ordena por `(status, created_at desc)` con `limit 20`, pero existen índices separados: `reports_status_idx (status)` y `reports_created_at_idx (created_at desc)` (`00007:46-56`). PostgreSQL no puede combinarlos para satisfacer el `ORDER BY` + `LIMIT` sin ordenar; con volumen creciente la consulta pasa a *sort* + *limit*. Un índice compuesto `(status, created_at desc)` (o parcial `where status = 'ACTIVE'`) resuelve el caso principal.

### AUD-S3-10 — MENOR · El umbral se duplica en el cliente

El backend es la autoridad (`system_config.resolution.threshold`, expuesto en cada respuesta), pero el cliente mantiene su propio respaldo `?? 3` en `LeakDetail.fromJson` (`leak_community.dart:79`), `CommunityActionResult.fromJson` (`:145`) y `_CommunityCard` (`leak_detail_screen.dart:307`). Si el umbral pasara a 5 y una respuesta llegara sin el campo, la UI mostraría "3" y una barra de progreso incorrecta. Aceptable como defensa, pero es la misma clase de duplicación de configuración que `REVIEW_CHECKLIST.md` prohíbe.

### AUD-S3-11 — MENOR · Captura de errores incompleta en la UI

`_run` usa `on Exception catch (error)` (`leak_detail_screen.dart:74`). Un `TypeError`/`StateError` derivado de un parseo inesperado (por ejemplo un `status_code` con forma distinta) es un `Error`, no una `Exception`: escaparía sin mensaje amigable, incumpliendo `UX_SPEC.md` §8 ("evitar stack traces") si llegara a la UI.

### AUD-S3-12 — MENOR · Errores de parseo sin traducir

`recentReports` traduce `SocketException`, `ClientException`, `PostgrestException` y `AuthException`, pero no un fallo de `LeakSummary.fromJson` (cast de un tipo inesperado) → error crudo en la pantalla de Inicio. Mismo patrón que otros repositorios del proyecto; se menciona por consistencia con REQ-170/UX §8.

### AUD-S3-13 — MENOR · Detalle sin fotos ni mapa

`FUNCTIONAL_SPEC.md` §4 lista "fotos" y "ubicación en mapa" en el detalle. La pantalla muestra el conteo (`photo_count`) y las coordenadas en crudo (`leak_detail_screen.dart:287-292`). Está **explícitamente documentado** como decisión (`FUNCTIONAL_SPEC.md` §4 último párrafo, `MIGRATION_NOTES.md:71`, `README.md:199`) y depende de URLs firmadas + MapLibre: no es un defecto oculto, pero conviene mantenerlo visible en el backlog para que el detalle no se considere "terminado".

### AUD-S3-14 / AUD-S3-15 — MENOR · Detalles menores

- `audit_events.user_id` guarda `auth.uid()` mientras todo el resto del modelo usa `app_users.id` (misma observación que AUD-S2-18); sin FK, sin validación.
- En el detalle, cuando el botón "Validar fuga" está deshabilitado por `alreadyValidated`, el texto `'Ya validaste este reporte'` aparece **dos veces**: como etiqueta del botón (`:176-180`) y como razón (`_disabledReason`, `:202-207`). Redundancia visual, no error funcional.

## 5. Trazabilidad requisito → implementación (Sprint 03)

| Requisito | Implementación | Estado |
|---|---|---|
| REQ-040 Usuario anónimo valida fuga ACTIVE de otro | `validate_leak` con comprobación de estado y de identidad | ✅ Cumple |
| REQ-041 El creador no valida su propio reporte | `if v_report.created_by = v_app_user.id then FORBIDDEN` | ✅ Cumple (y probado, `OK 3d`) |
| REQ-042 Una identidad valida una vez | `UNIQUE (report_id, user_id)` + `on conflict do nothing` + `DUPLICATE_ACTION` | ✅ Cumple (autoridad en BD, probado `OK 1c`/`OK 3c`) |
| REQ-043 La regla se aplica en el backend, no solo en la UI | Todo vive en RPC `security definer`; la UI solo consume `canValidate` informativo | ✅ Cumple |
| REQ-044 Validaciones con timestamp e identidad anónima | `report_validations.created_at` + `user_id`; tablas sin lectura de cliente | ✅ Cumple |
| REQ-050 Cualquier usuario puede indicar resolución | `confirm_leak_resolution` sin exclusión del creador | ⚠️ Cumple literalmente (ver AUD-S3-01) |
| REQ-051 Reglas del creador en la operación | Decisión documentada en `MIGRATION_NOTES.md:66` y probada (`OK 4i`) | ⚠️ Ambigüedad resuelta por el implementador; requiere confirmación del producto |
| REQ-052 Una confirmación por identidad | `UNIQUE (report_id, user_id)` en `resolution_confirmations` | ✅ Cumple (probado `OK 4c`) |
| REQ-053 3 identidades distintas → ACTIVE a RESOLVED atómicamente | `for update` + `INSERT` + `UPDATE` único con `status`/`resolved_at` en la misma sentencia | ✅ Cumple (probado `OK 4b/4d/4e` e invariante `OK 6`) |
| REQ-054 El historial de resueltas es público | Persistencia sí; **no hay vista de historial** | ⚠️ **Parcial** (AUD-S3-03) |
| REQ-055 Sin expiración automática | No hay cron/job ni transición temporal | ✅ Cumple |
| REQ-091 Rate limits configurables | No existe ninguno (diferido a S07) | ⚠️ **No implementado** (AUD-S3-05) |
| REQ-092 Acciones duplicadas rechazadas server-side | `DUPLICATE_ACTION` determinista y sin efectos | ✅ Cumple |
| REQ-093 Acciones relevantes en `audit_events` | `REPORT_VALIDATED`, `RESOLUTION_CONFIRMED`, `REPORT_RESOLVED` | ✅ Cumple (probado `OK 3b-5`, `4e-7`) |
| REQ-094 Permitir detección posterior de actividad anómala | Auditoría con identidad + timestamp; sin herramientas de detección (correcto: S07) | ✅ Base suficiente |
| REQ-100 Identidad del reportante no pública | `get_leak_report_detail` **no** expone `created_by` (correcto) | ❌ Incumplido por lectura directa de tablas (AUD-S2-01/02) |
| API_SPEC §2 contratos de respuesta | `status_code`, contadores, `threshold`, `resolved_at`, `already_validated`/`already_confirmed` completos | ✅ Cumple |
| API_SPEC §4 paginación en listas | Sin cursor en la lista de Inicio | ⚠️ **Parcial** (AUD-S3-02) |
| DATA_MODEL §5 resolución atómica | Bloqueo de fila + contador + estado + auditoría en una transacción | ✅ Cumple |
| DATA_MODEL §6 RLS | `report_validations`/`resolution_confirmations` con RLS sin políticas y `REVOKE ALL`; `reports` solo `select` | ✅ Cumple (probado `OK 2a`–`OK 2k`) |
| FUNCTIONAL_SPEC §6 progreso `n/3` desde el backend | `threshold` en cada respuesta; barra y texto con el valor del servidor | ✅ Cumple |
| FUNCTIONAL_SPEC §12 no anunciar éxito antes del backend | Snackbar solo tras la respuesta; mensajes condicionados a `isResolved` del backend | ✅ Cumple en el ciclo comunitario (⚠️ incumplido en el flujo de reporte, AUD-S2-06) |
| UX_SPEC §6 la acción primaria es "Validar" | `FilledButton` coral + botón secundario outline para resolución | ✅ Cumple |

## 6. Definition of Done (MVP_PLAN §Definition of Done)

| # | Elemento | Estado |
|---|---|---|
| 1 | Código | ✅ |
| 2 | Migración | ✅ (`00013`, aditiva) |
| 3 | RLS/seguridad | ✅ Muy sólido en este sprint: tablas de acciones cerradas, contadores y estado no modificables por el cliente, RPC con `search_path = ''` y `GRANT` solo a `authenticated` |
| 4 | Tests | ✅ Cobertura notable (offline + suite SQL de 663 líneas + flujo E2E + concurrencia), aunque **no ejecutadas en esta auditoría** |
| 5 | UX/error states | ✅ Carga, error con reintento, duplicado, bloqueado, resuelto, doble tap y refresco del estado real |
| 6 | Documentación | ✅ `MIGRATION_NOTES.md` §Sprint 03 documenta cada decisión, incluida la ambigüedad de REQ-051 |
| 7 | Verificación manual | ⚠️ No reproducible con datos reales (AUD-S1-02: sin sectores no hay fugas que validar) |

## 7. Aspectos verificados sin hallazgos (destacados)

- **Atomicidad real.** `select … for update` sobre la fila del reporte, `INSERT … on conflict do nothing` como autoridad, y contador + estado + `resolved_at` en **una sola** sentencia `UPDATE … RETURNING` dentro de la misma transacción. No existe ventana en la que el contador se incremente sin registro, ni dos incrementos por la misma identidad.
- **Serialización de la concurrencia.** El bloqueo de la fila hace que la cuarta identidad reciba `REPORT_ALREADY_RESOLVED` sin alterar contadores ni `resolved_at`. `community_concurrency_e2e.sh` verifica el multiset exacto (`CONFIRMED, CONFIRMED, RESOLVED, REPORT_ALREADY_RESOLVED`) y la equivalencia contador ≡ filas persistidas; el diseño del script es determinista (no depende de la intercalación real).
- **Umbral no hard-codeado.** `system_config.resolution = {"threshold": 3}` con respaldo en `resolution_threshold()` (`greatest(…, 1)`), probado con umbral 2 (`OK 4j`). `resolution_threshold()` es `security definer` con `EXECUTE` revocado a `public, anon, authenticated`: no es invocable desde el cliente.
- **No existe `RESOLVED → ACTIVE`.** Ninguna operación revierte el estado; una fuga resuelta responde `REPORT_ALREADY_RESOLVED` y el `CHECK reports_status_consistency` garantiza que `RESOLVED` siempre tiene `resolved_at` y `ACTIVE` nunca lo tiene.
- **Privacidad de las tablas de acciones.** `report_validations` y `resolution_confirmations` tienen RLS **sin políticas** y `REVOKE ALL`: el cliente no puede leerlas ni escribirlas, ni siquiera saber quién validó qué. El estado propio llega por `get_leak_report_detail` — decisión de privacidad bien ejecutada.
- **`get_leak_report_detail` no expone `created_by`**: solo `is_creator` booleano. Es la forma correcta; contrasta con la lectura directa de tablas señalada en AUD-S2-01/02.
- **Inmutabilidad de los campos críticos.** Verificado por prueba: `validation_count`, `resolution_confirmation_count`, `status` y `resolved_at` no son modificables por el cliente (bloqueado por GRANT de columna y por políticas de UPDATE inexistentes).
- **Inconsistencia de conteo imposible por diseño:** si el `UPDATE` del contador no afectara filas, la función lanza excepción (`raise exception 'validation_count no pudo actualizarse…'`) en lugar de devolver un éxito falso.
- **Coherencia de contadores verificada globalmente** en el script SQL (invariante 6 sobre los cuatro reportes de prueba: contador ≡ filas, estado ≡ `resolved_at`).
- **`is_blocked` respetado** en ambas RPC antes de cualquier efecto, con mensaje específico ("Tu acceso está bloqueado."), y expuesto en el detalle para que la UI deshabilite las acciones sin adivinar.
- **`DUPLICATE_ACTION` es un resultado de dominio, no un error genérico** (documentado en la migración, en el repositorio y en los tests), y no altera contadores ni estado.
- **La UI no anuncia nada que el backend no confirme:** el mensaje de éxito se construye con `validationCount`/`isResolved` de la respuesta, el umbral viene del servidor y la pantalla se relee tras cada acción.
- **Sin regresión del Sprint 04 sobre los Sprints 01–03:** la migración `00014` no modifica ningún objeto previo.

## 8. Veredicto Sprint 03

**El mejor sprint del proyecto en términos de ingeniería de datos; sus carencias son de alcance, no de ejecución.**

- La parte difícil —atomicidad, concurrencia, autoridad de la base de datos, privacidad de las tablas de acciones, no anunciar éxito antes de confirmar— está resuelta y documentada con nivel de detalle poco habitual. El `MIGRATION_NOTES.md` §Sprint 03 es, además, un registro honesto de las decisiones y sus ambigüedades.
- **No hay defectos de código que rompan un requisito** en las reglas de validación/resolución. Los hallazgos IMPORTANTES son de alcance o de decisión de producto: AUD-S3-01 (creador confirma su propia resolución — requiere confirmación explícita), AUD-S3-02 (la lista de Inicio no es geográfica y se degradará), AUD-S3-03 (historial de resueltas no entregado), AUD-S3-04 (identidades multiplicables por diseño) y AUD-S3-05 (REQ-091 sin materializar).
- **Riesgo que conviene no aplazar:** AUD-S3-02 y AUD-S3-04 se manifiestan precisamente en el piloto (Sprint 09): la lista dejando de mostrar lo propio, y validaciones/resoluciones infladas por reinstalación. Ambos son baratos de mitigar ahora y caros de explicar después.
- Recomendación de orden: confirmar AUD-S3-01 con el producto → corregir AUD-S3-02 (filtro geográfico) → decidir AUD-S3-03 → registrar AUD-S3-04/05 como deuda con plan → el resto es pulido.
