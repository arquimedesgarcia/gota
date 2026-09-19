# Auditoría E2E — Beta / Piloto (Release Candidate readiness)

Fecha: 2026-09-19 · Base auditada: `main` @ `679eb23` (feat: improve leak location suggestions)
Modo: solo lectura / QA E2E. Sin cambios de código, migraciones ni configuración.

## Veredicto

**READY PARA RC/BETA PILOTO, CON 1 CONDICIÓN OPERATIVA** (ver Hallazgo H1) y
cobertura de UX en dispositivo NO VERIFICADA en esta auditoría (entorno sin
emulador/dispositivo activo). No se detectaron regresiones en R1–R4 ni en D2.

## FASE 1 — Inspección

- Commit HEAD: `679eb23`. Últimos 4 commits = Beta Hardening: `9300594` (D2 GPS +
  reverse geocoding), `87a24ce` (3 UX corrections post-D2), `ba2a5d4` (R1–R4 por
  feedback de device validation), `0e31130` (pilot fixes task spec + kotlin
  incremental off), `679eb23` (B1 sugerencias de ubicación, tests B1-01–B1-06).
- `docs/PILOT_FIXES_TASK.md` define R1–R3 (flujo agua simplificado, refresh de
  historial, resolución requiere confirmación) y R4 (investigación de saltos de
  zoom). Verificado en código: `water_register_screen.dart` (flujo type→mun→sector→
  resumen con fecha editable), `waterHistoryControllerProvider.refresh()` post-create,
  `canConfirmResolution` respeta estado del backend, y en `map_providers.dart:44`
  el debounce de `setBounds` por igualdad (R4).
- Estado backend cloud piloto: catálogos OK (3 municipios / 96 sectores activos),
  `reports` y `notifications` correctamente NO legibles por anon (42501),
  `reverse-geocode` desplegada (401 sin JWT, 200 con JWT).
- Stack local Docker levantado y en la misma versión de migraciones que main.

## Pruebas ejecutadas (resultados reales)

| Suite | Resultado |
| --- | --- |
| `flutter analyze` | 0 issues |
| `flutter test` (suite completa) | **164/164 PASS** |
| E2E shell locales (storage_rls, create_leak_report, community_flow, community_concurrency, rate_limit_concurrency, pilot_catalog) | **6/6 PASS** |
| Suites SQL locales (8 archivos en `supabase/tests/*.sql`) | **8/8 PASS** (tras limpiar residuos previos; ver H2) |
| **Ciclo comunitario completo contra cloud piloto** (4 usuarios anónimos reales: catálogo → upload foto → create_leak_report → duplicado → validate×3 → confirm×3 → RESOLVED → detalle) | **PASS** |
| `reverse-geocode` cloud con JWT | **PASS**: HTTP 200, eco de coordenadas idénticas (11.002, -63.802 → enviadas 11.002, -63.802), sugerencia útil ("Pampatar, Municipio Maneiro…") |
| Rate limiting cloud | NO EJECUTADO (evitó dejar residuos de reportes en el piloto; verificado localmente 3/3 PASS) |
| UX en dispositivo/emulador Android (HOME, pantallas pequeñas, navegación real) | **NOT RUN** — no hay AVD ni dispositivo conectado (`adb devices` vacío, sin AVDs) |
| FCM push real | **NOT VERIFIED** — ver H1 |

## Checklist fase 2 (E2E como usuario)

- HOME / navegación / estados (loading, error, retry, vacío): cubiertos por widget
  tests (164 PASS). Verificación visual en dispositivo: NOT RUN.
- R1 agua (flujo simplificado + resumen con fecha/hora editable): implementado y
  con tests. Sin regresión detectada.
- R2 historial se refresca tras crear evento: implementado (`refresh()` post-create).
- R3 resolución requiere validación comunitaria: verificado E2E cloud real —
  validaciones 1→2→3, confirmaciones solo empujan al umbral, RESOLVED exactamente
  en la 3ª identidad distinta, `resolved_at` establecido una sola vez.
- R4 zoom del mapa: fix por igualdad de bounds presente; sin regresión en tests.
  Comportamiento visual real: NOT RUN (requiere dispositivo).
- D2 GPS: `reverse-geocode` cloud re-validada en esta auditoría (200, eco exacto,
  JWT requerido). Municipio/sector siguen siendo selección explícita (sugerencia
  B1 no muta `draft.*Id`; probado por tests B1-01–B1-06).
- Seguridad cloud re-confirmada: anon no lee `reports` ni `notifications` (42501),
  storage privado por carpeta (borrado de archivo ajeno bloqueado, local E2E).

## Hallazgos

| ID | Severidad | Descripción |
| --- | --- | --- |
| H1 | **IMPORTANT (bloqueante si el piloto incluye notificaciones push)** | `notify-push` NO está desplegada en el proyecto cloud piloto (`POST /functions/v1/notify-push` → 404; `reverse-geocode` sí responde 401). La app es fail-soft (NoopPushService), así que no rompe nada, pero FCM push no se entregará en el piloto. Acción: `npx supabase functions deploy notify-push --project-ref <ref>` + `FCM_SERVICE_ACCOUNT_JSON` configurado. |
| H2 | MINOR | Las suites SQL `create_leak_report_test.sql` y `map_reports_test.sql` asumen BD limpia y no eliminan su semilla; con residuos previos fallan con asserts confusos ("esperaba 3, obtuvo 4"). En baseline limpio ambas PASS. Acción sugerida: que las suites limpien sus filas al final. |
| H3 | MINOR | `pilot_catalog_e2e.sh` sobreescribe `ANON_KEY` con `npx supabase status` (línea 18), por lo que el parámetro remoto se ignora y el script no es ejecutable contra cloud ("NOT EXECUTED: no se pudo crear usuario anónimo"). En esta auditoría el E2E cloud se replicó por script propio (`qa-evidence/pilot_cloud_e2e_audit.py`). |
| H4 | INFO | Residuo dejado en el piloto por este E2E (sin ruta de borrado con anon): 1 reporte en estado RESOLVED (`967de23e-34f6-4d28-90e4-fad66cf7cd20`, oculto del mapa por defecto) y 4 usuarios anónimos de prueba. Limpieza opcional con service-role. |
| H5 | INFO | Verificación visual/UX en dispositivo Android (incl. pantallas pequeñas) y FCM real quedan NOT RUN/NOT VERIFIED por entorno, no por defecto de producto. |

## Acción necesaria

1. H1: desplegar `notify-push` en el proyecto piloto antes del arranque si el
   alcance del piloto incluye notificaciones push.
2. H5: ejecutar la pasada de UX en dispositivo/AVD (APK con defines reales) —
   es el único gate de readiness pendiente que esta auditoría no pudo cubrir.
3. Opcionales: H2 y H3 como deuda de harness de pruebas; H4 limpieza con
   service-role si se desea.
