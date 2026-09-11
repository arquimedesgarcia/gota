# Gota — Consolidation Notes

This document records the important consolidation decisions.

## Replaced decisions

| Previous material | Consolidated decision |
|---|---|
| Firebase | Supabase |
| Phone OTP | Anonymous Auth |
| Firestore | PostgreSQL + PostGIS |
| Firebase Storage | Supabase Storage |
| Cloud Functions | Supabase Edge Functions |
| Hive/WorkManager mandatory offline queue | Deferred; not Sprint 01 |
| 1–2 photos | 1–3 photos |
| 2 validation confirmations | Validation is independent; resolution requires 3 distinct users |
| PENDIENTE/CONFIRMADA/CERRADA_* | ACTIVE/RESOLVED |
| Phone hash as public identity | Supabase anonymous user ID, never public |
| Google Maps | MapLibre + OpenStreetMap abstraction |
| Parroquia as mandatory MVP relation | Municipality + configurable sector; do not invent geography |

## Reused from previous material

- visual identity and color tokens;
- screen composition;
- community-oriented microcopy;
- review checklist discipline;
- small-task construction workflow;
- prototype interaction patterns;
- accessibility rules;
- explicit handling of offline/empty/error states as UX concerns.

## Prototype status

`prototipo/index.html` is a visual/interaction reference only.

If prototype behavior contradicts this documentation, this documentation wins.

## Sprint 02 — decisiones de almacenamiento y validación

Revisión posterior al commit `06fe3bd` (correcciones de cierre de Sprint 02):

| Tema | Decisión |
|---|---|
| Rutas de fotos | `report_photos/{auth_user_id}/{upload_key}/{photo_id}.jpg`. La pertenencia se deriva de la ruta, que es lo que exige la política RLS. |
| Lectura de binarios | Sprint 02 no los publica: cada usuario solo lee los suyos. El detalle/mapa de un sprint posterior los resolverá server-side (URLs firmadas). |
| Escritura | Un usuario solo sube a su carpeta. Sin `service_role` en el cliente. |
| Borrado | Permitido solo sobre la carpeta propia: habilita la limpieza de temporales. |
| DML directo | Supabase bloquea `delete`/`update` directos sobre `storage.objects`; la limpieza se hace por la API de Storage (lo que ya hace `_cleanupUploaded()`). |
| Limpieza | Se ejecuta cuando falla la RPC, cuando se detecta `POSSIBLE_DUPLICATE` o cuando el backend rechaza el reporte. Si el borrado falla, se reintenta una vez y el error se muestra al usuario: nunca se dejan huérfanos en silencio. |
| Validación de fotos | Doble capa: cliente (formato/tamaño/cantidad inmediatos) y servidor (autoridad). La RPC verifica cada foto contra `storage.objects` (existencia, pertenencia, `mimetype` y `size`) y contra `system_config.photo_limits` (`max_count`, `max_bytes`, `allowed_mime_types`). Los metadatos persistidos se toman del binario real, no de lo que declare el cliente. |
| Duplicados | REQ-025: el candidato nunca bloquea en silencio. La RPC devuelve `POSSIBLE_DUPLICATE` y solo crea el reporte con `p_ignore_duplicate = true`, que la app envía cuando el usuario confirma "es otra fuga". |
| Operación crítica | Sigue siendo SQL protegido (`security definer`) como en Sprint 01, no una Edge Function: no añade infraestructura nueva y es la costura ya establecida. |
| Supuesto | La RPC lee `storage.objects`, así que el rol que aplica las migraciones necesita lectura sobre ese esquema (es el caso en Supabase local y hospedado; verificado contra la base local). Si no la tuviera, la RPC devuelve `STORAGE_ERROR` (falla cerrado) y no se crea nada. |
