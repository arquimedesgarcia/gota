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

## Sprint 03 — decisiones de validación y resolución

Implementación del ciclo comunitario sobre el patrón de Sprint 02 (RPC SQL
protegida, sin Edge Functions ni infraestructura nueva).

| Tema | Decisión |
|---|---|
| Validación | `REQ-040`–`REQ-044` implementadas tal cual: cualquier identidad anónima no bloqueada valida una fuga ACTIVE de otro usuario, una sola vez por reporte, con el creador excluido. La regla vive en la RPC `validate_leak`, no en la UI. |
| Duplicados | La autoridad real es `UNIQUE (report_id, user_id)` en `report_validations` / `resolution_confirmations`. La segunda acción devuelve `DUPLICATE_ACTION` (resultado de dominio, no error genérico) y no altera contadores ni estado. |
| Umbral | Sigue siendo **3 identidades distintas** (REQ-053). Se guarda en `system_config.resolution = {"threshold": 3}` en lugar de quedar hard-codeado en la función; la RPC lo lee con respaldo 3. |
| Ambigüedad de REQ-051 | El texto ("el creador puede participar solo si no está confirmando su propio reporte como mecanismo de validación de existencia") es ambiguo. Decisión mínima compatible: `confirm-leak-resolution` en `API_SPEC.md` **no** excluye al creador (a diferencia de `validate-leak`, que sí lo hace) y REQ-050 dice "cualquier usuario". Por tanto el creador **no** puede validar la existencia de su fuga, pero **sí** puede confirmar su resolución, una sola vez y con las mismas garantías que cualquier otra identidad. La decisión está cubierta por prueba (`OK 4i`). |
| Estados | Solo ACTIVE/RESOLVED, sin estados nuevos. Ninguna operación permite `RESOLVED → ACTIVE`; una fuga resuelta responde `REPORT_ALREADY_RESOLVED`. |
| Atomicidad y concurrencia | Cada RPC: identidad → `for update` sobre la fila del reporte → inserción con `on conflict do nothing` → incremento de contador y (si procede) `status`/`resolved_at` en la misma sentencia → auditoría. Todo en una transacción; el bloqueo de fila serializa accesos concurrentes. Verificado con dos y cuatro sesiones reales en paralelo (`supabase/tests/community_concurrency_e2e.sh`). |
| Privacidad de las tablas de acciones | `report_validations` y `resolution_confirmations` no son legibles ni escribibles por el cliente (RLS sin políticas + `REVOKE ALL`). El estado propio ("¿ya validé?") llega por la RPC `get_leak_report_detail`, evitando exponer qué validó cada identidad. |
| Lecturas de la UI | El listado de "Fugas cerca de ti" usa una lectura sencilla por SDK con RLS (recursos embebidos `sectors(name)` / `municipalities(name)`); el detalle y las acciones pasan por RPC. |
| Pendiente declarado (fuera de Sprint 03) | Las fotografías siguen sin publicarse entre usuarios: el detalle muestra el conteo, no binarios ajenos. Publicarlas exige URLs firmadas server-side (Sprint 02 lo dejó explícitamente para un sprint posterior). |
