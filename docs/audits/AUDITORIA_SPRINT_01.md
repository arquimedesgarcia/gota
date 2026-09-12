# Auditoría — Sprint 01 (Foundation)

**Proyecto:** Gota v0.2 — Flutter + Supabase (fugas de agua, Isla de Margarita)
**Repositorio:** `github.com/arquimedesgarcia/gota` — rama `main`
**Commit auditado (HEAD):** `41d82a9 feat: implement sprint 04 water events`
**Alcance de este informe:** artefactos del Sprint 01 (`0edd508`…`cf0045b`, migraciones `00001`–`00006`, capa `core/` + navegación + auth anónima)
**Método:** auditoría estática *código vs. documentación fuente de verdad* + ejecución de las suites disponibles
**Fecha:** 2026-09-11

---

## 1. Alcance y criterios

Documentos usados como fuente de verdad:

| Documento | Uso en esta auditoría |
|---|---|
| `docs/MVP_PLAN.md` (§Sprint 01) | Definición del alcance del sprint |
| `docs/REQUIREMENTS.md` | REQ-010…013, REQ-090, REQ-150…152, REQ-170…173 |
| `docs/ARCHITECTURE.md` | Estructura `lib/`, regla de dependencias, §9 ambientes, §10 "qué no construir" |
| `docs/DATA_MODEL.md` | `municipalities`, `sectors`, `app_users`, §7 datos iniciales |
| `docs/SETUP.md` / `README.md` | Procedimiento declarado de puesta en marcha y verificación |

Alcance declarado en `MVP_PLAN.md` §Sprint 01: proyecto Flutter, arquitectura base, Supabase, PostGIS, Anonymous Auth, `app_users`, `municipalities`, `sectors`, RLS, conexión Flutter ↔ Supabase y tests iniciales. **"No construir reportes todavía."**

## 2. Evidencia ejecutada

| Comprobación | Comando | Resultado real |
|---|---|---|
| Análisis estático | `flutter analyze` | **`No issues found!`** (Flutter 3.47.3 / Dart 3.13.3) |
| Tests unitarios/widget | `flutter test` | **92/92 en verde** (`All tests passed!`) |
| Manifiestos Android (merge efectivo) | Barrido de los 7 `AndroidManifest.xml` de plugins + `android/app/src/*` | **Ningún manifiesto declara `INTERNET`** salvo `debug/` y `profile/` |
| Suites SQL y E2E | `docker exec … psql`, `bash supabase/tests/*.sh` | **NO EJECUTADAS.** El motor de Docker no estaba disponible en la máquina de auditoría (`failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`). Se revisaron solo de forma estática. |

> Honestidad metodológica: los 92 tests de `flutter test` son **offline** (fakes de las abstracciones de red). Ninguna aserción de esa suite toca PostgreSQL, PostGIS, Storage ni RLS. La verificación real del Sprint 01 descansa en `supabase/tests/rls_test.sql`, que **no pudo ejecutarse en esta auditoría**.

## 3. Resumen de hallazgos

| ID | Sev. | Tema | Ubicación |
|---|---|---|---|
| AUD-S1-01 | **BLOQUEANTE** | Release Android sin permiso `INTERNET`: toda la app queda sin red | `android/app/src/main/AndroidManifest.xml` |
| AUD-S1-02 | IMPORTANTE | `sectors` sin datos y sin mecanismo de carga: el flujo posterior es inejecutable con datos reales | `00006_seed_municipalities.sql`, `supabase/seed.sql` |
| AUD-S1-03 | IMPORTANTE | `environment` (dev/prod) aceptado pero sin efecto alguno | `lib/core/config/app_config.dart:17,50` |
| AUD-S1-04 | MENOR | `GRANT INSERT` innecesario a `authenticated` sobre `app_users` (los privilegios del trigger ya bastan) | `00005_rls.sql:49` |
| AUD-S1-05 | MENOR | PostGIS ausente solo emite `warning`; el fallo real aparece más tarde y confuso | `00001_extensions.sql:7-15` |
| AUD-S1-06 | MENOR | `ensure_app_user()` sin comprobación de `auth.uid()` nulo (el resto de RPC sí la tiene) | `00004_app_users.sql:33-56` |
| AUD-S1-07 | MENOR | API muerta: `fetchAppUserByAuthId()` definida y nunca usada | `lib/core/network/gota_database.dart:14,56` |
| AUD-S1-08 | MENOR | Sin pipeline CI pese a REQ-171 y PROJECT_BRIEF §5 | repositorio (no existe `.github/`) |
| AUD-S1-09 | MENOR | `README.md` declara "Sprint 03" y omite la migración 14, con HEAD en Sprint 04 | `README.md:5,111-132` |

## 4. Hallazgos detallados

### AUD-S1-01 — BLOQUEANTE · Release Android sin `INTERNET`

**Evidencia.** El manifiesto principal no declara el permiso:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <!-- no hay android.permission.INTERNET -->
```

El permiso solo existe en los manifiestos de desarrollo:

```xml
<!-- android/app/src/debug/AndroidManifest.xml y .../profile/AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET"/>
<!-- "The INTERNET permission is required for development" -->
```

Verificado además que **ningún plugin aporta el permiso en el merge**: se inspeccionaron los 7 paquetes con `AndroidManifest.xml` (`app_links`, `flutter_image_compress_common`, `flutter_plugin_android_lifecycle`, `geolocator_android`, `image_picker_android`, `shared_preferences_android`, `url_launcher_android`) y **ninguno declara `permission.INTERNET`**.

**Impacto.** En `flutter run` (debug/profile) la app funciona; en un **APK de release** (`flutter build apk --release`, objetivo explícito del Sprint 08) el proceso Android no tiene permiso de red: `signInAnonymously()`, `ensure_app_user()`, municipios/sectores y Storage fallarían siempre. Es decir, el entregable central del Sprint 01 —"conexión Flutter ↔ Supabase"— **solo está verificado en modo debug**; ninguna validación manual en release pudo haber pasado nunca.

**Recomendación.** Añadir `<uses-permission android:name="android.permission.INTERNET"/>` al manifiesto principal y verificar con `flutter build apk --release` + instalación real. Es un cambio de una línea con impacto total.

### AUD-S1-02 — IMPORTANTE · `sectors` sin datos y sin vía de carga

**Evidencia.**

```sql
-- 00006_seed_municipalities.sql
insert into public.municipalities (id, name, state, country) values
  ('00000000-0000-4000-8000-000000000001', 'Maneiro',   'Nueva Esparta', 'Venezuela'),
  ('00000000-0000-4000-8000-000000000002', 'Arismendi', 'Nueva Esparta', 'Venezuela')
on conflict (id) do nothing;

-- PENDIENTE: no se inventan sectores sin una fuente validada.
```

`supabase/seed.sql` está vacío (solo comentarios). No existe RPC, script de carga, panel ni procedimiento documentado con fuente validada para insertar sectores; la única vía es escribir una migración SQL a mano.

**Impacto.** `reports.sector_id` es `not null` y `create_leak_report` exige un sector **activo** del municipio (`INVALID_SECTOR` en caso contrario). Con la base migrada tal cual, el paso "Datos" del flujo de reporte muestra un desplegable de sectores vacío y es **imposible reportar una fuga**: el 100% de la aceptación manual de Sprint 02/03 sobre datos reales queda bloqueada. REQ-012 ("los sectores deben ser datos configurables") queda cumplido en estructura pero no en operación.

**Recomendación.** Antes de dar por cerrado Sprint 02: (a) cargar el catálogo de sectores validado de Maneiro y Arismendi vía migración, y (b) documentar en `SETUP.md` el procedimiento y el responsable de esa carga. Se acepta como decisión la de "no inventar geografía", pero deja un hueco operativo que debe declararse explícitamente como dependencia externa.

### AUD-S1-03 — IMPORTANTE · `SUPABASE_ENV` sin efecto

`AppConfig.environment` se lee de `--dart-define=SUPABASE_ENV` y se almacena, pero **nada en el código lo consulta** (grep sobre `lib/`: solo la definición y el test). `README.md` y `docs/ARCHITECTURE.md` §9 prometen separación de ambientes; hoy `development` y `production` se comportan idénticamente salvo por la URL/clave que el operador escriba.

**Recomendación.** O bien eliminar la variable y su mención en la documentación, o darle un uso real (por ejemplo, logging de diagnóstico, o bloquear la limpieza agresiva de binarios en producción).

### AUD-S1-04 — MENOR · Privilegio de INSERT innecesario en `app_users`

```sql
revoke all on public.app_users from anon, authenticated;
grant select, insert on public.app_users to authenticated;   -- 00005_rls.sql:49
grant update (last_seen_at) on public.app_users to authenticated;
```

La fila se crea de dos formas ya cubiertas: el trigger `on_auth_user_created` (`security definer`) y la RPC `ensure_app_user()` (`security definer`, `GRANT EXECUTE` a `authenticated`). Ninguna ruta legítima del cliente hace `INSERT` directo. La política `"Usuario crea su propio perfil"` refuerza esa capacidad sin necesidad.

**Impacto.** Superficie de privilegio mayor de la necesaria (principio de mínimo privilegio, `docs/DATA_MODEL.md` §6). No se detectó un vector de escalada (RLS limita a la fila propia), por eso es MENOR.

**Recomendación.** Retirar `insert` del `GRANT` y la política de INSERT; el trigger y `ensure_app_user` siguen funcionando sin cambios.

### AUD-S1-05 — MENOR · Fallo de PostGIS diferido y confuso

```sql
-- 00001_extensions.sql
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'postgis') then
    raise warning 'postgis no está disponible: las funciones geoespaciales no funcionarán';
```

Solo emite `warning` y la migración continúa. Las migraciones `00007`/`00010`/`00013` usan `extensions.geography`, `extensions.st_setsrid` y `extensions.st_makepoint`: sin PostGIS el error real aparecerá mucho más tarde (`type "extensions.geography" does not exist`) y sin relación visible con la causa.

**Recomendación.** `raise exception` en la migración 00001 (fallar cerrado y temprano), o mover la dependencia a un `if not exists … then create extension` sin envoltorio condicional.

### AUD-S1-06 — MENOR · `ensure_app_user()` sin guarda de identidad

```sql
create or replace function public.ensure_app_user()
...
begin
  insert into public.app_users (auth_user_id) values (auth.uid())
  on conflict (auth_user_id) do nothing
  returning * into v_user;
```

Con `auth.uid()` nulo (rol `authenticated` sin `sub`) el `INSERT` viola el `NOT NULL` y se propaga una excepción Postgres en lugar de un resultado controlado. Las RPC de Sprint 02/03 sí resuelven esto explícitamente (`if v_auth_uid is null then return 'UNAUTHORIZED'`): hay una **inconsistencia de contrato** entre funciones del mismo backend. Alcanzable sobre todo con una sesión a medio expirar; el cliente lo traduce a `QueryException` genérico.

**Recomendación.** Alinear con el patrón de `validate_leak` (retorno tipado o excepción de dominio con mensaje en español).

### AUD-S1-07 — MENOR · API muerta

`GotaDatabase.fetchAppUserByAuthId()` (`gota_database.dart:14` y `:56`) no se invoca desde ningún repositorio ni pantalla; solo existe para que los fakes de test la implementen. Contradice el objetivo de `ARCHITECTURE.md` §4 de que cada costura tenga un rol.

### AUD-S1-08 — MENOR · Sin CI

`docs/PROJECT_BRIEF.md` §5 lista "GitHub + CI/CD" y REQ-171 exige que `flutter analyze` y los tests pasen antes de cerrar un sprint. No existe `.github/` ni ningún workflow: el cumplimiento depende de disciplina manual (esta auditoría tuvo que ejecutar ambos comandos a mano para comprobarlo).

### AUD-S1-09 — MENOR · Deriva documental

`README.md:5` afirma "Estado: Sprint 03", y su lista de migraciones (`README.md:104-132`) termina en la 13; HEAD contiene la migración `20260911000014_water_events.sql` y el commit `41d82a9` (Sprint 04), y `AppShell` ya apunta la pestaña "Agua" a `WaterScreen`. Como `docs/` es la fuente de verdad declarada del proyecto, esta desincronización afecta a la trazabilidad de todo el historial de sprints.

## 5. Trazabilidad requisito → implementación (Sprint 01)

| Requisito | Implementación | Estado |
|---|---|---|
| REQ-010 Maneiro/Arismendi | Migración `00006` (UUID fijos, idempotente) | ✅ Cumple |
| REQ-011 Municipio/sector asociados | `reports`/`water_events` con FK; no aplicable aún en S01 | ✅ Base lista |
| REQ-012 Sectores configurables | Tabla + `UNIQUE (municipality_id,name)` + `is_active` | ⚠️ Estructura sí, **sin datos ni vía de carga** (AUD-S1-02) |
| REQ-013 Extensible a otros municipios | UUID + FK, sin hard-code | ✅ Cumple |
| REQ-090 Identidad anónima persistente | `signInAnonymously()` + `ensure_app_user()` idempotente; `enable_anonymous_sign_ins = true` en `config.toml` | ✅ Cumple (verificado en tests offline) |
| REQ-150 Android prioritario | `android/` presente, `applicationId com.gota.gota` | ⚠️ **Release sin INTERNET** (AUD-S1-01) |
| REQ-151 iOS compatible | Proyecto iOS presente; **falta todo `*UsageDescription`** en `Info.plist` | ⚠️ Ver AUD-X-04 (informe S02) |
| REQ-152 Web fuera del MVP | Sin carpeta `web/` | ✅ Cumple |
| REQ-170 Reglas críticas server-side | Suficiente para S01 (RLS + triggers) | ✅ Cumple |
| REQ-171 analyze/tests antes de cerrar | `flutter analyze` limpio; 92 tests verdes | ✅ Cumple (offline; SQL no ejecutado aquí) |
| REQ-172 Migraciones versionadas | 6 migraciones numeradas y `supabase link/push` documentado | ✅ Cumple |
| REQ-173 Sin infraestructura no justificada | Solo Flutter + Supabase; sin Firebase/Redis/Railway | ✅ Cumple |
| ARCHITECTURE §10 "qué no construir" | Ninguna pieza prohibida introducida | ✅ Cumple |
| Regla de dependencias `UI → Provider → Repository → Database` | `network_providers.dart` + repositorios por feature; la UI no importa `SupabaseClient` | ✅ Cumple |

## 6. Definition of Done (MVP_PLAN §Definition of Done)

| # | Elemento | Estado |
|---|---|---|
| 1 | Código | ✅ |
| 2 | Migración | ✅ (00001–00006) |
| 3 | RLS/seguridad | ⚠️ Implementada; con observaciones AUD-S1-04 |
| 4 | Tests | ⚠️ 92 offline verdes; **suites SQL/RLS no ejecutadas en esta auditoría** y no hay CI |
| 5 | UX/estados de error | ✅ `ConfigMissingView`, `ErrorView` con reintento, `LoadingView`; mensajes en español |
| 6 | Documentación | ⚠️ `README`/`SETUP` desactualizados respecto a HEAD (AUD-S1-09) |
| 7 | Verificación manual | ⚠️ No reproducible contra datos reales sin sectores (AUD-S1-02) |

## 7. Aspectos verificados sin hallazgos

- RLS de `municipalities`/`sectors`: política `select` solo filas `is_active = true`, `revoke all` + `grant select` (mínimo privilegio correcto).
- `app_users`: RLS habilitada, `select/update` limitados a la fila propia y `update` restringido por columna a `last_seen_at` (`00005_rls.sql:50`) — evita que el cliente se auto-desbloquee (`is_blocked` fuera del `GRANT`).
- `ensure_app_user()` es `security definer` con `set search_path = ''` y `GRANT EXECUTE` solo a `authenticated`: patrón correcto y reutilizado después por todo el backend.
- `on_conflict (auth_user_id) do nothing` garantiza idempotencia del perfil; cubierto por los tests (`OK 2f` del script RLS y `auth_repository_test.dart`).
- `handle_new_user()` con `security definer` + `search_path` vacío: correcto.
- Navegación de cinco destinos con acción central y estados "próximamente" honestos (no simulan funcionalidad), según `FUNCTIONAL_SPEC.md` §1.
- Sin secretos en el repositorio: no hay `.env` versionado, `grep` de `service_role`/JWT solo devuelve comentarios y documentación; `--dart-define` como único canal de credenciales.
- Los 92 tests cubren config ausente/ inválida, sesión anónima, perfil idempotente, mapeo de errores de red y de PostgREST, y el widget raíz.
- No se introdujo ninguna tecnología fuera de stack (sin Firebase, Redis, RabbitMQ, Railway, microservicios).

## 8. Veredicto Sprint 01

**Base arquitectónica sólida y bien documentada; no apta para release.**

- El patrón de seguridad (RLS + `GRANT` mínimo + RPC `security definer` con `search_path` vacío) es correcto, coherente y se convirtió en la costura de los sprints siguientes.
- **Bloqueante:** AUD-S1-01 (release sin `INTERNET`) invalida cualquier verificación en modo release y es el riesgo más alto de todo el proyecto hasta que se corrija.
- **Riesgo operativo alto:** AUD-S1-02 (sin sectores no hay flujo ejecutable de punta a punta).
- El resto son incumplimientos de contrato/limpieza (ambiente sin efecto, API muerta, privilegio extra) sin impacto funcional inmediato.
- La afirmación de cierre del sprint ("tests iniciales") es cierta en la parte offline; la parte servidor no se pudo re-ejecutar en esta auditoría y debería quedar registrada como pendiente de evidencia.
