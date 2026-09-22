# Gota — API Specification

**Versión:** 0.2

## 1. Principio

Lecturas simples pueden usar Supabase SDK con RLS.

Las reglas críticas se ejecutan mediante Edge Functions o SQL protegido.

## 2. Operaciones

### create-leak-report
Entrada:
- municipality_id
- sector_id
- location
- location_source
- description
- photo references

Proceso:
1. autenticar;
2. validar sector;
3. validar ubicación;
4. validar fotos;
5. buscar duplicados 50m/48h;
6. devolver `POSSIBLE_DUPLICATE` si corresponde o crear ACTIVE.

> **Contrato de lectura (privacidad, AUD-S2-01/02 — Sprint 02):** el cliente
> (`anon`/`authenticated`) solo puede hacer `SELECT` por columnas sobre
> `public.reports` — **sin `created_by`** — y **no** tiene lectura sobre
> `public.report_photos` (ni `storage_path` ni `thumbnail_path`). El conteo de
> fotos llega vía `get-leak-report-detail`. Cualquier lectura directa de
> `created_by` o de `report_photos` devuelve `insufficient_privilege`.

### validate-leak

RPC `validate_leak(p_report_id uuid)`.

- reporte debe existir y estar ACTIVE;
- usuario autenticado anónimamente y no bloqueado;
- usuario != creador;
- una validación por usuario (autoridad: `UNIQUE (report_id, user_id)`);
- rate limit;
- operación atómica (una transacción; fila del reporte bloqueada).

Respuesta (`jsonb`): `status_code`, `status`, `validation_count`,
`resolution_confirmation_count`, `resolved_at`, `threshold`,
`already_validated`.

Códigos: `VALIDATED`, `DUPLICATE_ACTION`, `NOT_FOUND`, `FORBIDDEN`,
`REPORT_ALREADY_RESOLVED`, `UNAUTHORIZED`.

### confirm-leak-resolution

RPC `confirm_leak_resolution(p_report_id uuid)`.

- reporte ACTIVE;
- una confirmación por usuario;
- rate limit;
- transición atómica a RESOLVED al llegar a 3 identidades distintas
  (`system_config.resolution.threshold`).

Respuesta (`jsonb`): `status_code`, `status`, `validation_count`,
`resolution_confirmation_count`, `resolved_at`, `threshold`,
`already_confirmed`. `status_code` es `CONFIRMED` mientras el reporte siga
ACTIVE y `RESOLVED` cuando se alcanzó el umbral.

Códigos: `CONFIRMED`, `RESOLVED`, `DUPLICATE_ACTION`, `NOT_FOUND`,
`FORBIDDEN`, `REPORT_ALREADY_RESOLVED`, `UNAUTHORIZED`.

### get-leak-report-detail

RPC `get_leak_report_detail(p_report_id uuid)`: lectura del detalle de una
fuga junto con el estado del usuario actual. Necesaria porque las tablas de
acciones no son legibles por el cliente.

Respuesta (`jsonb`): `report_id`, `status`, `validation_count`,
`resolution_confirmation_count`, `threshold`, `created_at`, `resolved_at`,
`updated_at`, `description`, `location_source`, `latitude`, `longitude`,
`municipality_id`, `municipality_name`, `sector_id`, `sector_name`,
`photo_count`, `is_creator`, `is_blocked`, `already_validated`,
`already_confirmed`.

Códigos: `OK`, `NOT_FOUND`, `UNAUTHORIZED`.

### get-latest-community-activity

RPC `get_latest_community_activity()` (sin parámetros): el **último evento
comunitario a nivel global** sobre fallas para la tarjeta "Actividad reciente"
de Inicio. Global (todos los sectores del piloto), no el sector del usuario.
Devuelve **0 o 1 fila** (`returns table`): el evento más reciente en el tiempo
entre tres tipos, de cualquier falla.

Tipos de evento y su timestamp (`at`):

- `REPORTED` — falla creada: `reports.created_at`.
- `VALIDATED` — la falla **cruzó el umbral** de validación comunitaria
  (`system_config.validation.threshold`, hoy 3): `created_at` de la N-ésima
  validación (N = umbral), ordenada por `(created_at, id)`. **No** es cada
  validación individual: la 1ª y la 2ª de una falla con umbral 3 no producen
  evento; la que cruza el umbral sí.
- `RESOLVED` — falla resuelta: `reports.resolved_at`.

Orden determinista: `at desc`, y a igual `at` gana `RESOLVED` > `VALIDATED` >
`REPORTED` con desempate final por `report_id`.

Columnas: `activity_type` (`REPORTED`|`VALIDATED`|`RESOLVED`), `at`,
`report_id`, `status` (estado ACTUAL: `ACTIVE`|`RESOLVED`), `validation_count`,
`resolution_confirmation_count`, `created_at`, `resolved_at`, `description`,
`sector_id`, `sector_name`, `municipality_id`, `municipality_name`.

Grants: `revoke execute … from public` + `grant execute … to anon,
authenticated` (lectura pública, igual que `get-map-reports`).

**Privacidad (REQ-100):** ningún campo de identidad. Sin `created_by`,
`user_id`, email, teléfono, `storage_path` ni ids de `app_users`. El lateral
sobre `report_validations` es válido porque la función es `security definer`;
el cliente sigue sin acceso directo a esa tabla.

### register-water-event (Sprint 04)

RPC `register_water_event(p_municipality_id, p_sector_id, p_event_type, p_event_time, p_comment)`.

- Autenticar y resolver usuario de aplicación (no bloqueado).
- Validar municipio y sector (existen, activos, relación municipio/sector).
- Validar event_type (solo `WATER_ARRIVED` o `WATER_LEFT`).
- Validar event_time (no nulo, no futuro).
- Validar comentario (max 500 chars, normalizar vacío a NULL).
- Insertar en `water_events` con `validation_count = 0`.
- Auditar: evento `WATER_EVENT_CREATED`.
- Devolver resumen: `status_code` (CREATED/NOT_FOUND/INVALID_SECTOR/VALIDATION_ERROR/FORBIDDEN/UNAUTHORIZED).

Respuesta (`jsonb`): `status_code`, `event_id`, `event_type`, `event_time`, `created_at`.

### validate-water-event (Sprint 04)

RPC `validate_water_event(p_water_event_id)`.

- Autenticar y resolver usuario de aplicación (no bloqueado).
- Bloquear la fila del evento (`for update`).
- Validar existencia (ACTIVE no existe en agua, pero evento debe existir).
- Rechazar si creador == usuario actual.
- Insertar en `water_event_validations` con `on conflict do nothing`.
- Si inserción exitosa: incrementar `validation_count` atómicamente, auditar.
- Si duplicado: devolver `DUPLICATE_ACTION` (determinista, sin alterar contador).
- Devolver: `status_code`, `validation_count`, `already_validated`, `message`.

Códigos: `VALIDATED`, `DUPLICATE_ACTION`, `NOT_FOUND`, `FORBIDDEN`, `UNAUTHORIZED`.

### get-water-event-detail (Sprint 04)

RPC `get_water_event_detail(p_water_event_id)`: lectura del detalle de un evento + estado del usuario actual.

Respuesta (`jsonb`): `status_code` (OK/NOT_FOUND/UNAUTHORIZED), `event_id`, `event_type`, `event_time`, `comment`, `validation_count`, `created_at`, `updated_at`, `municipality_id`, `municipality_name`, `sector_id`, `sector_name`, `is_creator`, `is_blocked`, `already_validated`.

**NO expone `created_by`.**

### register_notification_token (Sprint 06)

RPC `register_notification_token(p_token text, p_platform text)`: registra o
reactiva el token FCM del dispositivo para el usuario autenticado. Como
`token` es UNIQUE global, un token reasignado (mismo dispositivo, otra
instalación) pasa a la identidad que lo registra ahora. El `user_id` sale de
`auth.uid()`, jamás del cliente. Plataformas válidas: `android`, `ios`
(`web` fue eliminado en la migración 00019: sin soporte Web en Sprint 06).

Códigos: `OK`, `VALIDATION_ERROR`, `FORBIDDEN`, `UNAUTHORIZED`.

### unregister_notification_token (Sprint 06)

RPC `unregister_notification_token(p_token text)`: desactiva (`is_active =
false`) un token propio. No borra la fila (historial de tokens obsoletos).
La Edge Function de push desactiva por su cuenta los tokens que FCM rechaza
(`UNREGISTERED`, `SENDER_ID_MISMATCH`).

Códigos: `OK`, `NOT_FOUND`, `UNAUTHORIZED`.

### save_notification_preferences (Sprint 06)

RPC `save_notification_preferences(p_preferred_sector_id uuid,
p_water_notifications_enabled boolean)`: upsert de la preferencia del
usuario autenticado. `preferred_sector_id = NULL` significa "sin sector de
interés". La unicidad de 1 fila por usuario la garantiza la PK, no el
cliente; el sector se valida (existe y está activo).

Códigos: `OK`, `NOT_FOUND`, `FORBIDDEN`, `UNAUTHORIZED`.

La bandeja se lee directo por PostgREST sobre `notifications` (RLS propia);
`read_at` se actualiza por UPDATE de columna concedida.

## 3. Errores

- UNAUTHORIZED
- FORBIDDEN
- NOT_FOUND
- VALIDATION_ERROR
- DUPLICATE_ACTION
- POSSIBLE_DUPLICATE
- RATE_LIMITED
- INVALID_LOCATION
- INVALID_SECTOR
- REPORT_ALREADY_RESOLVED
- STORAGE_ERROR
- INTERNAL_ERROR

## 4. Paginación

Usar cursor/paginación para listas.

## 5. Payload de mapa

Solo campos necesarios para pintar y abrir detalle.

## 6. Fotos

No enviar binarios dentro de la función. Usar Storage y persistir referencias.

## 7. Notificaciones

Sprint 06 implementa **solo** notificaciones de suministro (las de fugas —
validación/resolución de reportes — quedan para un sprint posterior):

Eventos:
- WATER_ARRIVED
- WATER_LEFT

Cadena (la fila de `notifications` es la fuente de verdad):

```text
water_events INSERT → trigger notify_water_event → notifications INSERT
→ Database Webhook (supabase_functions.http_request vía pg_net)
→ Edge Function notify-push → FCM HTTP v1 → dispositivo
```

- El backend determina destinatarios: usuarios con `preferred_sector_id`
  igual al sector del evento y `water_notifications_enabled = true`.
- Idempotencia: `UNIQUE (user_id, water_event_id)` + `ON CONFLICT DO NOTHING`.
- Si FCM falla, la notification persistente **no** se revierte (fail-soft).
- Payload FCM v1: `notification.{title, body}` y `data.{notification_id,
  type, water_event_id}` (este último habilita navegar al evento al tocar).

## 8. Versionado

Los contratos deben ser compatibles y versionarse cuando exista una ruptura real.
