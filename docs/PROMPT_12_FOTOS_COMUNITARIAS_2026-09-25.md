# PROMPT 12 — Fotos comunitarias: leer fotos de cualquier reporte (2026-09-25)

## Objetivo

Que cualquier usuario autenticado pueda ver las fotos de un reporte de fuga en
**Detalle de fuga** (y la lista de reportes de su sector), para validar si es
la misma fuga y dar contexto visual. **Fuera de alcance en esta etapa:**
galería/fotos en el mapa (el pin sigue con placeholder) y subida de fotos por
terceros.

## Estado actual (verificado en código)

- Fotos: máx 2/reporte (nota: `kReportPhotoMaxCount = 2` cliente, servidor
  autoridad; `photoPayload` admite hasta 3 — aclarar con dueño), JPEG 1280px
  q75, EXIF borrado, ~150-250 KB/foto.
- Bucket privado `report-photos`, RLS solo carpeta propia
  `report_photos/{auth.uid()}/...`.
- `report_photos` **sin** grant SELECT a cliente (AUD-S2-01/02). `thumbnail_path`
  existe en el modelo pero nunca se llena.
- Cliente no descarga nada: miniaturas de mapa y lista son placeholders.

## Decisión de privacidad (a confirmar con dueño del producto)

1. **Las fotos pasan a ser visibles para cualquier usuario autenticado** del
   sistema, asociadas al reporte. El EXIF GPS ya se elimina en el pipeline, así
   que no exponen nada extra; la ubicación ya es visible en el reporte.
2. RLS del bucket: agregar política `SELECT` sobre
   `report_photos/{uid}/{reportKey}/*.jpg` NO es suficiente por sí sola — la
   asociación reporte↔foto vive en `report_photos`, que sigue sin grants.

## Diseño recomendado: RPC + signed URLs (no bucket público)

Nada de bucket público: preserva el patrón "cliente nunca lee tablas de
dominio directo" (API_SPEC.md) y permite revocación/moderación central.

### Backend (migración única)

1. **RPC `get_report_photos(p_report_id uuid)`** (SECURITY DEFINER, search_path
   fijo, con `revoke from anon`):
   - Verifica que `p_report_id` exista (y opcionalmente que el usuario no esté
     bloqueado: `app_users.is_blocked`).
   - Devuelve por foto: `id`, `sort_order`, `width`, `height`, y **una signed
     URL temporal** (`storage.create_signed_url`, TTL 15 min) para
     `storage_path` y — cuando exista — `thumbnail_path`.
   - Rate limit igual que las demás RPCs (tabla `rate_limits`).
   - Fotos de reportes RESOLVED: se devuelven igual (histórico/entretenimiento),
     decidido aquí para no fragmentar la API.
2. **RLS/GRANT**: no se concede SELECT sobre `report_photos`; la RPC es el único
   camino (mismo contrato que `get-leak-report-detail`).
3. **Thumbnails**: trigger o paso en `create_leak_report` NO puede generar
   imágenes server-side (sin extensión de imágenes en Supabase). Opciones:
   - **Opción A (elegida)**: el cliente genera la miniatura (128px, q70,
     ~10-20 KB) en el mismo pase de compresión existente (`photo_service.dart`),
     la sube a `.../{photoId}_thumb.jpg` y envía `thumbnail_path` en
     `p_photos`. `photo_limits.dart`: agregar
     `kReportPhotoThumbMaxDimension = 128`.
   - Opción B (descartada etapa 1): Edge Function con supabase/storage
     transform — requiere plan Pro y adds-ons.

### Cliente (Flutter)

1. `PhotoService.pickAndPrepare`: segunda pasada de compresión a 128px thumb;
   `PreparedPhoto` gana `thumbnailPath`. `DraftPhotoStore` copia ambas.
2. `SupabaseLeakReportRepository.createReport`: sube thumb junto a la foto,
   agrega `'thumbnail_path'` a `photoPayload`.
3. Nuevo `LeakPhotoRepository.getPhotos(reportId)` (usa la RPC, renueva URL si
   expira > 2 min antes).
4. UI:
   - `LeakDetailScreen`: carrusel/galería horizontal con las fotos (tap abre
     visor a pantalla completa), loader por imagen, fallback si la URL expiró.
   - Lista de reportes (`leak_summary_tile.dart`): reemplazar placeholder de
     `_LeakThumbnail` por la miniatura real si `photo_count > 0` (el conteo ya
     llega por `get-leak-report-detail`). Cargar thumb bajo demanda y cachear
     en disco (`cached_network_image` o equivalente).
   - Mapa: **sin cambios** (placeholder queda).
5. Fotos viejas sin thumb: el detalle muestra la foto completa redimensionada;
   no se retrogeneran thumbs (población piloto pequeña, opcional script).

## Presupuesto (por qué esto no duele)

- Subida: +15 KB por foto por el thumb → despreciable.
- Almacenamiento: ~0,8 GB/año con 100 usuarios activos (free tier Supabase
  alcanza holgado).
- Bajada: thumbs ~15 KB; solo cargan al abrir detalle/lista, con caché en
  disco. 10 vistas/reporte/mes × 100 usuarios ≈ 0,25 GB/mes. Fotos completas
  (~200 KB) solo en el visor bajo tap explícito.

## Tests

- SQL: `get_report_photos` — bloqueado para anon, sin reporte 404, blocked
  user, rate limit, URLs firmadas con TTL, no filtra `storage_path` crudo.
- Dart: thumb generado dentro de límites, payload incluye `thumbnail_path`,
  repositorio maneja expiración, widget del detalle con/fotos y sin fotos.
- RLS: re-ejecutar `storage_report_photos_test` — las políticas nuevas de
  lectura NO deben ampliar a escritura ni listar carpetas ajenas.

## Criterio de aceptación

1. Usuario B abre el detalle de un reporte de usuario A y ve las fotos
   (miniatura y visor), sin poder leer `report_photos` directo.
2. Fotos nuevas tienen thumb; la lista muestra miniatura real.
3. Mapa sin regresiones; tests SQL y Dart en verde.

## Fuera de alcance etapa 1

- Fotos en el mapa (pins).
- Reporte de foto inapropiada / moderación (backlog).
- Purga de fotos de reportes resueltos antiguos (backlog).
