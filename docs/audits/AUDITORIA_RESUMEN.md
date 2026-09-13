# Auditoría Sprints 01–03 — Índice y resumen ejecutivo

**Proyecto:** Gota v0.2 (Flutter + Supabase)
**Repo:** `github.com/arquimedesgarcia/gota` · rama `main` · auditado en HEAD `41d82a9`
**Informes:**
- [`AUDITORIA_SPRINT_01.md`](AUDITORIA_SPRINT_01.md) — Foundation
- [`AUDITORIA_SPRINT_02.md`](AUDITORIA_SPRINT_02.md) — Leak Reporting
- [`AUDITORIA_SPRINT_03.md`](AUDITORIA_SPRINT_03.md) — Validation & Resolution

> Auditoría **solo de lectura**: no se modificó código, migración, test ni configuración. Los únicos archivos añadidos son estos tres informes (sin *commit*).

## Qué se ejecutó realmente

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | `No issues found!` |
| `flutter test` | **92/92 en verde** (todos offline, con fakes/mocks) |
| Barrido de manifiestos Android + plugins | 0 de 8 declaran `INTERNET` (ver hallazgo bloqueante) |
| Inspección de PostgREST (`config.toml`, `GRANT`/RLS) | Confirmada la exposición del esquema `public` a `anon`/`authenticated` |
| Suites SQL y E2E (`supabase/tests/*.sql`, `*.sh`, concurrencia) | **NO ejecutadas**: el motor Docker no estaba disponible en la máquina de auditoría (`npipe:////./pipe/dockerDesktopLinuxEngine`). Revisadas solo de forma estática. |

## Bloqueantes (2)

| ID | Sprint | Hallazgo | Arreglo |
|---|---|---|---|
| AUD-S1-01 | 01 | El APK de **release** no tiene permiso `INTERNET` (solo lo tienen los manifiestos de debug/profile, y ningún plugin lo aporta): toda la app queda sin red fuera de `flutter run`. | Añadir `<uses-permission android:name="android.permission.INTERNET"/>` a `android/app/src/main/AndroidManifest.xml`. |
| AUD-S2-01 | 02 | `public.report_photos` es de lectura pública y su `storage_path` contiene `report_photos/{auth_user_id}/…`: la identidad del reportante es legible y correlacionable por cualquier cliente (incumple REQ-100). | `grant select` por columnas (sin `storage_path`), o retirar la lectura pública y exponer los metadatos por RPC. |

## Importantes (14)

| ID | Tema |
|---|---|
| AUD-S1-02 | `sectors` sin datos ni vía de carga: el flujo de reporte es inejecutable con datos reales |
| AUD-S1-03 | `SUPABASE_ENV` aceptado pero sin efecto (la separación dev/prod es nominal) |
| AUD-S2-02 | `reports.created_by` legible por cualquier cliente (autoría correlacionable) |
| AUD-S2-03 | "Ubicación manual" es un formulario lat/lng, no selección en mapa (REQ-021) |
| AUD-S2-04 | El override "es otra fuga" queda pegado y salta la detección de duplicados tras editar la ubicación |
| AUD-S2-05 | El duplicado no permite ver/validar el reporte existente (REQ-025 y UX_SPEC §5) |
| AUD-S2-06 | La pantalla final dice "Reporte enviado" cuando solo se reutilizó uno existente |
| AUD-S2-07 | `limit 5` sin `ORDER BY` en los candidatos: la distancia mostrada puede no ser la menor |
| AUD-S2-08 | Sin miniaturas (`thumbnail_path` siempre `NULL`) y `width`/`height` siempre `NULL` |
| AUD-S2-09 | La cámara nunca se ofrece en la UI (solo galería) |
| AUD-S3-02 | "Fugas cerca de ti" sin filtro geográfico ni paginación: se degrada con el uso |
| AUD-S3-03 | No existe historial de fugas resueltas (REQ-054 / `FUNCTIONAL_SPEC` §10) |
| AUD-S3-04 | Identidades anónimas multiplicables reinstalando la app → "3 identidades distintas" es frágil |
| AUD-S3-05 | REQ-091: no existe ningún rate limit ni su configuración |

El detalle de cada hallazgo (severidad, archivo y línea, evidencia, impacto y recomendación) está en el informe del sprint correspondiente.

## Lo que está bien y conviene preservar

- **Patrón de seguridad consistente:** RLS + `GRANT` mínimo + RPC `security definer` con `search_path = ''` y `EXECUTE` solo a `authenticated`. Sin `service_role` en el cliente, sin secretos en el repo.
- **Reglas críticas server-side de verdad:** duplicados, validación, resolución y contadores viven en PostgreSQL; el cliente no puede escribir `reports`, `report_validations` ni `resolution_confirmations`.
- **Atomicidad y concurrencia demostrables** por diseño (`for update` + `UNIQUE` + contador y estado en la misma sentencia) con evidencia de prueba prevista para 2 y 4 sesiones paralelas.
- **Configuración de negocio fuera del código:** 50 m/48 h, límites de fotos y umbral de resolución en `system_config`, con respaldo en la función.
- **Validación de fotos contra el binario real** en Storage (no contra lo que declara el cliente), con limpieza de huérfanos y reintento visible.
- **Disciplina documental:** `MIGRATION_NOTES.md` registra decisiones, ambigüedades y pendientes; la UI no anuncia éxito antes de que responda el backend (salvo AUD-S2-06).

## Orden de corrección sugerido

1. **AUD-S1-01** (una línea; desbloquea cualquier verificación en release).
2. **AUD-S2-01 / AUD-S2-02** (privacidad; `GRANT` por columnas o RPC de metadatos).
3. **AUD-S2-06**, luego **AUD-S2-04/05** (corrección del flujo de duplicado).
4. **AUD-S1-02** (cargar sectores validados y documentar el procedimiento) — habilita la verificación manual de todos los sprints.
5. **Confirmar AUD-S3-01** con producto y decidir AUD-S3-03; registrar AUD-S3-04/05 como deuda con plan de mitigación.
6. Re-ejecutar y adjuntar como evidencia las suites SQL/E2E (`supabase start` + los `*.sql` y `*.sh`), que esta auditoría no pudo correr.
