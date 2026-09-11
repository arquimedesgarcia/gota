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
- report_id
- user_id
- created_at

Unique `(report_id, user_id)`.

### resolution_confirmations
- id UUID
- report_id
- user_id
- created_at

Unique `(report_id, user_id)`.

### water_events
- id UUID
- created_by
- municipality_id
- sector_id
- event_type (`WATER_ARRIVED`, `WATER_LEFT`)
- event_time
- comment
- validation_count
- created_at
- updated_at

### water_event_validations
- id UUID
- water_event_id
- user_id
- created_at

Unique `(water_event_id, user_id)`.

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

La operación debe ser atómica:

1. comprobar reporte ACTIVE;
2. insertar confirmación si no existe;
3. contar identidades distintas;
4. si count >= 3, cambiar a RESOLVED;
5. guardar resolved_at.

## 6. RLS

- municipios/sectores activos: lectura pública.
- reportes: lectura pública según alcance del MVP.
- identidad y datos privados: solo propietario.
- escrituras críticas: mediante operaciones protegidas.

## 7. Datos iniciales

Seed:
- Maneiro
- Arismendi

No inventar sectores si no existe una fuente validada. La estructura debe quedar lista para cargar sectores después.
