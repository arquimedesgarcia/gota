# Auditoría Gota — Sprint 01 (Foundation)

- **Fecha:** 2026-09-12 (UTC-4)
- **Commit auditado:** `5e34092`
- **Modo:** SOLO LECTURA. Sin mutaciones.
- **Alcance:** S01 — Flutter base, Supabase, PostGIS, Anonymous Auth, app_users, municipalities, sectors, RLS, conexión Flutter↔Supabase.

## Veredicto

**CONFIGURADO Y VERIFICADO.** Base de datos y conexión cliente coherentes con las migraciones 00001–00006 / 00015.

## Checklist

| # | Ítem | Estado | Evidencia |
|---|------|--------|-----------|
| 1 | PostGIS instalada | OK | `pg_extension` tiene `postgis` |
| 2 | Tablas base existen | OK | `municipalities`, `sectors`, `app_users` presentes |
| 3 | `set_updated_at()` + triggers | OK | función existe; triggers en `municipalities`/`sectors` (00002/00003) |
| 4 | RLS habilitado en tablas base | OK | `relrowsecurity=t` en municipalities, sectors, app_users, reports, report_photos |
| 5 | Provisionamiento app_users | OK | `handle_new_user()` + trigger `on_auth_user_created` en `auth.users`; `ensure_app_user()` presente y con grant |
| 6 | Anonymous Auth (config) | OK | `config.toml`: `enable_anonymous_sign_ins = true` |
| 7 | Conexión Flutter↔Supabase | OK | `main.dart:32 Supabase.initialize`; `gota_auth.signInAnonymously` → `auth.signInAnonymously` |

## Notas

- `config.toml` usa `site_url = "http://localhost:3000"` (dev). En producción debe apuntar al dominio real (pendiente operativo, fuera de alcance).
- No se detectaron discrepancias entre migración, runtime y código cliente para S01.

## Acción necesaria

**NINGUNA** para la validación.
