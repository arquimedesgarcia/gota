# Auditoría Gota — Sprint 02 (Leak reporting)

- **Fecha:** 2026-09-12 (UTC-4)
- **Commit auditado:** `5e34092`
- **Modo:** SOLO LECTURA.
- **Alcance:** S02 — modelo reports, fotos, ubicación, create-leak-report, detección de duplicados, storage.

## Veredicto

**CONFIGURADO Y VERIFICADO.** Esquema, RLS, bucket y RPC coherentes con el código cliente.

## Checklist

| # | Ítem | Estado | Evidencia |
|---|------|--------|-----------|
| 1 | Tabla `reports` + constraints (status, location geography, índices gist) | OK | `to_regclass('public.reports')`; migración 00007 |
| 2 | Tabla `report_photos` | OK | presente; migración 00008 |
| 3 | RPC `create_leak_report` (security definer) + grant a authenticated | OK | función existe, `proacl` seteado a authenticated |
| 4 | Validaciones server-side (ubicación, sector/municipio, fotos, duplicados) | OK | migración 00010 implementa auth + límites + `st_dwithin` 50m/48h |
| 5 | Bucket `report-photos` privado + RLS folder propio | OK | `storage.buckets`: `public=false`; políticas insert/select/delete restringidas a `auth.uid()` |
| 6 | `system_config`: photo_limits / duplicate_detection | OK | claves presentes |
| 7 | Cliente no escribe `reports` directo; usa RPC + sube a carpeta propia | OK | `leak_report_repository.dart`: `_storage.upload` a `report_photos/{uid}/...` + `_database.rpcCreateLeakReport` |
| 8 | Limpieza de binarios huérfanos (fail/duplicate) | OK | `_cleanupUploaded` en errores y `PossibleDuplicateFound` |

## Notas

- El cliente solo lleva clave pública (anon) + sesión; la RPC corre como owner (security definer) — cumple el contrato anti-escritura-directa.
- `reports` expone SELECT a `anon` y `authenticated` vía RLS (la app lista reportes públicos). Consistente con el modelo de comunidad.

## Acción necesaria

**NINGUNA** para la validación.
