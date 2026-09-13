# Auditoría Gota — Sprint 03 (Validation & resolution)

- **Fecha:** 2026-09-12 (UTC-4)
- **Commit auditado:** `5e34092`
- **Modo:** SOLO LECTURA.
- **Alcance:** S03 — validación comunitaria, confirmación de resolución, reglas atómicas, historial (audit_events). Migraciones 00013, 00016 (correcciones S02 que afectan privacidad/ancho de banda).

## Veredicto

**CONFIGURADO Y VERIFICADO.** Validación y resolución atómicas, con RLS cerrada y auditoría. Privacidad del reportante preservada (created_by no expuesto).

## Checklist

| # | Ítem | Estado | Evidencia |
|---|------|--------|-----------|
| 1 | Tablas `report_validations` / `resolution_confirmations` + UNIQUE(user) | OK | presentes; migración 00013 |
| 2 | RLS sin políticas en tablas de acción (denegado por defecto) | OK | `relrowsecurity=t`, `revoke all` a anon/authenticated |
| 3 | RPC `validate_leak` (for update, no auto-valida, 1 vez) | OK | grant a authenticated; migración 00013 |
| 4 | RPC `confirm_leak_resolution` (transición atómica a RESOLVED a 3) | OK | `resolution_threshold()`=3 en `system_config`; grant OK |
| 5 | `get_leak_report_detail` (estado del usuario, sin leak de identidad) | OK | grant a authenticated; migración 00013 |
| 6 | `audit_events` registra validación/resolución | OK | ambas RPCs insertan en `audit_events` |
| 7 | Privacidad: `reports.created_by` no concedido a cliente | OK | `reports` grant SELECT sin `created_by` (00016); `report_photos` sin grant a anon/authenticated |
| 8 | Límite descripción 500 (AUD-S2-10) y `starts_with` (AUD-S2-11) | OK | aplicados en CREATE OR REPLACE 00016 |

## Notas

- Atomicidad: cada RPC bloquea la fila (`for update`) y actualiza contador + estado en la misma transacción; no hay ventana de inconsistencia.
- El umbral de resolución (3) vive en `system_config`, no hard-codeado.
- AUD-S2-03 (geofence bbox de Nueva Esparta) queda documentado como deuda explícita, no implementado — coherente con "no inventar config".

## Acción necesaria

**NINGUNA** para la validación. Deuda documentada (bbox) es decisión de diseño, no defecto.
