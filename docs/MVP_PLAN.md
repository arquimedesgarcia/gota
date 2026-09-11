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

### Sprint 06 — Notifications
- FCM;
- tokens;
- preferencias;
- eventos.

### Sprint 07 — Security & abuse
- RLS revisión;
- rate limits;
- auditoría;
- pruebas de abuso.

### Sprint 08 — Stabilization
- tests;
- UX;
- rendimiento;
- errores;
- Android release.

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
