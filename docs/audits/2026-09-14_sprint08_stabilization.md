# Auditoría Sprint 08 — Stabilization (QA + Security Verification)

- **Fecha:** 2026-09-14 (UTC-4)
- **Commit auditado:** `1491952` (chore(sprint-08): stabilization — regression tests, release readiness, error UX, E2E hygiene, docs)
- **Modo:** SOLO LECTURA sobre el repositorio de producción. Las pruebas de abuso se ejecutan
  contra la instancia local (Docker `gota`); no se modificó código, migraciones ni tests de
  producción para obtener un PASS. Los scripts de ataque/probe son temporales y viven fuera
  del repo (`%LOCALAPPDATA%\Temp\gota_qa_s08`).
- **Instancia evaluada:** Supabase self-hosted Docker (stack `gota`), `localhost:54322`
  (PostgreSQL 17), migraciones **26/26 aplicadas**, sin pendientes.
- **Rol:** Senior QA Engineer + Security Tester + Database/API Test Engineer, con mandato
  explícito de **no confiar en el agente codificador** e intentar romper la implementación.
- **Veredicto:** 🔴 **BLOCKED** (2 hallazgos IMPORTANTES, 6 MENORES, cobertura de UX en
  dispositivo y de instalación/arranque del APK **NO EJECUTADA**).

## Resumen ejecutivo

El núcleo de Sprint 08 —rate limiting, RLS/privilegios, concurrencia y contratos de error—
**pasa** con evidencia reproducible y leída de vuelta desde PostgreSQL y desde HTTP
(PostgREST con clave anon pública y con JWT `authenticated` real firmado localmente).

Cifras de la verificación:

- Suites SQL del repo (`ON_ERROR_STOP=1`): **8/8 OK** (aserciones 1a→14d).
- E2E reales: **5/5 scripts, 64 PASS / 0 FAIL** (create_leak_report 14, community_flow 27,
  storage_rls 8, community_concurrency 10, rate_limit_concurrency 5).
- Auditoría independiente propia (`s08_attacks.py`, no usa las suites del repo): **99
  aserciones → 90 PASS / 9 FAIL**; los 9 se desmontaron uno a uno: **8 falsos positivos o
  fallos de instrumento del propio harness** y **1 grupo (S13) invalidado** por llamadas mías
  con firmas equivocadas, re-verificado con firmas correctas (**5/5 `UNAUTHORIZED`
  controlado**).
- Flutter estático: `flutter analyze` → `No issues found! (ran in 2.4s)`, `ANALYZE_EXIT=0`;
  `flutter test` → `+123: All tests passed!`, `TEST_EXIT=0`.
- Android release: el APK **se construye y se verifica estáticamente**, pero **no se instaló
  ni se ejecutó** (sin dispositivo ni emulador en el entorno) y en la ruta del repo
  (`D:\Proyectos\Gota\v0.2`) el build **falla de forma reproducible** (ver AUD-S08-08).

El BLOCKED no proviene del rate limiting/RLS/concurrencia de Sprint 08, sino de
exposiciones/higiene detectadas en la BD auditada y de la verificación en ejecución que el
entorno no permitió realizar.

## Evidencia (pruebas ejecutadas)

Rate limiting (5 operaciones protegidas; límites reales de `system_config.rate_limits` y de
`get_rate_limit`): create leak = 3, validate leak = 20, confirm resolution = 10,
register water event = 5, validate water event = 20.

- Límite exacto y siguiente llamada: `1..3 CREATED → 4ª RATE_LIMIT_EXCEEDED`;
  `20 VALIDATED (+DUPLICATE_ACTION) → 21ª RL`; `10 confirmaciones → 11ª RL`;
  `5 eventos → 6ª RL`; `20 validaciones de agua → 21ª RL`.
- Aislamiento entre usuarios: `A=5, B=0`; la llamada inválida de B no consume su bucket; el
  bucket de B se crea de forma independiente sin tocar el de A.
- Rechazo sin efectos de negocio: tras los rechazos, `reports=3, audit=3` y en
  validate/confirm/water `filas=1, contador=1, auditoría=1` pese a 19–20 `DUPLICATE_ACTION`.
  El contador del bucket **sí** registra el intento rechazado (`count=4/6/21`): diseño
  fixed-window confirmado también por el e2e de concurrencia
  (`contador del bucket == M (6) aunque 3 fueron rechazadas`).
- Bypass: `check_rate_limit`/`check_rate_limit_inline` revocados (42501) para A/B/C y anon;
  `get_rate_limit` legible por `authenticated` y **no consume** presupuesto (filas 0→0);
  `rate_limit_tracking` inaccesible por REST (401) y por SQL (42501) → el usuario no puede
  resetear su propio bucket.
- Ventana/reset: ventana vencida (`count=99`, −2h) no bloquea; ventana activa con `count=3`
  rechaza y devuelve `reset_at=2026-09-14T18:00:00+00:00`.

Concurrencia (no se acepta «funciona normalmente» como evidencia):

- Rate limiting: **8 solicitudes simultáneas** con límite 3 y contador previo 2 →
  `CREATED=1, RL=7, contador=10, reports=3`; e2e: `filas <= 3` y contador == M → el límite
  **no se supera por concurrencia**.
- Leaks: **6 confirmaciones simultáneas** → `CONFIRMED=2, RESOLVED=1, 3× REPORT_ALREADY_RESOLVED`,
  `resolution_confirmation_count=3`, `status=RESOLVED`, `resolved_at` íntegro.
- Leaks: **6 validaciones simultáneas** → 6/6, `validation_count=6`, filas=6, sin corrupción.
- Idempotencia posterior: validate/confirm sobre reporte ya resuelto → `REPORT_ALREADY_RESOLVED`
  sin alterar `resolved_at`.

Contratos de error observados y controlados (§6): `VALIDATION_ERROR`, `DUPLICATE_ACTION`,
`FORBIDDEN`, `UNAUTHORIZED`, `NOT_FOUND`, `REPORT_ALREADY_RESOLVED`, `INVALID_LOCATION`,
`INVALID_SECTOR`, `STORAGE_ERROR` y rate limit distinguible (`status_code` + `reset_at`).
No se observó SQLSTATE escapando al cliente en los 19 casos de la matriz (S14), incluido el
caso de `authenticated` **sin fila en `app_users`** (5/5 `UNAUTHORIZED` controlado; trigger
`on_auth_user_created`/`handle_new_user` mantiene `auth.users` 82/82 con 0 huérfanos).

Suites y estático:

- `supabase/tests/{rls,create_leak_report,validate_resolve_leak,water_events,notifications,map_reports,storage_report_photos,rate_limiting}_test.sql` → OK con `ON_ERROR_STOP=1`.
- `supabase/tests/{create_leak_report,community_flow,storage_rls,community_concurrency,rate_limit_concurrency}_e2e.sh` → exit 0, 64 PASS / 0 FAIL.
- `flutter analyze` y `flutter test` → OK (0 issues, 123/123).
- Migraciones: 26 en disco = 26 aplicadas (`supabase_migrations.schema_migrations`).

Comandos relevantes:

```bash
docker exec supabase_db_gota psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f supabase/tests/<suite>.sql
bash supabase/tests/<e2e>.sh
python <harness>/s08_attacks.py            # 99 aserciones independientes (SET ROLE + claim JWT)
flutter analyze && flutter test
flutter build apk --release --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=… --dart-define=SUPABASE_ENV=…
apksigner verify --print-certs -v app-release.apk && aapt2 dump badging app-release.apk
```

## Hallazgos

### AUD-S08-01 — IMPORTANTE — Identidad del autor expuesta en `water_events`
- **Esperado:** la identidad del autor no es legible por el cliente; así está resuelto en
  `reports` (grants **por columna**, `created_by` no seleccionable) según AUD-S2-01/02.
- **Observado:** `GET /rest/v1/water_events?select=*` con la **clave anon pública** devuelve
  la fila completa **incluyendo `created_by`** (uuid de `app_users`) de todos los eventos.
- **Evidencia:** `col_probe.txt` (`water_events: … anon=r/postgres, authenticated=r/postgres`
  frente a `reports`, que solo tiene grants por columna), `rest_final.txt`
  (`[200] water_events: SELECT … created_by`), `http_auth.txt`.
- **Ubicación:** grants de tabla de `public.water_events` (migraciones de water events).
- **Impacto:** un cliente anónimo enumera eventos de agua y **correlaciona actividad por
  identidad pseudónima estable** (perfilado por usuario); rompe la simetría de privacidad ya
  aplicada en `reports`.

### AUD-S08-02 — IMPORTANTE — `public.temp` existe con DML abierto a `anon` (RLS desactivada)
- **Esperado:** ninguna tabla escribible por `anon`; sin objetos de prueba en la BD.
- **Observado:** con la clave anon pública, `POST /rest/v1/temp → 201`, `PATCH → 200`,
  `DELETE → 200`; ACL `anon=arwdDxtm/postgres`; `RLS=False`; 1 fila residual
  (`11111111-1111-1111-1111-111111111111`). Bajo `SET ROLE anon` también es
  SELECT/INSERT/UPDATE/DELETE/TRUNCATE (probado con rollback).
- **Evidencia:** `rest_final.txt` (sección B), `acl_final.txt`, `policies.txt`, `role_test.txt`.
- **Ubicación:** **no existe en las migraciones del repo** (grep del repo vacío,
  `git log -S` sin resultados, `seed.sql` sin referencias) → residuo del volumen Docker local.
- **Impacto:** superficie de escritura arbitraria con la clave pública. **Si el objeto existiera
  también en el Supabase desplegado, se eleva a BLOQUEANTE.** Remediación: `DROP TABLE public.temp;`.

### AUD-S08-03 — MENOR — Funciones de prueba con EXECUTE para `anon`/`authenticated`
- `test_func()`, `test_simple_update()`, `test_get_rate_limit()` invocables vía REST por `anon`
  (`rest_final.txt` sección C, `acl_final.txt`). Inofensivas (`SELECT 'test'`), pero son
  residuo de entorno. Remediación: `DROP FUNCTION`.

### AUD-S08-04 — MENOR — `system_config` con RLS desactivada (policy definida pero inactiva)
- `rls=False`, `pol=1`, `anon=r`: `anon` y `authenticated` leen `rate_limits`, `photo_limits`,
  `duplicate_detection`, `resolution`. Los valores no son secretos (y `get_rate_limit` ya los
  expone), pero queda como superficie pública para cualquier clave futura.
- **Evidencia:** `acl_final.txt` §4, `db_estado.txt`, `policies.txt`.

### AUD-S08-05 — MENOR — Los 401/403 de PostgREST filtran nombres de objetos internos
- Ej.: `{"hint":"Grant the required privileges to the current role with: GRANT SELECT ON public.audit_events TO authenticated;"}`.
  Sin datos privados, pero revela esquema interno (comportamiento por defecto de PostgREST).

### AUD-S08-06 — MENOR — Los E2E no limpian sus usuarios anónimos ni filas asociadas
- Residuos por corrida: `auth.users`/`app_users` +1..2, `rate_limit_tracking` +1,
  `audit_events` +1..6. Las tablas de negocio (`reports`, `report_validations`,
  `water_events`, `report_photos`, `storage.objects`) quedan **sin residuos**.
- Los 80 `auth.users` anónimos son iteraciones E2E, **no datos funcionales abandonados**
  (0 `app_users` huérfanos). **Evidencia:** `e2e_hygiene2.txt`.

### AUD-S08-07 — MENOR — El cleanup ante interrupción no quedó probado
- Los `SIGTERM` se enviaron a los 8/12/15/25 s, pero los scripts ya habían terminado
  (`Todas las pruebas … pasaron`), por lo que el escenario «etapa intermedia fallida» **no se
  ejecutó realmente**. Es cobertura incompleta, no un fallo del producto.

### AUD-S08-08 — MENOR — `flutter build apk` no reproducible en `D:\Proyectos\Gota\v0.2`
- `compileReleaseKotlin`/`compileDebugKotlin` fallan con
  `Could not close incremental caches in D:\Proyectos\Gota\v0.2\build\<plugin>\kotlin\...\*.tab`
  (image_picker_android, shared_preferences_android, flutter_image_compress_common,
  firebase_core, maplibre_gl) en **debug y release**, con y sin daemon, con
  `kotlin.incremental=false` e `in-process`.
- El **mismo árbol** compila sin errores desde `%LOCALAPPDATA%\Temp\gota_relcheck`
  (`√ Built build\app\outputs\flutter-apk\app-release.apk (85.0MB)`, 190.5 s).
- **Evidencia:** `build_release.log`/`build_release3.log:790`/`build_release4.log:1337`/
  `build_debug.log:1329` (`BUILD_EXIT=1`/`DEBUG_BUILD_EXIT=1`) y `build_relcheck.log` (OK).
- **Impacto:** condición del entorno/ruta (bloqueo de ficheros/AV) y no del código, pero la
  afirmación de `docs/SETUP.md` («verificado en Sprint 08: el comando compila y produce un APK
  válido desde un clon limpio») **no es reproducible en esta máquina para esa ruta**.

### Cobertura NO EJECUTADA (exigida por §7/§9)
- UX en ejecución: arranque, navegación principal, mapa, listado, detalle de fuga, reportar,
  validar, resolver, agua, notificaciones, loading, vacíos, errores, retry, doble tap, rate
  limit, pérdida de red, sesión anónima.
- Instalación y arranque del APK release, permisos en runtime y **FCM real**.
- **Motivo:** no hay dispositivo físico, ni emulador/AVD, ni system-images, y `adb devices`
  está vacío; la raíz del repo no tiene `windows/`, así que no hay target de escritorio
  sustituto. Solo se verificó de forma **estática** el mapeo códigos→mensajes en español
  (`lib/features/leaks/domain/leak_errors.dart`, `lib/features/water/domain/water_errors.dart`)
  y el uso de `reset_at` en los repositorios.

## Transparencia (falsos positivos y errores del propio harness)

1. Los 6 `FAIL` de S13 en `s08_attacks.log` son **errores de firma de mi script**
   (42883/42601/42703 = función/columna/sintaxis inexistente en **mi** llamada), invalidados
   por la re-ejecución con firmas correctas (`noappuser2.txt` → 5/5 `UNAUTHORIZED`).
2. S9 `audit_events` bajo `authenticated` → 42501 **es el comportamiento esperado** (denegado);
   mi aserción estaba mal escrita.
3. S10 «+0 escaneos» es una **métrica de `pg_stat` mal instrumentada** (no mide lo que afirma).
4. S15 `created_at` / `is_creator` no son identidad: **falso positivo** de mi heurística
   (el listado real de campos no contiene id/nombre/email).
5. La sección «Visibilidad efectiva» de `policies.txt` (que reportaba «83 filas visibles para
   anon» en `app_users`) es un **error de instrumento**: REST devuelve 401 y `role_test.txt`
   da 42501. Evidencia válida: HTTP + `role_test`.
6. Residuo propio del harness: `audit_events` 248→262 (+14 por las acciones de ataque). Todo
   lo demás quedó idéntico a la línea base (`preclean.py` restaura los artefactos).

## Regresiones

- **Ninguna regresión funcional observada** en las áreas auditadas: listado/mapa/detalle siguen
  legibles para clientes (`get_map_reports` 200 con anon), `reports.created_by` sigue **no**
  seleccionable (aserciones 9b/9c), `report_photos` sin grants de cliente (9d/9e), Storage
  bloquea acceso cruzado (A no borra ni lee objetos de B), confirmaciones/validaciones
  conservan `DUPLICATE_ACTION`/`REPORT_ALREADY_RESOLVED` y contadores consistentes.
- El único cambio de comportamiento observado (el bucket cuenta también los intentos
  rechazados) es **diseño fixed-window** confirmado por el e2e de concurrencia; no es regresión.
- AUD-S08-01 no se clasifica como regresión: no hay línea base previa que demuestre cuándo se
  introdujo el grant de tabla en `water_events`; se reporta como hallazgo.

## Seguridad (resultado específico)

Pasan: helpers de rate limiting no invocables por clientes (42501); `rate_limit_tracking` sin
grants y sin políticas → no reseteable; `audit_events` sin lectura pública (`USING false`) e
inserción forjada denegada; `app_users` con RLS own-row (`auth_user_id = auth.uid()`);
`reports` con grants **por columna** (`id, municipality_id, sector_id, description, status,
validation_count, resolution_confirmation_count, created_at, updated_at, resolved_at`) y
`select=*`/`created_by`/`latitude` denegados; `report_photos` sin grants; Storage con acceso
cruzado denegado (404/400) y bucket no listable por anon; `notifications`/`notification_tokens`/
`notification_preferences` solo fila propia (tokens ajenos → `[]`); RPC de negocio denegadas a
`anon` (`permission denied for function`); `authenticated` sin perfil → `UNAUTHORIZED`
controlado sin fuga de SQLSTATE; `service_role` ausente en `lib/`, `android/` y `pubspec.yaml`.

A corregir: AUD-S08-01 (identidad en `water_events`), AUD-S08-02/03 (residuos con DML/EXECUTE
a `anon`), AUD-S08-04 (`system_config` sin RLS), AUD-S08-05 (hints de esquema en 401/403).

## Release Android

- `flutter build apk --release` con `JAVA_HOME=D:\TMP\gota-jdk\jdk-21.0.12.1+1`:
  **falla** en `D:\Proyectos\Gota\v0.2` (4 intentos release + 1 debug; AUD-S08-08).
- **Éxito** desde copia del mismo árbol en `%LOCALAPPDATA%\Temp\gota_relcheck`:
  `√ Built build\app\outputs\flutter-apk\app-release.apk (85.0MB)`.
- Artefacto: 89 177 848 bytes, sha1 `bb5f00a9…af8a`; 3 ABIs (`arm64-v8a`, `armeabi-v7a`,
  `x86_64`); firma **APK Signature Scheme v2 = true** (v1/v3 = false), 1 firmante
  `CN=Android Debug` (no existe `android/key.properties`, como documenta SETUP.md);
  **no debuggable**; `com.gota.gota` versionCode 1 / versionName 1.0.0; minSdk 24,
  targetSdk 36; permisos coherentes (ubicación FINE/COARSE, INTERNET, POST_NOTIFICATIONS,
  WAKE_LOCK, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, `com.google.android.c2dm.permission.RECEIVE`);
  **sin** `network_security_config` (cleartext bloqueado, AUD-S2-17).
- Límites del artefacto: se compiló con la anon key como **marcador** (`[REDACTED]`, 1
  ocurrencia por ABI) y **sin `google-services.json`** → `google_app_id` ausente → **FCM no
  operativo** en este APK. Valida **compilación/empaquetado**, no conectividad ni runtime.
  `service_role` = 0 ocurrencias y **ningún JWT embebido** en ninguna ABI.
- **Instalación, arranque, navegación, mapa, flujo principal, permisos y FCM: NO EJECUTADO.**

## Acción necesaria

**BLOCKED.** Antes del cierre de Sprint 08:

1. `water_events`: quitar el grant de tabla a `anon`/`authenticated` y aplicar grants **por
   columna** como en `reports` (dejando `created_by` no seleccionable); si el cliente necesita
   autoría, exponerla solo vía RPC con `is_creator`. (AUD-S08-01)
2. `DROP TABLE public.temp;` y `DROP FUNCTION public.test_func(), public.test_simple_update(),
   public.test_get_rate_limit();`; verificar que no existan en el Supabase desplegado (si
   existen allí, es **BLOQUEANTE**). (AUD-S08-02/03)
3. Activar RLS en `system_config` o retirar la policy muerta y el grant a `anon`
   (`get_rate_limit` ya cubre el caso de uso). (AUD-S08-04)
4. Ejecutar la verificación en dispositivo/emulador del APK release con defines reales y
   `google-services.json`: cubre la UX completa (§7) e instalación/arranque/FCM (§9).
5. Excluir `build` de `D:\Proyectos\Gota\v0.2` del antivirus o documentar el workaround, y
   ajustar la afirmación de `docs/SETUP.md` al entorno real. (AUD-S08-08)
6. Hacer que los E2E limpien sus usuarios anónimos y filas propias, y probar el cleanup con
   interrupción **efectiva**. (AUD-S08-06/07)

## Veredicto

🔴 **BLOCKED.** El rate limiting (5 operaciones, límite exacto, aislamiento por usuario, sin
bypass ni llamada directa, sin efectos de negocio en el rechazo, ventana/reset verificados), la
concurrencia (8 simultáneas contra límite 3; 6 confirmaciones y 6 validaciones concurrentes con
`resolved_at` íntegro y sin doble resolución), las RLS/privilegios, los contratos de error y el
estático de Flutter **pasan** con evidencia leída de vuelta desde PostgreSQL y HTTP. No se
declara READY porque: (a) hay una exposición de identidad en `water_events` con la clave anon
pública y objetos residuales con DML abierto a `anon` en la BD auditada; (b) la verificación en
ejecución de la app y la instalación/arranque del APK **no se pudieron ejecutar** en este
entorno; y (c) el build release no es reproducible en la ruta del repositorio en esta máquina.
