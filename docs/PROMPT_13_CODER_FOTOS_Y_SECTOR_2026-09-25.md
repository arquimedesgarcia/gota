# PROMPT 13 — Coder: fotos comunitarias + rescope del Sector de Interés (2026-09-25)

Eres el codificador de la iteración. Implementa EXACTAMENTE los dos cambios de
este documento en el repo Gota (Flutter + Supabase). Lee antes:
`docs/PROMPT_12_FOTOS_COMUNITARIAS_2026-09-25.md` (diseño de fotos, APROBADO),
`docs/ARCHITECTURE.md` §4 (la UI nunca consulta Supabase directo),
`docs/API_SPEC.md` (contrato de lectura/privacidad), `docs/REVIEW_CHECKLIST.md`.

Cambios aditivos, en rama nueva `feat/photos-and-sector-rescope` desde `main`.

---

## PARTE A — Fotos comunitarias (PROMPT 12, aprobado)

Límite: **2 fotos por reporte** (decisión del dueño). Alinear el repositorio a
ese límite: `photoPayload` hoy admite hasta 3 — cortar a 2 en
`leak_report_repository.dart` coherente con `kReportPhotoMaxCount`.

### A1. Backend (una migración SQL nueva, número siguiente al último)

1. RPC `get_report_photos(p_report_id uuid)`:
   - `SECURITY DEFINER`, `SET search_path = public, pg_temp`, `REVOKE EXECUTE
     FROM anon` y `GRANT TO authenticated` (igual que las demás RPC).
   - Rechaza (código `NOT_FOUND`) si el reporte no existe.
   - Rechaza (`FORBIDDEN`) si `app_users.is_blocked` del llamador.
   - Rate limit con los helpers existentes de `rate_limits` (mismo patrón que
     `validate_leak`).
   - Por cada foto del reporte (orden `sort_order`): `id`, `sort_order`,
     `width`, `height`, y signed URLs temporales (`storage.create_signed_url`,
     TTL 900 s) para `storage_path` y para `thumbnail_path` **solo si no es
     NULL** (`thumbnail_url: null` cuando falte). NUNCA devolver
     `storage_path` crudo.
2. NO conceder SELECT sobre `report_photos`: la RPC es el único camino.
3. Tests SQL en `supabase/tests/` (extender `storage_report_photos_test.sql` o
   nuevo archivo): anon bloqueado, reporte inexistente, usuario bloqueado, rate
   limit, formato de respuesta (URLs firmadas presentes, `storage_path`
   ausente), y que las políticas de Storage NO se ampliaron a escritura.

### A2. Cliente Flutter

1. `photo_limits.dart`: agregar `kReportPhotoThumbMaxDimension = 128` y
   `kReportPhotoThumbQuality = 70`.
2. `photo_service.dart`: tras la compresión principal (1280px), segunda pasada
   a 128px → `PreparedPhoto` gana `thumbnailPath` + `thumbnailBytes`. EXIF
   irrelevante en thumb (misma fuente sin EXIF).
3. `draft_photo_store.dart`: persistir ambas (thumb como `{photoId}_thumb.jpg`
   en el mismo directorio durable); `clearAll` borra ambas.
4. `leak_report_repository.dart`: subir thumb a
   `$_folder/$userId/$uploadKey/${photo.id}_thumb.jpg` y agregar
   `'thumbnail_path'` al `photoPayload`. Si la subida del thumb falla, fallar
   igual que la principal (misma limpieza).
5. Nuevo `leak_photo_repository.dart` (features/leaks/data): llama
   `get_report_photos`, expone `List<LeakPhoto>` (domain: id, sortOrder,
   width, height, url, thumbnailUrl). Renovar la URL si expira en <2 min.
6. UI:
   - `leak_detail_screen.dart`: carrusel horizontal de fotos (miniatura si hay
     thumb, si no la foto completa redimensionada); tap → visor a pantalla
     completa con PageView y zoom básico. Estados: loader por imagen, error
     con reintentar, vacío (0 fotos) no renderiza la sección. Sin fotos no
     rompe el flujo existente de validar/confirmar.
   - `leak_summary_tile.dart`: si `photo_count > 0` (ya llega por
     `get-leak-report-detail`), reemplazar el placeholder `_LeakThumbnail`
     por la miniatura real; caché en disco (`cached_network_image`; agregar
     la dependencia, justificar en el PR si eliges otra). El placeholder
     queda para `photo_count == 0`.
   - **Mapa: sin cambios** (placeholders quedan).
7. Reportes antiguos sin thumb: detalle funciona igual (usa foto completa);
   no retrogenerar thumbs.

---

## PARTE B — Rescope del Sector de Interés en Home

Estado actual: `communitySummaryProvider` (tarjeta "Hoy en tu comunidad") y
`sectorWaterStatusProvider` (estado del agua) filtran ambos por
`preferredSectorId`. Cambio deseado:

1. **Los conteos comunitarios pasan a ser SIEMPRE globales** (cobertura del
   piloto): quitar `sectorId` de la llamada `todaySummary(...)` en
   `communitySummaryProvider`. `todaySummary` conserva su parámetro (no
   romper tests); simplemente ya no se le pasa sector desde Home.
2. **El filtro por sector queda SOLO en el estado del agua**
   (`sectorWaterStatusProvider`): sin cambio de consulta.
3. **Estado del agua sin sector seleccionado**: cuando
   `prefs?.preferredSectorId == null` (o el título actual sería "Sin
   información del agua" por falta de datos PERO el usuario no tiene sector),
   mostrar en la tarjeta el mensaje **"Selecciona tu sector para ver el estado
   del agua en tu zona"** con estilo accionable (color accent, icono chevron o
   similar del design system). Toda la tarjeta es tappable →
   `Navigator.push(MaterialPageRoute(builder: (_) => const
   SectorSelectionScreen()))` (mismo patrón que `settings_screen.dart:229`).
   Al volver con sector seleccionado, el provider se refresca (invalidar
   `sectorWaterStatusProvider` y `notificationPreferencesProvider` en
   `.then()` del push si hace falta).
4. El encabezado de la tarjeta de conteos pasa a decir siempre "Cobertura del
   piloto" (hoy alterna con `sectorNameProvider`).
5. Revisar copy: los textos de tarjetas viven en las clases `*Copy` del
   proyecto — agregar los nuevos ahí, no literales en el widget.

---

## Calidad (bloqueante, no negociable)

- `flutter analyze` sin issues; `flutter test` en verde. Tests nuevos:
  - Foto: thumb generado dentro de límites, payload con `thumbnail_path`,
    repositorio de fotos maneja expiración, widget del detalle con/sin fotos
    (contract test con `MockClient` contra `SupabaseClient` real, no fakes que
    devuelvan escalares).
  - Rescope: conteos globales (sin filtro de sector), tarjeta de agua con
    sector (datos), sin sector (CTA "Selecciona tu sector") y navegación.
- RLS: re-ejecutar con `ON_ERROR_STOP=1` los tests SQL de storage y rls.
- `docs/API_SPEC.md` y `docs/DATA_MODEL.md`: documentar la nueva RPC y el
  contrato de `thumbnail_path` (camino RPC único se mantiene).
- `docs/UX_SPEC.md`: anotar el nuevo comportamiento de la tarjeta de agua.

## Entregable

- PR con: migración SQL + tests, código Flutter, docs actualizados.
- En la descripción del PR: lista de decisiones tomadas (dependencia de cache
  elegida, etc.) y evidencia de tests ejecutados.
- NO tocar: `created_by`, grants de `report_photos`, políticas de escritura de
  Storage, ni el mapa.
