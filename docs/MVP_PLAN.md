# Gota — MVP Plan

**Versión:** 0.2

## Ciclo

```text
PROJECT_BRIEF
  ↓
REQUIREMENTS
  ↓
FUNCTIONAL_SPECIFICATION
  ↓
UX/UI DESIGN
  ↓
ARCHITECTURE
  ↓
DATA_MODEL
  ↓
API_SPECIFICATION
  ↓
IMPLEMENTATION
  ↓
TESTING
  ↓
COMMUNITY PILOT
  ↓
FEEDBACK
```

## Fases

### Sprint 01 — Foundation
- Flutter project.
- arquitectura base;
- Supabase;
- PostGIS;
- Anonymous Auth;
- app_users;
- municipalities;
- sectors;
- RLS;
- conexión Flutter ↔ Supabase;
- tests iniciales.

**No construir reportes todavía.**

### Sprint 02 — Leak reporting
- modelo reports;
- fotos;
- ubicación;
- create-leak-report;
- detección de duplicados.

### Sprint 03 — Validation & resolution
- validación;
- confirmación de resolución;
- reglas atómicas;
- historial.

### Sprint 04 — Water
- water_events;
- validación;
- historial;
- estadísticas descriptivas.

### Sprint 05 — Map
- MapLibre/OSM;
- markers;
- filtros;
- lista/mapa.

### Sprint 06 — Notifications ✅
- preferencias: un sector de interés (0..1, opcional, no GPS) + ON/OFF de agua;
- notifications persistentes con RLS e idempotencia `UNIQUE (user_id, water_event_id)`;
- generación server-side por trigger `notify_water_event` (WATER_ARRIVED/WATER_LEFT);
- tokens FCM (RPC register/unregister, plataformas android/ios);
- Database Webhook → Edge Function `notify-push` → **FCM HTTP v1** (OAuth2 service account);
- tap push → navegación al Water Event (background + terminated); bandeja con read/unread.

### Sprint 07 — Security & abuse ✅
- RLS revisión;
- rate limits (5 RPC de escritura, ventana fija 1 h, `RATE_LIMIT_EXCEEDED` + `reset_at`);
- auditoría (DEF-01 helpers de rate limit revocados a `authenticated` en `07557a4`, revalidado en `docs/audits/2026-09-13_def01_revalidation.md`);
- pruebas de abuso.

### Sprint 08 — Stabilization 🚧 en curso
- tests de regresión server-side del rate limiting (`supabase/tests/rate_limiting_test.sql`, `rate_limit_concurrency_e2e.sh`);
- higiene de scripts E2E (cleanup fiable ante fallos);
- consistencia UX de errores conocidos del backend (`RATE_LIMIT_EXCEEDED`, red, timeout);
- build Android release reproducible (firma configurable, R8, sin secretos en el repo).

### Sprint 09 — Pilot
- piloto pequeño;
- métricas;
- feedback;
- backlog v0.2/v1.

## Definition of Done

Una tarea no está terminada si falta cualquiera de los elementos aplicables:

1. código;
2. migración;
3. RLS/seguridad;
4. tests;
5. UX/error states;
6. documentación;
7. verificación manual.

## Método con agente

Una tarea por prompt.

El prompt debe indicar:
- contexto;
- documentos fuente;
- objetivo;
- archivos permitidos;
- restricciones;
- criterios de aceptación;
- comandos de prueba;
- formato de entrega.

El agente no debe avanzar al siguiente sprint por iniciativa propia.
