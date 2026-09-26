# PROMPT 15 — Fix fotos de fugas: signed URLs vía Edge Function (2026-09-26)

## Contexto y síntoma

En **Detalle de fuga** no se muestran las fotos de un reporte, ni siquiera para
el propio autor. El rediseño del PROMPT 14 (montar siempre el carrusel) no lo
resolvió porque el problema no está en la UI sino en el backend de lectura.

## Causa raíz (verificada en código)

El flujo es correcto en captura, subida y persistencia:

- Captura: `PhotosStepView` + `PhotoService` (0..2 fotos, compresión + thumb).
- Subida: `SupabaseLeakReportRepository.createReport`
  (`lib/features/leaks/data/leak_report_repository.dart:73-110`) sube a
  `report_photos/{auth.uid()}/{uploadKey}/{photoId}.jpg`, que **coincide** con
  la política RLS de escritura del bucket (`00012`).
- Persistencia: la RPC `create_leak_report` (`00010`) valida contra
  `storage.objects` e inserta filas en `public.report_photos`. Correcto.

El punto roto es **la lectura**:

- La RPC `public.get_report_photos` (`migración 00033`) construye la respuesta
  llamando a **`storage.create_signed_url('report-photos', path, 900)`**.
- **Esa función SQL no existe en Supabase.** Las signed URLs de Storage se
  firman (HS256 con el JWT secret) en el servicio `storage-api`; no hay función
  PL/pgSQL que las genere. Solo se pueden crear vía:
  1. los SDK de cliente / API REST de Storage, o
  2. una Edge Function con `service_role`.
  (Feature request abierto: github.com/orgs/supabase/discussions/29317.)
- En tiempo de ejecución, el RPC lanza
  `function storage.create_signed_url(...) does not exist`. El cliente
  (`SupabaseLeakPhotoRepository.getPhotos`) lo captura como
  `PostgrestException` → `QueryException`; `leakPhotosProvider` queda en error y
  el carrusel no pinta nada.
- Corolario: el test SQL `get_report_photos_test.sql` nunca pudo pasar contra
  una BD real (habría fallado al invocar la función inexistente). Coincide con
  que los tests de ese sprint quedaron delegados y sin ejecutar.

## Objetivo

Que **cualquier usuario autenticado** vea las fotos de un reporte en el
Detalle, respetando el contrato de privacidad ya aprobado en el PROMPT 12: el
cliente **nunca** recibe `storage_path` crudo (la ruta embebe el `auth.uid()`
del autor, un identificador estable que no debe filtrarse entre usuarios).

## Diseño

Se conserva la arquitectura aprobada en el PROMPT 12 (RPC + signed URLs, bucket
privado) y solo se corrige el mecanismo de firma, que era imposible en SQL. Se
traslada la firma a una Edge Function con `service_role` (mismo patrón e
infraestructura que `notify-push`), y el gating (auth/bloqueado/existe/rate
limit) permanece en SQL, en una RPC invocable **solo por el servidor**.

```
Flutter (functions.invoke, JWT del usuario)
   → Edge Function get-report-photos
        1. verifica el JWT del llamador  → auth_uid   (GET /auth/v1/user)
        2. RPC get_report_photo_paths(auth_uid, report_id)  [service_role]
             · gating: UNAUTHORIZED / FORBIDDEN / NOT_FOUND / RATE_LIMIT
             · devuelve rutas crudas (server-side, nunca al cliente)
        3. firma cada ruta con service_role
             POST /storage/v1/object/sign/report-photos/{path} {expiresIn:900}
        4. responde el MISMO contrato que ya parsea el cliente:
             { status_code, photos:[{id,sort_order,width,height,url,thumbnail_url}] }
```

Ventajas:

- Preserva la privacidad: la ruta cruda (con `auth.uid`) nunca sale del
  servidor. El cliente solo ve signed URLs temporales (TTL 900 s).
- Reutiliza el gating y el rate-limit ya probados, sin reimplementarlos en TS.
- El cliente cambia **solo el transporte**: modelo `LeakPhoto`, repositorio,
  `leakPhotosProvider` y el carrusel del Detalle no cambian.
- Consistente con la infraestructura existente (`notify-push` ya usa
  `service_role` + REST + WebCrypto, sin `supabase-js`).

### ¿Por qué no firmar en el cliente?

`SupabaseClient.storage.createSignedUrl` funciona, pero para firmar la foto de
**otro** usuario haría falta: (a) ampliar la RLS de `SELECT` de
`storage.objects` a todos los autenticados y (b) devolver la ruta cruda al
cliente. Ambas cosas filtran el `auth.uid` del autor y contradicen el contrato
del PROMPT 12. Descartado.

### ¿Por qué no `pg_net`/`http` desde la RPC?

Firmar llamando al endpoint de Storage vía `pg_net` es asíncrono
(fire-and-forget) y no puede devolver la URL en la misma llamada. Descartado.

## Cambios

### Backend

1. **Migración `20260926000034_get_report_photo_paths.sql`**
   - Nueva RPC `public.get_report_photo_paths(p_auth_uid uuid, p_report_id uuid)`
     `SECURITY DEFINER`, `search_path` fijo:
     - Resuelve `app_users` por `p_auth_uid` → `UNAUTHORIZED` si no existe.
     - `is_blocked` → `FORBIDDEN`.
     - Rate limit `check_rate_limit(app_user.id,'get_report_photos')` →
       `RATE_LIMIT_EXCEEDED`.
     - Existencia del reporte → `NOT_FOUND`.
     - Devuelve `{ status_code:'OK', photos:[{id,sort_order,width,height,
       storage_path,thumbnail_path}] }` (rutas crudas; uso server-side).
     - `REVOKE EXECUTE FROM public, anon, authenticated;`
       `GRANT EXECUTE TO service_role;`  → inalcanzable desde el cliente.
     - No confía en `auth.uid()` (bajo `service_role` es NULL): usa el
       `p_auth_uid` que la Edge Function ya verificó.
   - `DROP FUNCTION IF EXISTS public.get_report_photos(uuid);` — RPC rota,
     reemplazada por la Edge Function.

2. **Edge Function `supabase/functions/get-report-photos/index.ts`**
   - `POST` con `{ report_id }`. Requiere `Authorization: Bearer <jwt>`.
   - Verifica el JWT (`GET /auth/v1/user`) → `auth_uid`; sin/expirado →
     `{status_code:'UNAUTHORIZED'}`.
   - Llama a la RPC vía REST con `service_role`; propaga
     `UNAUTHORIZED/FORBIDDEN/NOT_FOUND/RATE_LIMIT_EXCEEDED`.
   - En `OK`, firma cada `storage_path` (y `thumbnail_path` si existe) con
     `POST /storage/v1/object/sign/...` y compone `url`/`thumbnail_url`
     absolutas (`SUPABASE_URL` + `/storage/v1` + `signedURL`).
   - **Siempre responde HTTP 200** con `status_code` en el cuerpo (los errores
     de dominio no son excepciones de transporte), salvo fallo interno
     inesperado (500). Sin `supabase-js`, solo `fetch` (patrón `notify-push`).
   - `deno.json` con `--allow-net --allow-env`.

### Cliente (Flutter)

3. `GotaCommunityDatabase.rpcGetReportPhotos`
   (`lib/core/network/gota_community_database.dart`): en vez de
   `_client.rpc('get_report_photos', ...)`, invoca
   `_client.functions.invoke('get-report-photos', body:{'report_id':reportId})`
   y devuelve el `data` como `Map`. Mantiene el nombre del método y el contrato.

4. `SupabaseLeakPhotoRepository.getPhotos`
   (`lib/features/leaks/data/leak_photo_repository.dart`): añadir captura de
   `supabase.FunctionException` → `QueryException` (además de las ya presentes).
   El `switch(status_code)` no cambia.

### Tests

5. `supabase/tests/get_report_photos_test.sql` → reescribir como
   `get_report_photo_paths_test.sql`: mismos casos (anon/no-service_role
   bloqueado, NOT_FOUND, FORBIDDEN, rate limit, OK con `storage_path`/
   `thumbnail_path` y orden, thumb NULL), verificando además que
   `authenticated` **no** puede ejecutar la RPC (solo `service_role`).
6. Dart: el test de `leak_detail_screen` ya inyecta
   `leakPhotoRepositoryProvider`; no requiere cambios de contrato.

## Criterio de aceptación

1. Usuario B abre el detalle de un reporte de usuario A y ve las fotos.
2. El autor también ve sus fotos.
3. El cliente nunca recibe `storage_path` crudo (solo signed URLs con TTL).
4. Un cliente autenticado no puede ejecutar `get_report_photo_paths`
   directamente (solo la Edge Function con `service_role`).
5. `flutter analyze` y los tests Dart en verde.

## Notas de despliegue

- Desplegar la Edge Function: `supabase functions deploy get-report-photos`
  (usa `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY`, ya inyectadas por la
  plataforma; el mismo entorno que `notify-push`).
- Aplicar la migración `20260926000034`.
- No hay retro-generación de thumbnails: las fotos viejas sin thumb muestran la
  foto completa (`displayThumbnailUrl` cae a `url`).
</invoke>
