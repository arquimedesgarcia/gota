# Gota — Data Model

**Versión:** 0.2

## 1. Extensiones

- `postgis`

## 2. Tablas

### municipalities
- id UUID
- name
- state
- country
- is_active
- created_at
- updated_at

### sectors
- id UUID
- municipality_id FK
- name
- is_active
- created_at
- updated_at

Unique: `(municipality_id, name)`.

### app_users
- id UUID
- auth_user_id UUID FK a auth.users
- created_at
- last_seen_at
- is_blocked

### reports
- id UUID
- created_by UUID
- municipality_id
- sector_id
- location geography(Point,4326)
- location_source (`GPS`, `MANUAL`)
- description
- status (`ACTIVE`, `RESOLVED`)
- validation_count
- resolution_confirmation_count
- created_at
- updated_at
- resolved_at

### report_photos
- id UUID
- report_id
- storage_path
- thumbnail_path
- mime_type
- size_bytes
- width
- height
- sort_order
- created_at

### report_validations
- id UUID
- report_id FK a `reports` (on delete cascade)
- user_id FK a `app_users` (on delete cascade)
- created_at

Unique `(report_id, user_id)`: es la autoridad real contra duplicados (una
identidad valida una sola vez). Índices por `report_id` y por `user_id`.

### resolution_confirmations
- id UUID
- report_id FK a `reports` (on delete cascade)
- user_id FK a `app_users` (on delete cascade)
- created_at

Unique `(report_id, user_id)`. Índices por `report_id` y por `user_id`.

`report_validations` y `resolution_confirmations` no tienen acceso de cliente
(ni lectura): el estado propio ("¿ya validé?") se obtiene por la RPC
`get_leak_report_detail`, y toda escritura pasa por `validate_leak` /
`confirm_leak_resolution`.

### water_events (Sprint 04)
- id UUID
- created_by UUID FK a `app_users`
- municipality_id UUID FK a `municipalities`
- sector_id UUID FK a `sectors`
- event_type TEXT CHECK (`WATER_ARRIVED`, `WATER_LEFT`)
- event_time timestamptz (la hora efectiva del evento; puede diferir de `created_at`)
- comment TEXT nullable (max 500 chars)
- validation_count int default 0
- created_at timestamptz default now()
- updated_at timestamptz default now()

Índices: `(sector_id, event_time DESC)`, `(municipality_id, event_time DESC)`, `(created_at DESC)`.

### water_event_validations (Sprint 04)
- id UUID
- water_event_id UUID FK a `water_events`
- user_id UUID FK a `app_users`
- created_at timestamptz default now()

Unique `(water_event_id, user_id)`. Índices por `water_event_id` y `user_id`.

### notification_tokens
- id UUID
- user_id
- token
- platform
- is_active
- created_at
- updated_at
- last_used_at

### notification_subscriptions
- id UUID
- user_id
- municipality_id
- sector_id
- leaks_enabled
- water_supply_enabled
- created_at
- updated_at

### audit_events
- id UUID
- user_id nullable
- event_type
- entity_type
- entity_id
- metadata jsonb
- created_at

### system_config
- key
- value jsonb
- updated_at

Claves sembradas: `duplicate_detection` (radio/ventana), `photo_limits`
(cantidad/tamaño/MIME) y `resolution` (`{"threshold": 3}`).

## 3. Índices

- GIST sobre `reports.location`.
- reports por status/sector/municipality/created_at.
- water_events por sector/event_time.
- FKs e índices de búsqueda habituales.

## 4. Reglas espaciales

Posible duplicado:

- status = ACTIVE
- distancia ≤ 50m
- created_at dentro de 48h

Valores configurables mediante `system_config`.

## 5. Resolución

La operación es atómica y ocurre server-side (RPC
`confirm_leak_resolution`):

1. autenticar y resolver el usuario de aplicación (no bloqueado);
2. bloquear la fila del reporte (`for update`) y comprobar que sigue ACTIVE;
3. insertar la confirmación con `on conflict do nothing` sobre
   `UNIQUE (report_id, user_id)`;
4. incrementar `resolution_confirmation_count` y, en la misma sentencia,
   pasar a `RESOLVED` con `resolved_at = now()` cuando el contador alcanza el
   umbral;
5. registrar la auditoría.

Umbral: **3 identidades distintas** (`system_config.resolution.threshold`).
El bloqueo de la fila serializa confirmaciones concurrentes: la cuarta
identidad recibe `REPORT_ALREADY_RESOLVED` sin alterar contadores ni
`resolved_at`. `RESOLVED → ACTIVE` no existe en ninguna operación.

Validación comunitaria (RPC `validate_leak`): mismas garantías; el creador
del reporte no puede validarlo, y cada identidad valida una sola vez.

## 6. RLS

- municipios/sectores activos: lectura pública.
- reportes: lectura pública **por columnas** (`GRANT SELECT` explícito en
  `id, municipality_id, sector_id, status, description, validation_count,
  resolution_confirmation_count, created_at, updated_at, resolved_at`).
  `created_by` **no** se concede al cliente (identidad del reportante no pública,
  REQ-100; ver `docs/audits/AUDITORIA_SPRINT_02.md` AUD-S2-01/02).
- `report_photos`: **sin** lectura de cliente (se retiró el `GRANT SELECT`); el
  detalle expone `photo_count` vía RPC. Ni `storage_path` ni `thumbnail_path` son
  seleccionables por `anon`/`authenticated`.
- identidad y datos privados: solo propietario.
- escrituras críticas: mediante operaciones protegidas.
- `report_validations` y `resolution_confirmations`: RLS habilitada **sin
  políticas** y sin GRANT para `anon`/`authenticated` (denegado por defecto);
  `reports` solo concede `select`, de modo que `validation_count`,
  `resolution_confirmation_count`, `status` y `resolved_at` no son
  modificables por el cliente.

## 7. Datos iniciales

Seed:
- Maneiro
- Arismendi

No inventar sectores si no existe una fuente validada. La estructura debe quedar lista para cargar sectores después.
