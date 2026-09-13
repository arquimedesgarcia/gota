# Auditoría — Sprint 02 (Leak Reporting)

**Proyecto:** Gota v0.2 — Flutter + Supabase
**Repositorio:** `github.com/arquimedesgarcia/gota` — rama `main`
**Commit auditado (HEAD):** `41d82a9 feat: implement sprint 04 water events`
**Alcance de este informe:** artefactos del Sprint 02 (`d2fcd61`…`d7049e4`, migraciones `00007`–`00012`, feature `lib/features/leaks/`, `gota_storage.dart`, `system_config`/`audit_events`)
**Método:** auditoría estática *código vs. documentación fuente de verdad* + ejecución de las suites disponibles
**Fecha:** 2026-09-11

---

## 1. Alcance y criterios

Alcance del sprint según `docs/MVP_PLAN.md`: modelo `reports`, fotos, ubicación, `create-leak-report` y detección de duplicados.

Reglas aplicables: REQ-020…025 (fugas), REQ-030…032 (duplicados), REQ-040 (validación, aún no en este sprint), REQ-100/101/102 (privacidad), REQ-023 (fotos validadas, comprimidas y almacenadas de forma segura), REQ-173. Contrato: `docs/API_SPEC.md` §2 (`create-leak-report`), §3 (errores), §6 (fotos); `docs/DATA_MODEL.md` §4 (reglas espaciales); `docs/FUNCTIONAL_SPEC.md` §3 (flujo de reporte); `docs/UX_SPEC.md` §4/§5.

## 2. Evidencia ejecutada

| Comprobación | Comando | Resultado real |
|---|---|---|
| Análisis estático | `flutter analyze` | **`No issues found!`** |
| Tests unitarios/widget | `flutter test` | **92/92 en verde**, incluidos `leak_repository_test.dart` (subida, cleanup, códigos del backend) y `photo_limits_test.dart` |
| Manifiestos Android | Barrido de `android/app/src/**` y de los 7 manifiestos de plugins | Sin `INTERNET` fuera de debug/profile (ver AUD-S1-01) |
| Exposición PostgREST | `supabase/config.toml` → `schemas = ["public","storage","graphql_public"]` + `GRANT`/RLS de la migración `00011` | **Confirmada**: `reports` y `report_photos` son consultables por `anon`/`authenticated` |
| Suites SQL/E2E | `create_leak_report_test.sql`, `storage_report_photos_test.sql`, `create_leak_report_e2e.sh`, `storage_rls_e2e.sh` | **NO EJECUTADAS** (motor Docker no disponible: `npipe:////./pipe/dockerDesktopLinuxEngine`). Revisadas solo de forma estática. |

## 3. Resumen de hallazgos

| ID | Sev. | Tema | Ubicación |
|---|---|---|---|
| AUD-S2-01 | **BLOQUEANTE** | `report_photos.storage_path` es de lectura pública e incluye el `auth.uid()` del creador → identidad del reportante correlacionable | `00011_rls_reports.sql:28-34`, `00012_storage_report_photos.sql:7` |
| AUD-S2-02 | IMPORTANTE | `reports.created_by` legible por cualquier cliente: autoría correlacionable entre reportes | `00011_rls_reports.sql:17-25` |
| AUD-S2-03 | IMPORTANTE | "Ubicación manual" es un formulario de latitud/longitud, no selección en mapa | `leak_report_screen.dart:240-307` |
| AUD-S2-04 | IMPORTANTE | El override "es otra fuga" (`_ignoreDuplicate`) queda pegado y sobrevive a cambios de la ubicación | `leak_report_controller.dart:89,244-251` |
| AUD-S2-05 | IMPORTANTE | El duplicado no ofrece "ver/validar el existente": solo un botón que cierra el flujo | `leak_report_screen.dart:665-699`, `leak_report_controller.dart:255-258` |
| AUD-S2-06 | IMPORTANTE | En la ruta "usar el reporte existente" la pantalla final anuncia **"Reporte enviado"** sin que se haya enviado nada | `leak_report_screen.dart:787,800-805` |
| AUD-S2-07 | IMPORTANTE | `limit 5` sin `ORDER BY` dentro de la subconsulta de candidatos: la distancia mostrada puede no ser la menor | `00010_create_leak_report.sql:230-245` |
| AUD-S2-08 | IMPORTANTE | No se generan miniaturas (`thumbnail_path` siempre `NULL`) y `width`/`height` quedan siempre `NULL` | `photo_service.dart:80-90`, `00010:204-218` |
| AUD-S2-09 | IMPORTANTE | La UI nunca ofrece cámara: `addPhoto(fromCamera: false)` fijo | `leak_report_screen.dart:390` |
| AUD-S2-10 | MENOR | La RPC no valida la longitud de `description`: un texto >500 produce error Postgres, no `VALIDATION_ERROR` | `00010:255-263` vs `API_SPEC §3` |
| AUD-S2-11 | MENOR | Comprobación de pertenencia con `LIKE` donde `_` es comodín | `00010:158` |
| AUD-S2-12 | MENOR | Doble fuente de verdad y doble petición de municipios/sectores | `leak_report_controller.dart:99-128` vs `location_providers.dart` |
| AUD-S2-13 | MENOR | Código muerto: `DuplicateDialog`, `validateCanAddPhoto`, `LeakCommunityCopy.noLocation`, rama de error inalcanzable en la etapa de resultado | varios |
| AUD-S2-14 | MENOR | Cancelar el selector de fotos se presenta como error visible, contradiciendo el comentario del propio código | `photo_service.dart:40-43` |
| AUD-S2-15 | MENOR | Límite de 3 fotos hard-codeado en la UI y en el controlador, pese a `system_config.photo_limits` | `leak_report_screen.dart:350`, `leak_report_controller.dart:169` |
| AUD-S2-16 | MENOR | `Image.file` sin `cacheWidth`: decodifica hasta 3 imágenes a resolución completa | `leak_report_screen.dart:359-363` |
| AUD-S2-17 | MENOR | Android bloquea tráfico *cleartext*: la app no puede hablar con Supabase local por `http://` (el entorno que exigen los tests) | `android/app/src/main/AndroidManifest.xml` |
| AUD-S2-18 | MENOR | `audit_events.user_id` guarda `auth.uid()`, no `app_users.id`, y sin FK | `00010:281`, `00013:204-208` |
| AUD-S2-19 | MENOR | Aserción débil en la suite SQL (acepta dos desenlaces distintos) | `create_leak_report_test.sql:211-219` |

## 4. Hallazgos detallados

### AUD-S2-01 — BLOQUEANTE · La ruta de las fotos expone la identidad del reportante

**Evidencia.** `report_photos` es de lectura pública:

```sql
-- 00011_rls_reports.sql
create policy "Lectura pública de fotos de reportes"
  on public.report_photos for select to anon, authenticated using (true);
revoke all on public.report_photos from anon, authenticated;
grant select on public.report_photos to anon, authenticated;
```

Y su columna `storage_path` contiene el identificador de autenticación del creador:

```sql
-- 00012_storage_report_photos.sql (estructura de rutas, comentario normativo)
--   report_photos/{auth_user_id}/{upload_key}/{photo_uuid}.jpg
```

```dart
// leak_report_repository.dart:74
final path = '$_folder/$userId/$uploadKey/${photo.id}.jpg';   // $userId = session.user.id
```

Como PostgREST expone el esquema `public` (`config.toml` → `schemas = ["public", …]`), cualquier cliente con la clave pública puede ejecutar:

```
GET /rest/v1/report_photos?select=storage_path
```

y obtener `report_photos/<auth_user_id>/…` de **todos** los reportes.

**Impacto.** REQ-100 ("la identidad del reportante no es pública") queda incumplido: la identidad anónima persistente (REQ-090) es el `auth.uid()`, y ese UUID es directamente legible. Con él se puede: (a) agrupar todos los reportes de un mismo vecino, (b) deducir cuándo una misma persona reporta o deja de reportar (patrones de movimiento y de actividad), (c) cruzar esa identidad con `report_validations`… que está cerrada (lo cual evidencia la **incoherencia**: se protegió con esmero *quién valida* y se dejó abierto *quién reporta*). También contradice la propia promesa funcional "No muestra identidad del creador" (`FUNCTIONAL_SPEC.md` §4).

Agravante: es un fallo **server-side**, invisible para la app, y no está cubierto por ninguna prueba (`storage_report_photos_test.sql` prueba `storage.objects`, no la tabla `public.report_photos`).

**Recomendación (sin romper la app).** Reducir el `GRANT` a nivel de columna —`revoke all … ; grant select (report_id, mime_type, size_bytes, width, height, sort_order, created_at) on public.report_photos …`— o, mejor, retirar la lectura pública de la tabla y exponer el conteo/metadatos por una RPC (`get_leak_report_detail` ya devuelve `photo_count`). Si más adelante se publican binarios, la ruta debe dejar de contener el `auth.uid()` (por ejemplo `report_photos/{report_id}/{photo_id}.jpg`) o resolverse siempre por URLs firmadas server-side, como ya prevé `MIGRATION_NOTES.md`.

### AUD-S2-02 — IMPORTANTE · `created_by` legible por cualquier cliente

Mismo mecanismo: `grant select on public.reports` (todas las columnas) + política `using (true)`. `GET /rest/v1/reports?select=created_by` devuelve el `app_users.id` del autor de cada fuga. El comentario de la migración lo justifica ("`created_by` es un UUID de `app_users`, no un dato personal"), pero el UUID es un **identificador estable y correlacionable**: permite reconstruir la autoría y comparar vecinos entre sí aunque no resuelva a un nombre. `app_users.id` es además deducible como `auth_user_id` vía AUD-S2-01.

**Recomendación.** Mismo tratamiento: `grant select` por columnas, excluyendo `created_by`, y exponer `is_creator` solo por RPC (como ya se hace en `get_leak_report_detail`).

### AUD-S2-03 — IMPORTANTE · "Ubicación manual" no es selección en mapa

`REQUIREMENTS.md` REQ-021: "La ubicación puede proceder de GPS o **selección manual en mapa**". `FUNCTIONAL_SPEC.md` §3: "si falla o se deniega, permite seleccionar manualmente en mapa". La implementación abre un `AlertDialog` con dos `TextField` numéricos:

```dart
// leak_report_screen.dart:251-266
TextField(controller: latController, decoration: const InputDecoration(labelText: 'Latitud'), …)
TextField(controller: lngController, decoration: const InputDecoration(labelText: 'Longitud'), …)
const Text('Muy pronto podrás seleccionar el punto exacto en el mapa.', …)
```

El propio diálogo reconoce la carencia y el `MVP_PLAN` asigna MapLibre al Sprint 05, pero el requisito está redactado sin esa excepción. Riesgo adicional de calidad de datos: el backend solo valida rango (`INVALID_LOCATION`), sin *geofence* a Maneiro/Arismendi (`00010:83-89`), así que un usuario puede registrar una fuga en cualquier coordenada del planeta con fuente `MANUAL`.

**Recomendación.** Registrar la desviación de forma explícita (no solo en un comentario de código y un diálogo) y, hasta el Sprint 05, añadir al menos una validación geográfica razonable (bbox de Nueva Esparta) o exigir que el punto manual provenga de una búsqueda de sector.

### AUD-S2-04 — IMPORTANTE · El override de duplicado es pegajoso

```dart
// leak_report_controller.dart
bool _ignoreDuplicate = false;                       // :89  nunca se reinicia salvo invalidación del provider

Future<void> continueAsNewLeak() async {             // :244
  _ignoreDuplicate = true;
  …
  await submit();
}
```

`_ignoreDuplicate` se activa al pulsar "Es otra fuga" y **solo** se limpia cuando se invalida el provider al salir del flujo (`AppShell.resetLeakReportDraft`, `home_screen._openReport`). Dentro del flujo: tras el duplicado el usuario puede pulsar "Editar datos" (`leak_report_screen.dart:728-731`), **cambiar la ubicación/el sector** y volver a enviar; el envío viaja con `p_ignore_duplicate = true` y `create_leak_report` **omite por completo la detección de duplicados** (`00010:249`). Es decir: una confirmación dada para *un* candidato en *una* ubicación se reutiliza silenciosamente para otra.

**Impacto.** Contradice REQ-025 tal como está redactado ("permite ver/validar el existente **o** declarar que es otra fuga"): la declaración debe corresponder a la revisión que el usuario hizo. Se pueden crear reportes casi idénticos sin que el usuario vuelva a confirmarlo.

**Recomendación.** Reiniciar `_ignoreDuplicate = false` en cualquier mutación del borrador (`setManualLocation`, `requestGps`, `selectMunicipality`, `selectSector`, `removePhoto`) o, mejor, no mantenerlo como estado del controlador: enviarlo como parámetro explícito de `submit({bool ignoreDuplicate = false})` ligado a la revisión mostrada.

### AUD-S2-05 — IMPORTANTE · El duplicado no permite ver ni validar el existente

`UX_SPEC.md` §5 lista dos acciones: "**Ver reporte y validar**" y "Es otra fuga". La implementación ofrece "Es la misma: usar ese reporte" (`leak_report_screen.dart:682`) y "Es otra fuga" (:697). La primera ejecuta:

```dart
// leak_report_controller.dart:255-258
void useExistingReport() => state = state.copyWith(currentStep: ReportStep.result,
    message: 'Usaste el reporte existente. Puedes validarlo desde el mapa cuando esté disponible.');
```

No navega al candidato, ni permite validarlo, ni muestra sus fotos; envía al usuario a una función ("Mapa") que hoy es un `PlaceholderScreen`. La única vía real de validar es salir del flujo, ir a Inicio y encontrar la fuga en "Fugas cerca de ti" (junto a otras 19).

**Impacto.** REQ-025 y UX_SPEC §5 quedan cumplidos a medias: el sistema no bloquea (bien) pero tampoco ofrece la alternativa prometida. Impacto directo en la captura comunitaria de validaciones.

**Recomendación.** Añadir un botón "Ver y validar" que abra `LeakDetailScreen(reportId: candidate.id)` con el `id` que la respuesta `POSSIBLE_DUPLICATE` ya entrega (`PossibleDuplicateCandidate.id`), sin esperar al mapa.

### AUD-S2-06 — IMPORTANTE · "Reporte enviado" sin envío

```dart
// leak_report_screen.dart:787
final isError = state.submitState == ReportSubmitState.idle;
…
Text(state.submitState == ReportSubmitState.done ? 'Reporte enviado' : 'No se pudo enviar', …)  // :800-805
```

En la ruta "usar el reporte existente", `submitState` sigue valiendo `duplicate` (nunca pasó por `done`), por lo que `isError == false` y la pantalla muestra el icono verde de éxito y el título **"Reporte enviado"**, aunque no se creó ningún reporte. El cuerpo del mensaje sí aclara ("Usaste el reporte existente…"), pero el encabezado contradice `FUNCTIONAL_SPEC.md` §12 ("no se debe mostrar 'enviado' hasta que el backend confirme").

**Recomendación.** Derivar el título del `outcome`/paso real (tres estados: creado, duplicado-aceptado, error) en lugar de inferirlo de `submitState`.

### AUD-S2-07 — IMPORTANTE · La distancia mostrada puede no ser la menor

```sql
select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'sector_id', r.sector_id,
    'distance_meters', round(r.distance)::int, 'created_at', r.created_at
  ) order by r.distance), '[]'::jsonb)
into v_candidates
from (
  select r.id, r.sector_id, r.created_at, extensions.st_distance(r.location, v_point) as distance
  from public.reports r
  where r.status = 'ACTIVE' and r.created_at >= now() - make_interval(hours => v_window_hours)
    and extensions.st_dwithin(r.location, v_point, v_radius_m)
  limit 5                      -- ← sin ORDER BY: subconjunto arbitrario
) r;
```

El `ORDER BY` exterior ordena solo lo que el `LIMIT 5` haya devuelto; el subconjunto lo elige el planificador (normalmente por orden físico/GIST). Con más de 5 candidatos dentro del radio, el más cercano puede quedar fuera. La UI usa `candidates.first.distanceMeters` (`leak_report_controller.dart:287-288`), así que el mensaje al usuario ("Ya existe un reporte de fuga cerca (N m)") puede reportar una distancia mayor que la real.

**Recomendación.** Mover el `limit 5` **después** del `order by r.distance` (subconsulta ordenada + límite externo), o eliminar el límite y agregar todo lo que caiga en el radio.

### AUD-S2-08 — IMPORTANTE · Sin miniaturas y con dimensiones siempre nulas

`FUNCTIONAL_SPEC.md` §3 exige "miniaturas" y `DATA_MODEL.md` define `thumbnail_path`. La app nunca genera miniaturas:

```dart
// photo_service.dart:80-90 — no se produce thumbnail
return PreparedPhoto(id: …, originalPath: path, compressedPath: compressed.path,
  mimeType: kReportPhotoContentType, sizeBytes: sizeBytes, width: 0, height: 0);
```

El cliente nunca envía `thumbnail_path` (`leak_report_repository.dart:83-90`), por lo que `report_photos.thumbnail_path` queda siempre `NULL`. Además:

```dart
// photo_service.dart:86-88
// "Las dimensiones exactas las determina el servidor a partir del binario;
//  aquí se dejan en 0 (sin metadatos inventados)."
```

…pero el servidor **no** las determina: solo las anula.

```sql
-- 00010:215-216
'width',  case when v_width  > 0 then v_width  end,
'height', case when v_height > 0 then v_height end,
```

**Impacto.** `width`/`height` quedan `NULL` en el 100% de los casos: el comentario promete algo que no ocurre y el modelo de datos pierde información que un sprint de mapa/detalle puede necesitar (orientación, relación de aspecto). La ausencia de miniaturas contradice el spec funcional.

**Recomendación.** O generar la miniatura en el cliente (una llamada más a `compressAndGetFile` con `maxWidth`/`maxHeight` reducidos) o declarar formalmente su exclusión; y corregir el comentario de `photo_service.dart` o implementar la lectura real de dimensiones en el cliente (`decodeImageFromList`).

### AUD-S2-09 — IMPORTANTE · La cámara no es alcanzable

`FUNCTIONAL_SPEC.md` §3: "Fotos: mínimo 1, máximo 3; **cámara o galería**". `photo_service.dart` soporta ambas (`fromCamera ? ImageSource.camera : ImageSource.gallery`), pero la única llamada en la UI es:

```dart
// leak_report_screen.dart:390 — la tarjeta "+" del grid
onTap: () => controller.addPhoto(fromCamera: false),
```

No hay botón ni *bottom sheet* que ofrezca la cámara (verificado por `grep`: `fromCamera` solo aparece en la firma y en la llamada con `false`). Igualmente, `android.permission.CAMERA` no está declarado (no es imprescindible con `image_picker`, que delega en la app de cámara, pero conviene revisarlo junto con el Sprint 08).

**Recomendación.** Añadir la elección (cámara/galería) al pulsar "+" — es el caso de uso principal de una app de fugas callejeras.

### AUD-S2-10 — MENOR · `description` sin validación en la RPC

`reports.description` tiene `check (char_length(description) <= 500)` (`00007`), pero `create_leak_report` inserta `nullif(trim(p_description), '')` sin comprobar la longitud (`00010:255-263`). Un cliente que llame a la RPC con 501 caracteres provoca `check_violation` (23514) → `PostgrestException` → `QueryException` ("No pudimos registrar tu reporte. Verifica tus datos e intenta de nuevo."), en lugar del `VALIDATION_ERROR` con mensaje específico que define `API_SPEC.md` §3. La app sí acota con `maxLength: 500` (`leak_report_screen.dart:505`), así que solo se alcanza por API directa o por un futuro cliente.

### AUD-S2-11 — MENOR · `LIKE` con comodín implícito

```sql
-- 00010:158
if v_path not like 'report_photos/' || v_auth_uid::text || '/%' then
```

En `LIKE`, `_` coincide con cualquier carácter: el prefijo `report_photos` es un patrón, no una cadena literal. No es explotable hoy (la política de Storage exige `(storage.foldername(name))[1] = 'report_photos'` **exacto** y el `SELECT` de `storage.objects` exige `owner = auth.uid()`), pero es una comprobación de seguridad escrita de forma laxa.

**Recomendación.** `starts_with(v_path, 'report_photos/' || v_auth_uid::text || '/')` o `split_part(v_path,'/',2) = v_auth_uid::text`.

### AUD-S2-12 — MENOR · Doble fuente de verdad y doble petición

`LeakReportController` carga municipios en `build()` (`:99-114`) y sectores en `selectMunicipality` (`:116-128`), guardando `state.municipalities`, `state.sectors`, `state.municipalityError`, `state.sectorsError`. La UI **no usa nada de eso**: `DataStepView` y `_SectorsDropdown` consumen `municipalitiesProvider` y `sectorsProvider` (`location_providers.dart`). Resultado: al abrir el flujo se piden los municipios dos veces y al elegir municipio los sectores dos veces. Solo `state.municipalities` se lee, para mostrar el nombre en la revisión (`leak_report_screen.dart:628-633`), lo que además puede quedar vacío si esa carga falló mientras la del provider sí funcionó.

**Recomendación.** Eliminar `_loadMunicipalities`/`loadSectors` y los campos asociados, o retirar los providers y consumir el estado del controlador (una sola fuente).

### AUD-S2-13 — MENOR · Código muerto

| Símbolo | Ubicación | Observación |
|---|---|---|
| `DuplicateDialog` | `leak_report_screen.dart:745-777` | Clase completa sin ninguna referencia (el duplicado se resuelve inline en `ReviewStepView`). Duplica lógica y copy. |
| `validateCanAddPhoto()` | `photo_limits.dart:51-57` | Solo la invoca su propio test; el controlador usa `if (photos.length >= 3)`. |
| `LeakCommunityCopy.noLocation` | `leak_community_microcopy.dart:21` | Sin uso. |
| Rama `'No se pudo enviar'` | `leak_report_screen.dart:803` | Inalcanzable: los errores de `submit()` vuelven a `idle` **sin** cambiar de paso (`leak_report_controller.dart:297-307`), así que el usuario permanece en "Revisar". |

### AUD-S2-14 — MENOR · La cancelación se muestra como error

```dart
// photo_service.dart:40-43
if (picked == null) {
  // Cancelación del usuario: no es un error visible.
  throw const PhotoValidationException('No se seleccionó ninguna foto.');
}
```

`addPhoto` captura y publica el mensaje (`leak_report_controller.dart:184-188`), y `PhotosStepView` lo pinta en un `StatusBanner` rojo (`:328-331`). El comentario declara una intención que el propio código incumple: cancelar no debería producir un banner de error.

### AUD-S2-15 — MENOR · Límites hard-codeados

`system_config.photo_limits.max_count` es la fuente configurable (y la RPC la respeta), pero la UI fija el 3 en cuatro sitios: `photos.length >= 3` (`controller:169`), `photos.length < 3` (`screen:350`), `'Fotos agregadas: ${photos.length} de 3'` (`screen:336`) y `kReportPhotoMaxCount = 3` (`photo_limits.dart:11`, que ni se usa en el controlador). `REVIEW_CHECKLIST.md`: "No hard-codeó configuración que debe ser configurable". Si en el Sprint 07 se cambia el límite en `system_config`, la UI seguirá diciendo 3.

### AUD-S2-16 — MENOR · Decodificación de imágenes a resolución completa

```dart
// leak_report_screen.dart:359-363
child: Image.file(File(photo.compressedPath), fit: BoxFit.cover),
```

Sin `cacheWidth`/`cacheHeight`. Tres JPEG de 1920 px se decodifican a tamaño completo para pintarse en celdas de una grilla de 3 columnas (~120 dp): memoria de GPU/CPU innecesaria en equipos de gama baja, que es el público objetivo (`PROJECT_BRIEF.md`: conectividad y equipos limitados).

### AUD-S2-17 — MENOR · Supabase local inalcanzable por HTTP en Android

`main/AndroidManifest.xml` no define `usesCleartextTraffic` ni un `network_security_config` (no existe `android/app/src/debug/res/`). Con `targetSdk` moderno, Android bloquea `http://` por defecto. Consecuencia: la app no puede hablar con el Supabase local (`http://10.0.2.2:54321`) que exigen `supabase/tests/*.sh` y el procedimiento de `SETUP.md`; solo funciona apuntando a un proyecto remoto `https://`. No está documentado en `README.md`/`SETUP.md`.

**Recomendación.** Añadir un `network_security_config` limitado a `localhost`/`10.0.2.2` **solo en debug**, y documentarlo.

### AUD-S2-18 — MENOR · Auditoría con identificador inconsistente

`audit_events.user_id` recibe `v_auth_uid` (el `auth.users.id`) tanto en `create_leak_report` (`00010:281`) como en las RPC de Sprint 03, mientras que `reports.created_by` y `report_validations.user_id` usan `app_users.id`. La columna no tiene FK (`00009:27`), así que no hay validación de integridad. `REQ-094` ("permitir detección posterior de actividad anómala") se ve afectado: cruzar auditoría con reportes exige un salto extra y no está documentado.

### AUD-S2-19 — MENOR · Aserción de prueba ambigua

```sql
-- create_leak_report_test.sql:211-219 (caso "3b")
begin
  insert into public.report_photos (…) values (… sort_order 1);
  raise exception 'FALLO 3b: sort_order duplicado aceptado';
exception when unique_violation then
  raise notice 'OK 3b: sort_order duplicado rechazado';
when others then
  raise notice 'OK 3b: rechazado por el límite de fotos antes del unique';
end;
```

El caso declara éxito ante **cualquiera** de los dos desenlaces, de modo que no demuestra que el `UNIQUE (report_id, sort_order)` funcione: si el límite de 3 fotos cambiara, la prueba seguiría pasando en verde sin comprobar nada.

## 5. Trazabilidad requisito → implementación (Sprint 02)

| Requisito | Implementación | Estado |
|---|---|---|
| REQ-020 Fuga con ubicación, sector, municipio, descripción opcional y 1–3 fotos | `00007`+`00008`+`create_leak_report`; UI en 5 etapas | ✅ Cumple (fotos reales, 1–3, descripción opcional) |
| REQ-021 Ubicación por GPS **o selección manual en mapa** | GPS real (`geolocator`) + diálogo lat/lng | ⚠️ **Parcial** (AUD-S2-03) |
| REQ-022 Fuente registrada GPS/MANUAL | `location_source` CHECK + `LocationSource.wireName` | ✅ Cumple |
| REQ-023 Fotos validadas, comprimidas y almacenadas de forma segura | Compresión a JPEG (elimina EXIF), validación cliente+servidor contra el binario real, bucket privado por carpeta | ✅ Cumple (excelente); ⚠️ sin miniaturas (AUD-S2-08) y con fuga de identidad (AUD-S2-01) |
| REQ-024 Backend revisa duplicados antes de crear | `POSSIBLE_DUPLICATE` calculado server-side antes del `INSERT` | ✅ Cumple |
| REQ-025 El duplicado no bloquea: ver/validar el existente o declarar otra fuga | `POSSIBLE_DUPLICATE` + `p_ignore_duplicate` | ⚠️ **Parcial** (AUD-S2-04, AUD-S2-05) |
| REQ-030 Radio 50 m / ventana 48 h configurables | `system_config.duplicate_detection` + respaldo en la función; `st_dwithin`/`make_interval` | ✅ Cumple |
| REQ-031 Devolver candidato(s) y distancia | `candidates[{id, sector_id, distance_meters, created_at}]` con `round()` | ⚠️ Cumple con riesgo de distancia no mínima (AUD-S2-07) |
| REQ-032 Sin reconocimiento de imágenes | No hay IA de visión | ✅ Cumple |
| REQ-100 Identidad del reportante no pública | `get_leak_report_detail` **no** expone `created_by` (acierto), pero `reports.created_by` y `report_photos.storage_path` son legibles | ❌ **Incumple** (AUD-S2-01, AUD-S2-02) |
| REQ-101 Ubicación pública = la de la fuga | Solo se persiste la ubicación de la fuga, no la del dispositivo más allá de la fuga | ✅ Cumple |
| REQ-102 Sin nombre/teléfono/correo/perfil | No hay campos personales; sin EXIF en las fotos | ✅ Cumple |
| REQ-173 / ARCHITECTURE §10 sin infraestructura nueva | RPC SQL protegida en vez de Edge Functions (documentado en `MIGRATION_NOTES`) | ✅ Cumple y está justificado |
| API_SPEC §6 "no enviar binarios dentro de la función" | Binarios van a Storage; la RPC persiste referencias y las valida | ✅ Cumple |

## 6. Definition of Done (MVP_PLAN §Definition of Done)

| # | Elemento | Estado |
|---|---|---|
| 1 | Código | ✅ |
| 2 | Migración | ✅ (00007–00012) |
| 3 | RLS/seguridad | ❌ Privacidad incumplida en lectura (AUD-S2-01/02); el resto del modelo de escritura es muy sólido |
| 4 | Tests | ⚠️ Cobertura Dart buena y verde; suites SQL/E2E **no ejecutadas aquí**; una aserción débil (AUD-S2-19) |
| 5 | UX/error states | ⚠️ Hay mensajes y reintentos, pero "Reporte enviado" falso (AUD-S2-06) y cancelación tratada como error (AUD-S2-14) |
| 6 | Documentación | ⚠️ `MIGRATION_NOTES` §Sprint 02 es detallado y honesto; la desviación del mapa (AUD-S2-03) no está declarada como tal |
| 7 | Verificación manual | ⚠️ Imposible de reproducir con datos reales sin sectores (AUD-S1-02) |

## 7. Aspectos verificados sin hallazgos (destacados)

- **Detección de duplicados correcta en lo esencial:** `status = 'ACTIVE'`, `created_at >= now() - make_interval(hours => v_window_hours)` y `st_dwithin(...v_radius_m)` sobre `geography` (metros reales, no grados). Umbrales leídos de `system_config` con respaldo 50/48.
- **Validación de fotos contra el binario real:** la RPC consulta `storage.objects` (existencia, `owner_id`, `mimetype`, `size`) y **descarta lo que declare el cliente** para `mime_type`/`size_bytes`; verifica pertenencia por carpeta, MIME permitido y tamaño máximo desde `system_config`. Es el punto más fuerte del sprint.
- **Anti-reutilización:** `unique (storage_path)` en `report_photos` + comprobación explícita en la RPC impiden asociar el mismo binario a dos reportes.
- **Límite de 3 fotos a nivel de tabla:** trigger `enforce_report_photo_limit` con `pg_advisory_xact_lock(hashtextextended(report_id))`, que evita la carrera entre inserciones concurrentes — buen detalle.
- **Atomicidad:** el reporte y sus fotos se insertan en una sola transacción; si algo falla, no queda reporte huérfano.
- **Limpieza de huérfanos:** `_cleanupUploaded()` borra los temporales cuando la RPC falla, cuando hay rechazo o cuando hay `POSSIBLE_DUPLICATE`, con reintento y **error visible** si no puede limpiar. Coherente con `MIGRATION_NOTES` y cubierto por tests.
- **RLS de escritura:** `reports` y `report_photos` con `revoke all` + `grant select` únicamente; escritura solo por RPC `security definer`. `audit_events` sin lectura.
- **Errores del backend con mensaje en español listo para UI** y traducción 1:1 a excepciones de dominio en el repositorio (`_parseOutcome`), incluida la no-anunciación de éxito ante `UNAUTHORIZED`.
- **Sin `service_role` en el cliente** en ninguna ruta; credenciales solo por `--dart-define`.
- El doble envío dentro de una sesión está mitigado en la UI (`_running`/`submitting`) y, en el backend, por la detección de duplicados; no se encontró una ruta simple de duplicación silenciosa.

## 8. Veredicto Sprint 02

**Funcionalmente rico y con un backend de validación por encima de la media, pero con un defecto de privacidad que debe corregirse antes de cualquier uso real y tres desviaciones de requisitos explícitos.**

- **Bloqueante:** AUD-S2-01 — la identidad del reportante es pública a través de `report_photos.storage_path`, y el arreglo es pequeño (GRANT por columnas o retirar la lectura pública de la tabla).
- **Importantes:** AUD-S2-02 (mismo origen), AUD-S2-03 (ubicación manual sin mapa), AUD-S2-04 (override de duplicado pegajoso), AUD-S2-05 (no se puede ver/validar el candidato), AUD-S2-06 ("Reporte enviado" falso), AUD-S2-07 (distancia posiblemente errónea), AUD-S2-08 (sin miniaturas y dimensiones nulas), AUD-S2-09 (sin cámara).
- La robustez del camino de escritura (RPC + Storage + limpieza + auditoría) contrasta con la laxitud del camino de lectura (RLS `using (true)` con `GRANT` de tabla completa), que es donde se concentran los hallazgos de seguridad.
- Recomendación de orden de corrección: AUD-S2-01/02 → AUD-S2-06 → AUD-S2-04/05 → el resto.

## 9. Cierre de hallazgos (sesión de corrección)

**Fecha de cierre:** 2026-09-11 · **Commit:** `fix: close sprint 02 audit findings`
(no `git push`). **Migración aplicada:** `20260911000016_audit_sprint02_fixes.sql`.

### 9.1 Estado por hallazgo

| ID | Severidad | Cierre | Evidencia |
|---|---|---|---|
| AUD-S2-01 | BLOQUEANTE | `revoke all` + `grant select (columnas sin identidad)` en `reports`; se excluye `created_by` | `create_leak_report_test.sql` → `OK 4a-priv`, `OK 9b`, `OK 9c` |
| AUD-S2-02 | IMPORTANTE | ídem (misma causa) | `OK 4a-priv`, `OK 4d-priv` |
| AUD-S2-03 | IMPORTANTE | Desviación **documentada**: manual = coordenadas hasta Sprint 05 (MapLibre). No se inventa bbox (prohibido). Valor de rango `INVALID_LOCATION` conservada | `MIGRATION_NOTES.md` §Sprint 02, `FUNCTIONAL_SPEC.md` §3 |
| AUD-S2-04 | IMPORTANTE | `submit({ignoreDuplicate})` es argumento, no estado del controlador; al reenviar sin "Es otra fuga" viaja `false` | `leak_report_duplicate_flow_test.dart` (AUD-S2-04, AUD-S2-04/REQ-025 control) |
| AUD-S2-05 | IMPORTANTE | Botón "Ver y validar" → `LeakDetailScreen(reportId: candidate.id)` con el `id` de la RPC | `leak_report_duplicate_flow_test.dart` (AUD-S2-05) |
| AUD-S2-06 | IMPORTANTE | `ResultStepView` deriva título/icono del `outcome` real; nunca "Reporte enviado" si `submitState != done` | `leak_report_duplicate_flow_test.dart` (AUD-S2-06) |
| AUD-S2-07 | IMPORTANTE | `LIMIT 5` sobre subconsulta ordenada por distancia; `candidates.first` = más cercano | `create_leak_report_test.sql` → `OK 10` |
| AUD-S2-08 | IMPORTANTE | Exclusión honesta de miniaturas; `width`/`height` solo si el binario los aporta; comentario de `photo_service.dart` corregido | `photo_service.dart`, `00016` |
| AUD-S2-09 | IMPORTANTE | "+" ofrece cámara **o** galería (reusa `addPhoto(fromCamera:)`) | `leak_report_screen.dart` |
| AUD-S2-10 | MENOR | `char_length(description) > 500` → `VALIDATION_ERROR` | `00016` |
| AUD-S2-11 | MENOR | pertenencia con `starts_with` (sin `_` comodín) | `00016` |
| AUD-S2-12 | MENOR | municipios/sectores solo en `municipalitiesProvider`/`sectorsProvider` | `leak_report_controller.dart` |
| AUD-S2-13 | MENOR | `DuplicateDialog` muerto eliminado; símbolos sin uso retirados donde el analyzer lo confirma | `leak_report_screen.dart` |
| AUD-S2-14 | MENOR | cancelar el picker no muestra banner rojo | `leak_report_controller.dart` |
| AUD-S2-15 | MENOR | UI/controlador usan `kReportPhotoMaxCount` (sin "3" mágico) | `photo_limits.dart` |
| AUD-S2-16 | MENOR | `Image.file(..., cacheWidth:)` en la grilla | `leak_report_screen.dart` |
| AUD-S2-17 | MENOR | `usesCleartextTraffic`/network_security_config solo en `debug` para localhost/10.0.2.2; documentado en `SETUP.md` | `android/app/src/debug/...` |
| AUD-S2-18 | MENOR | `audit_events.user_id` NO migrado (riesgo); inconsistencia documentada | `MIGRATION_NOTES.md` §Sprint 02 |
| AUD-S2-19 | MENOR | aserción 3b del test SQL endurecida (sin `when others` = éxito) | `create_leak_report_test.sql` |

### 9.2 Preservado (no se reescribió el flujo)

- RPC `create_leak_report` (`security definer`, `search_path = ''`): **misma firma**
  y mismos `status_code`. Se hizo `CREATE OR REPLACE` para el `LIMIT 5` ordenado,
  `VALIDATION_ERROR` por longitud y `starts_with`.
- Validación de fotos contra `storage.objects`, duplicados 50 m/48 h vía
  `system_config`, cleanup de huérfanos y `p_ignore_duplicate` como confirmación
  explícita (REQ-025).

### 9.3 Verificación real ejecutada

- `flutter analyze` → **No issues found!**
- `flutter test test/features/leaks/` → **77/77 en verde** (incluye 4 nuevos
  `leak_report_duplicate_flow_test.dart`: AUD-S2-04, AUD-S2-04/REQ-025 control,
  AUD-S2-05, AUD-S2-06).
- SQL/E2E contra `supabase_db_gota` (Docker activo):
  - `create_leak_report_test.sql`: OK 1…OK 10, privacidad `4a-priv`/`4a-priv2`/
    `4d-priv`/`9b`/`9c`/`9d`/`9e`, **sin FALLO**.
  - `storage_report_photos_test.sql`: OK 0…OK 3b, **sin FALLO**.
  - `create_leak_report_e2e.sh`: **todas las pruebas pasaron** (EXIT 0).
  - `community_flow_e2e.sh`: **todas pasaron** (EXIT 0), incluido
    "el listado con sector/municipio embebidos funciona con RLS (ok)".

### 9.4 Confirmación de privacidad (AUD-S2-01/02)

`authenticated` y `anon` **no** pueden `select created_by from reports` ni
`select storage_path from report_photos` (el test SQL lo fuerza y cae en
`insufficient_privilege`). El listado embebido de Inicio (con
`sectors(name)`/`municipalities(name)`) sigue funcionando tras el `GRANT` por
columnas — verificado por `community_flow_e2e.sh`.

### 9.5 Deudas dejadas (fuera de Sprint 02)

1. Rutas de Storage contienen `auth.uid()`
   (`report_photos/{auth_user_id}/…`): cambiarlas o publicar solo por URLs firmadas
   server-side queda para el sprint de fotos públicas.
2. MapLibre / selección en mapa: Sprint 05.
3. `plist` de permiso de cámara iOS: no tocado (queda documentado; `image_picker`
   delega en la app de cámara del sistema).
4. `audit_events.user_id` sigue en `auth.uid()` (inconsistencia con `app_users.id`
   documentada; migración diferida por riesgo).

