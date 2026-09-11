# Gota v0.2

Aplicación comunitaria móvil (Flutter + Supabase) para reportar y validar fugas de agua y registrar eventos de suministro en Isla de Margarita, Venezuela.

**Estado: Sprint 02 — Leak Reporting implementado** (Sprint 01 — Foundation, completado).

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
- Migraciones versionadas: PostGIS, `municipalities`, `sectors`, `app_users`, RLS y seed de Maneiro/Arismendi.

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
| `SUPABASE_ENV` | No | `development` (por defecto) o `production`. |

Nunca usar la `service_role` key en el cliente. Si faltan las variables obligatorias, la app arranca y muestra una pantalla de configuración ausente en lugar de fallar.

## Ejecutar la app

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<proyecto>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public> \
  --dart-define=SUPABASE_ENV=development
```

Sin credenciales también se puede lanzar `flutter run`; la app mostrará el aviso de configuración ausente.

## Tests y análisis estático

```bash
flutter analyze
flutter test
```

Los tests son 100 % offline (fakes/mocks de las abstracciones de red): config, auth anónima, persistencia idempotente de `app_users`, repositorio de municipios (Maneiro y Arismendi) y el widget de la app.

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
```

Los dos últimos scripts de `supabase/tests/*.sh` verifican el comportamiento real de la **API** (Supabase bloquea el DML directo sobre `storage.objects`, así que el borrado y el aislamiento entre usuarios solo se pueden probar por HTTP):

```bash
# Storage: subir/leer/borrar con dos usuarios anónimos reales (aislamiento y cleanup)
bash supabase/tests/storage_rls_e2e.sh

# Camino completo: usuario anónimo → subida → RPC → ACTIVE → duplicado → cleanup
bash supabase/tests/create_leak_report_e2e.sh
```

## Conexión Flutter ↔ Supabase

```
UI → Provider (Riverpod) → Repository → GotaAuth/GotaDatabase → SupabaseClient
```

- Arranque: si no hay sesión → `signInAnonymously()` → sesión persistente entre ejecuciones.
- Después: `rpc('ensure_app_user')` crea/recupera el `app_users` asociado a `auth.users.id` sin duplicar.
- Las consultas de municipios/sectores pasan por `MunicipalityRepository` / `SectorRepository`.

## Decisiones y problemas conocidos

- **Navegación:** `UX_SPEC.md` y `FUNCTIONAL_SPEC.md` definen cinco posiciones con acción central (Reportar); cualquier otra numeración es anterior y la documentación manda.
- **Sectores:** estructura lista; seed pendiente de fuente validada.
- **iOS:** compatible arquitectónicamente; el release iOS puede venir después (Android es la prioridad).
- El test RLS es un script SQL y requiere Supabase CLI/local DB para ejecutarse; no corre en `flutter test`.
