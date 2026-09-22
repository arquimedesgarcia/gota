# Gota v0.2

Aplicación comunitaria móvil (Flutter + Supabase) para reportar y validar fugas de agua y registrar eventos de suministro en Isla de Margarita, Venezuela.

**Estado: Sprint 08 — Stabilization en curso.** Sprint 01 Foundation, Sprint 02 Leak Reporting, Sprint 03 Validation & Resolution, Sprint 04 Water Events, Sprint 05 Map, Sprint 06 Notifications y Sprint 07 Security & Abuse Hardening están implementados y migrados. La auditoría del Sprint 07 encontró DEF-01 (helpers de rate limit expuestos a `authenticated`); la corrección (`07557a4`), su revalidación y la regresión asociada a `create_leak_report` (`2ac8377`, `0b27fcf`) están aplicadas en `main`. El estado READY del Sprint 08 lo determina el tester independiente. Sobre esta base, el Home incorpora la tarjeta **"Actividad reciente"** (último evento comunitario global sobre fallas: reportada / validada = cruce del umbral / resuelta) con su RPC `get_latest_community_activity` (migración `20260922000029`).

## Documentación (fuente de verdad)

Leer en este orden:

1. `docs/PROJECT_BRIEF.md`
2. `docs/REQUIREMENTS.md`
3. `docs/FUNCTIONAL_SPEC.md`
4. `docs/UX_SPEC.md`
5. `docs/DESIGN_SYSTEM.md`
6. `docs/ARCHITECTURE.md`
7. `docs/DATA_MODEL.md`
8. `docs/API_SPEC.md`
9. `docs/MVP_PLAN.md`
10. `docs/REVIEW_CHECKLIST.md`
11. `docs/SETUP.md`

`docs/MIGRATION_NOTES.md` explica qué decisiones antiguas fueron reemplazadas. `prototipo/index.html` es referencia visual, no fuente de reglas.

## Qué incluye Sprint 01

- Proyecto Flutter (Android prioritario, iOS compatible) con Material 3 y tema de Gota.
- Navegación inferior de cinco posiciones: **Inicio · Mapa · Reportar (acción central) · Agua · Más** (según `UX_SPEC.md`).
- Pantalla Inicio inicial y pantallas "próximamente" para destinos no implementados.
- Conexión Supabase con autenticación anónima y persistencia de sesión.
- Creación idempotente del perfil en `app_users` para cada usuario anónimo.
- Repositorios de municipios y sectores con Riverpod (la UI nunca llama a Supabase directamente).
- Migraciones versionadas: PostGIS, `municipalities`, `sectors`, `app_users`, RLS y catálogo piloto (Maneiro/Arismendi/Mariño, 96 sectores).

## Requisitos

- **Flutter 3.47.3** (Dart 3.13.3) — versión usada en este sprint. Cualquier Flutter estable reciente compatible con `pubspec.yaml` sirve.
- Android Studio + Android SDK (para ejecutar en Android).
- Git.
- **Supabase CLI** (solo para aplicar migraciones y levantar entorno local). Ver <https://supabase.com/docs/guides/cli>.
- Una cuenta/proyecto Supabase (development).

## Configuración local

1. Clonar el repositorio.
2. `flutter pub get`
3. Crear un proyecto Supabase de desarrollo y activar **Anonymous Sign-ins**
   (Authentication → Providers → Anonymous → Enable).
4. Aplicar las migraciones (ver siguiente sección).
5. Ejecutar la app con las variables de entorno (ver siguiente sección).

### Variables de entorno

La app lee su configuración exclusivamente desde `--dart-define` (no hay secretos en el repositorio):

| Variable | Obligatoria | Descripción |
|---|---|---|
| `SUPABASE_URL` | Sí | URL pública del proyecto Supabase (`https://<proyecto>.supabase.co`). |
| `SUPABASE_ANON_KEY` | Sí | Clave pública anónima (Settings → API → `anon public`). |
| `SUPABASE_ENV` | No | `development` (por defecto) o `production`. Metadato de despliegue: no altera reglas de negocio ni runtime (AUD-S1-03). |

Nunca usar la `service_role` key en el cliente. Si faltan las variables obligatorias, la app arranca y muestra una pantalla de configuración ausente en lugar de fallar.

## Ejecutar la app

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<proyecto>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public> \
  --dart-define=SUPABASE_ENV=development
```

Sin credenciales también se puede lanzar `flutter run`; la app mostrará el aviso de configuración ausente.

## Build Android release

`versionCode`/`versionName` salen de `version` en `pubspec.yaml` (sobrescribibles con `--build-number`/`--build-name`). El build de release firma con `android/key.properties` cuando existe y, si no, con la clave de debug (reproducible sin secretos); R8/minify está activado vía `android/app/proguard-rules.pro`.

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<proyecto>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public> \
  --dart-define=SUPABASE_ENV=production
```

Para un release con **push notifications**, colocar antes el `google-services.json` de Firebase en `android/app/` (fuera de Git; ignorado por `.gitignore`). Sin ese archivo el APK compila y funciona sin FCM. Para distribución real generar un upload keystore y crear `android/key.properties` (`storeFile`, `keyAlias`, `storePassword`, `keyPassword`) — ambos fuera de Git. Los `--dart-define` se incrustan en el binario: usar siempre credenciales públicas de cliente, nunca `service_role`. Verificado en Sprint 08: `flutter build apk --release` compila y produce APK válido (R8 aplicado).

## Tests y análisis estático

```bash
flutter analyze
flutter test
```

Los tests son 100 % offline (fakes/mocks de las abstracciones de red): config, auth anónima, persistencia idempotente de `app_users`, repositorio de municipios (Maneiro y Arismendi), el widget de la app, el flujo **Reportar fuga** (Sprint 02), el ciclo comunitario de Sprint 03 (repositorio de validación/resolución y pantalla de detalle: contadores, progreso, duplicado, bloqueado, resuelto, error y doble tap), mapa (Sprint 05), notificaciones (Sprint 06) y los mapeos de errores conocidos del backend, incluido `RATE_LIMIT_EXCEEDED` (Sprint 08).

Cómo se ejecutan las suites SQL/E2E y qué cubre cada una: ver [Pruebas SQL y de integración](#pruebas-sql-y-de-integración).

## Migraciones y seed

Las migraciones versionadas viven en `supabase/migrations/` y son la fuente reproducible del esquema (no hacer cambios manuales en la base).

```bash
# vincular el proyecto local con el proyecto remoto (una sola vez)
supabase link --project-ref <project-ref>

# aplicar migraciones pendientes al proyecto vinculado
supabase db push

# o levantar una base local y aplicar migraciones + seed
supabase start
supabase db reset
```

Contenido de las migraciones:

1. `...0001_extensions` — habilita PostGIS (extensión verificada en la migración).
2. `...0002_municipalities` — tabla `municipalities` + trigger `updated_at`.
3. `...0003_sectors` — tabla `sectors` (único `(municipality_id, name)`).
4. `...0004_app_users` — tabla `app_users`, trigger de aprovisionamiento desde `auth.users` y función idempotente `ensure_app_user()` (llamada por la app vía RPC al iniciar).
5. `...0005_rls` — RLS: lectura pública de municipios/sectores activos; `app_users` solo accesible por su propietario.
6. `...0006_seed_municipalities` — seed: **Maneiro** y **Arismendi** (Nueva Esparta, Venezuela).
   `...00028_seed_sectores_piloto` — catálogo piloto: sectores de Maneiro (27), Arismendi (27) y Mariño (42).

### Sprint 02 — Leak Reporting

7. `...0007_reports` — tabla `reports` (ACTIVE/RESOLVED, PostGIS, GPS/MANUAL) + índices GIST y de búsqueda.
8. `...0008_report_photos` — tabla `report_photos` (máx. 3 fotos por reporte con advisory lock, orden único, FKs).
9. `...0009_system_config_audit` — `system_config` (duplicados 50 m/48 h y límites de foto configurables) + `audit_events`.
10. `...0010_create_leak_report` — RPC server-side `create_leak_report()`: autentica; valida municipio, sector, ubicación y **fotografías contra el binario real en Storage** (pertenencia, MIME y tamaño según `system_config.photo_limits`); busca duplicados (≤50 m/≤48 h sobre reportes ACTIVE) y crea ACTIVE, o devuelve `POSSIBLE_DUPLICATE` con distancia. Solo con `p_ignore_duplicate = true` (confirmación "es otra fuga", REQ-025) crea el reporte pese al candidato.
11. `...0011_rls_reports` — RLS de reports/report_photos/audit_events/system_config. Escrituras de clientes bloqueadas; toda creación pasa por la RPC.
12. `...0012_storage_report_photos` — bucket **privado** `report-photos` con políticas por carpeta de usuario.

### Storage (fotos)

- Bucket privado `report-photos`; **nunca** se usa `service_role` en la app (solo la clave pública y la sesión anónima del usuario).
- Estructura de rutas: `report_photos/{auth_user_id}/{upload_key}/{photo_id}.jpg`.
- Un usuario solo puede **subir, leer y borrar dentro de su propia carpeta**: no ve ni modifica fotos de otros usuarios.
- Sprint 02 no publica binarios (no hay detalle/mapa todavía); si hiciera falta, se resolverá server-side con URLs firmadas.
- `_cleanupUploaded()` borra por la API de Storage los temporales cuando la RPC falla, cuando se detecta `POSSIBLE_DUPLICATE` o cuando el backend rechaza el reporte; si el borrado falla, el error se muestra (nunca se deja basura en silencio).

App: flujo **Reportar fuga** (`lib/features/leaks/`) con 5 etapas (Ubicación GPS/manual → Fotos 1–3 con compresión → Datos → Revisar → Enviar), detección de duplicados con acciones "usar existente" o "es otra fuga", validación de fotos en cliente **y** servidor, y limpieza de binarios huérfanos.

### Sprint 03 — Validation & Resolution

13. `...0013_validation_resolution` — tablas `report_validations` y `resolution_confirmations` (con `UNIQUE (report_id, user_id)` como autoridad contra duplicados, FKs e índices, RLS sin acceso de cliente), `system_config.resolution` (umbral 3) y las RPC `validate_leak()`, `confirm_leak_resolution()` y `get_leak_report_detail()`.

Reglas implementadas (server-side, en la RPC):

- **Validar:** solo identidades anónimas no bloqueadas; nunca el creador del reporte; una validación por identidad y reporte.
- **Confirmar resolución:** una confirmación por identidad y reporte; con **3 identidades distintas** el reporte pasa a `RESOLVED` y se guarda `resolved_at`.
- **Duplicados:** la segunda acción devuelve `DUPLICATE_ACTION` sin alterar contadores ni estado (la UI muestra "Ya validaste este reporte").
- **Atomicidad:** cada operación bloquea la fila del reporte (`for update`) e inserta la acción + incrementa el contador (+ `status`/`resolved_at` cuando se alcanza el umbral) en una única transacción. Probado con sesiones concurrentes reales.
- **Estados:** solo `ACTIVE`/`RESOLVED`; no existe `RESOLVED → ACTIVE` y una fuga resuelta responde `REPORT_ALREADY_RESOLVED`.
- **Campos críticos:** el cliente no puede modificar `validation_count`, `resolution_confirmation_count`, `status` ni `resolved_at` (solo `select` sobre `reports`, RPC para escribir).

App: lista **Fugas cerca de ti** en Inicio (`lib/features/leaks/presentation/recent_leaks_list.dart`) y pantalla de detalle (`leak_detail_screen.dart`) con contador de validaciones, progreso `n de 3`, acciones **Validar fuga** y **Sí, fue resuelta**, estados de carga/error/duplicado/bloqueado y refresco del estado real del backend.

### Sprint 04 — Water Events

14. `...0014_water_events` — tablas `water_events` y `water_event_validations` (acceso cliente solo lectura de eventos; validaciones solo vía RPC) y las RPC `register_water_event()`, `validate_water_event()` y `get_water_event_detail()`, siguiendo el patrón `security definer` de Sprint 03. Estadísticas descriptivas (sin predicción) y pestaña "Agua" integrada en `AppShell`.

### Sprint 05 — Map

15. `...0017_map_reports` — RPC pública `get_map_reports()` con DTO que expone **solo datos públicos** (sin `created_by`, emails, teléfonos ni metadatos privados). Filtros: Todas, Activas, Resueltas, Mi sector, Recientes, Más validadas. Usa índice espacial GIST `reports_location_gix` para bounding box. Límite acotado 1–200. Accesible para `anon` y `authenticated`.

App: pantalla **Mapa** (`lib/features/map/`) con MapLibre/OSM, markers diferenciados ACTIVE/RESOLVED, selección → detalle existente (`LeakDetailScreen`), vista Mapa ↔ Lista sincronizada (mismo provider `mapReportsProvider`), ubicación del usuario bajo demanda (no tracking continuo), estados UX (carga, vacío, error, sin permiso GPS), y respeto estricto de RLS y privacidad.

### Corrección de la auditoría del Sprint 01

16. `...0015_audit_sprint01_fixes` — mínimos privilegios en `app_users` (sin `INSERT` de cliente), verificación estricta de PostGIS y `ensure_app_user()` con firma `jsonb` + `UNAUTHORIZED` controlado sin sesión. Detalle en `docs/MIGRATION_NOTES.md` § "Auditoría Sprint 01".

### Sprint 06 — Notifications

17. `...0016_audit_sprint02_fixes` — mínimos privilegios por columnas: el cliente no lee `report_photos.storage_path`/`thumbnail_path` ni `reports.created_by` (la identidad del reportante no es pública).
18. `...0018_notifications` — `notification_preferences` (un sector de interés 0..1 + ON/OFF de agua), `notifications` (RLS cerrada, idempotencia `UNIQUE (user_id, water_event_id)`) y `notification_tokens`; RPCs `save_notification_preferences` y `register/unregister_notification_token` con `status_code` y mínimo privilegio; trigger `notify_water_event` (WATER_ARRIVED/WATER_LEFT).
19. `...0019_notifications_platform` — plataformas soportadas corregidas a Android/iOS (sin Web).
20. `...0020_notifications_hardening` — el cliente solo **lee** sus tokens; el alta/baja pasa exclusivamente por las RPC.

La entrega push usa Database Webhook → Edge Function `notify-push` → **FCM HTTP v1** (OAuth2 service account). Detalle en `docs/SETUP.md` § "Push notifications".

### Sprint 07 — Security & Abuse Hardening

21. `...0021_rate_limiting_schema` — tabla `rate_limit_tracking` (ventana fija de 1 h, upsert atómico por `(user_id, operation_type, window_start)`, sin acceso de cliente), configuración por operación en `system_config.rate_limits` (fallbacks hardcodeados) y helpers `get_rate_limit`/`check_rate_limit`.
22. `...0022_notification_preferences_rls_fix` — el cliente solo lee preferencias; toda modificación pasa por la RPC.
23. `...0023_rate_limiting_integration` / `...0024_rate_limiting_rpc_updates` — rate limit integrado en las 5 RPC de escritura (`create_leak_report` 3/h, `validate_leak` 20/h, `confirm_leak_resolution` 10/h, `register_water_event` 5/h, `validate_water_event` 20/h): valida antes de mutar y responde `RATE_LIMIT_EXCEEDED` + `reset_at` sin efectos secundarios en tablas de negocio.
24. `...0025_def01_rate_limit_helpers_revoke` — DEF-01: revoca `EXECUTE` de `check_rate_limit`/`check_rate_limit_inline` a `public`, `anon` y `authenticated`; solo las RPC (SECURITY DEFINER) las invocan.
25. `...0026_create_leak_report_description_validation` — descripción acotada a 500 caracteres (`VALIDATION_ERROR` antes del rate limit), además del CHECK de integridad existente.

### Sprint 08 — Stabilization (en curso)

Sin migraciones nuevas. Cobertura de regresión server-side (`supabase/tests/rate_limiting_test.sql`, `supabase/tests/rate_limit_concurrency_e2e.sh`), higiene de los scripts E2E, consistencia UX de errores conocidos (`RATE_LIMIT_EXCEEDED`, red, timeout) y preparación del build Android release. Detalle en `docs/audits/` cuando el tester cierre la validación.

## Pruebas SQL y de integración

Requieren una base Supabase local levantada con `supabase start` (o `SUPABASE_DB_URL` apuntando a una base con las migraciones aplicadas).

```bash
# RLS de municipios/sectores/app_users (Sprint 01)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_test.sql

# RLS del bucket privado de fotos (Sprint 02)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/storage_report_photos_test.sql

# Tablas, constraints, RLS de reportes y RPC create_leak_report
# (validaciones, límites configurables y duplicados)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/create_leak_report_test.sql

# Sprint 03: tablas de acciones, RLS/GRANT, validación, resolución,
# umbral, estados y consistencia de contadores
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/validate_resolve_leak_test.sql

# Sprint 05: RPC get_map_reports (DTO público, filtros, bbox, límites, RLS)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/map_reports_test.sql

# Sprint 06: notificaciones (RLS, idempotencia, preferencias, tokens)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/notifications_test.sql

# Sprint 07/08: rate limiting por operación (límites exactos, aislamiento,
# bypass, privilegios de helpers, sin efectos secundarios al rechazar)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rate_limiting_test.sql
```

`supabase/tests/water_events_test.sql` (Sprint 04) también existe en el mismo directorio con el mismo comando.

Los scripts de `supabase/tests/*.sh` verifican el comportamiento real de la **API** y la concurrencia (Supabase bloquea el DML directo sobre `storage.objects`, así que el borrado y el aislamiento entre usuarios solo se pueden probar por HTTP). Todos hacen cleanup (incluido ante interrupción) y distinguen `PASS`/`FAIL`/`NOT EXECUTED` (exit 0/1/2):

```bash
# Storage: subir/leer/borrar con dos usuarios anónimos reales (aislamiento y cleanup)
# (también acepta SUPABASE_URL/SUPABASE_ANON_KEY de un proyecto remoto)
bash supabase/tests/storage_rls_e2e.sh

# Camino completo: usuario anónimo → subida → RPC → ACTIVE → duplicado → cleanup
bash supabase/tests/create_leak_report_e2e.sh

# Ciclo comunitario completo por REST con usuarios anónimos reales:
# validar, duplicado, detalle, 1/3 → 2/3 → RESOLVED y RLS de campos críticos
bash supabase/tests/community_flow_e2e.sh

# Concurrencia real: 2 sesiones validando a la vez y 4 confirmando a la vez
bash supabase/tests/community_concurrency_e2e.sh

# Concurrencia real sobre el rate limit: 6 sesiones paralelas creando reportes
# → exactamente 3 aceptadas (límite), 3 rechazadas con RATE_LIMIT_EXCEEDED
bash supabase/tests/rate_limit_concurrency_e2e.sh
```

## Conexión Flutter ↔ Supabase

```
UI → Provider (Riverpod) → Repository → GotaAuth/GotaDatabase → SupabaseClient
```

- Arranque: si no hay sesión → `signInAnonymously()` → sesión persistente entre ejecuciones.
- Después: `rpc('ensure_app_user')` crea/recupera el `app_users` asociado a `auth.users.id` sin duplicar.
- Las consultas de municipios/sectores pasan por `MunicipalityRepository` / `SectorRepository`.
- Las acciones comunitarias pasan por `LeakCommunityRepository` → `GotaCommunityDatabase` (RPC protegidas); el cliente nunca escribe contadores, estado ni tablas de acciones.

## Decisiones y problemas conocidos

- **Navegación:** `UX_SPEC.md` y `FUNCTIONAL_SPEC.md` definen cinco posiciones con acción central (Reportar); cualquier otra numeración es anterior y la documentación manda.
- **Sectores:** catálogo piloto cargado (96 activos en 3 municipios). El dataset completo de la isla (10 municipios, 307 sectores) está en `supabase/seed_data/ne_margarita_sectores.json` (ver `docs/SETUP.md` § "Seed inicial").
- **iOS:** compatible arquitectónicamente; el release iOS puede venir después (Android es la prioridad).
- El test RLS es un script SQL y requiere Supabase CLI/local DB para ejecutarse; no corre en `flutter test`.
- **Fotos en el detalle:** el detalle de una fuga muestra el conteo de fotos, no los binarios de otros usuarios (Storage sigue siendo privado por carpeta). Publicarlas requiere URLs firmadas server-side y queda para un sprint posterior.
