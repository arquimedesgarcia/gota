# Auditoría Gota — Sprint 04 (Water events)

- **Fecha:** 2026-09-12 (UTC-4)
- **Commit auditado:** `5e34092`
- **Modo:** SOLO LECTURA.
- **Alcance:** S04 — water_events, validación, historial, estadísticas descriptivas. Migración 00014.

## Veredicto

**CONFIGURADO Y VERIFICADO.** Registro/validación de eventos atómicos, historial público sin leak de identidad, estadísticas descriptivas en cliente.

## Checklist

| # | Ítem | Estado | Evidencia |
|---|------|--------|-----------|
| 1 | Tabla `water_events` + constraints (event_type, event_time, índices) | OK | presente; migración 00014 |
| 2 | Tabla `water_event_validations` + UNIQUE(user) | OK | presente |
| 3 | RLS: `water_events` SELECT público; `water_event_validations` revocado a cliente | OK | `relacl` confirma `anon=r`,`authenticated=r` en water_events; validations solo postgres/service_role |
| 4 | RPC `register_water_event` (security definer, reglas server-side) | OK | grant a authenticated |
| 5 | RPC `validate_water_event` (for update, no auto-valida, 1 vez) | OK | grant a authenticated |
| 6 | RPC `get_water_event_detail` (estado usuario, sin created_by) | OK | grant a authenticated |
| 7 | Auditoría en `audit_events` | OK | ambas RPCs insertan |
| 8 | Estadísticas DESCRIPTIVAS (REQ-077: sin predicción) | OK | `water_statistics.dart`: `computeWaterStatistics` en cliente sobre eventos cargados; sin RPC de stats |

## Notas

- `event_time` no futuro (sanidad), sin ventana de validación (decisión documentada, va a Sprint 07).
- Rate limiting de water_events queda para Sprint 07 (REQ-091), igual que S03.
- Identidad del creador no expuesta (created_by fuera de SELECT concedido).

## Acción necesaria

**NINGUNA** para la validación. Deuda de rate limiting y ventana de validación documentadas para S07.
