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

### register-water-event
- validar municipio/sector;
- registrar event_type y event_time;
- aplicar rate limit.

### validate-water-event
- usuario != creador;
- una validación por usuario;
- rate limit.

### register-notification-token
Registra/actualiza token FCM del usuario.

### update-notification-preferences
Actualiza preferencias de fugas/suministro y sector.

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

Eventos:
- REPORT_VALIDATED
- REPORT_RESOLVED
- WATER_ARRIVED
- WATER_LEFT

El backend determina destinatarios según sector y preferencias.

## 8. Versionado

Los contratos deben ser compatibles y versionarse cuando exista una ruptura real.
