# Gota v0.2

Aplicación comunitaria móvil (Flutter + Supabase) para reportar y validar fugas de agua y registrar eventos de suministro en Isla de Margarita, Venezuela.

**Estado: Sprint 01 — Foundation implementado.**

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

## Ejecutar

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

> **Pendiente:** el seed de **sectores** queda aplazado hasta contar con una fuente validada (ver `docs/DATA_MODEL.md` §7). No inventar sectores.

### Pruebas RLS

`supabase/tests/rls_test.sql` contiene un script SQL autocontenido que verifica las políticas RLS (usuario A no puede leer la fila de B, `ensure_app_user()` es idempotente, etc.). Requiere una base Supabase local levantada con `supabase start`; se ejecuta con:

```bash
psql "$SUPABASE_DB_URL" -f supabase/tests/rls_test.sql
# o con el wrapper del CLI si se habilita la suite de tests
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
