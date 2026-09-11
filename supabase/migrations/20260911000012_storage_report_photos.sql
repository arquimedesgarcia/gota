-- 00012: Bucket privado para fotos de reportes.
--
-- Los binarios viven en Supabase Storage; PostgreSQL guarda solo
-- referencias (docs/ARCHITECTURE.md §7). Acceso restringido: solo el
-- usuario autenticado puede subir a su carpeta; la lectura de imágenes
-- de un reporte la resuelve el backend al serializar el detalle.
--
-- Estructura: report_photos/{report_id}/{sort}_{uuid}.{ext}

insert into storage.buckets (id, name, public)
values ('report-photos', 'report-photos', false)
on conflict (id) do nothing;

-- Escritura: solo el usuario autenticado que lleva el archivo de su
-- reportería (path = report_photos/{report_id}/...) y con la firma
-- report_id en el bucket name. Sprint 03 añade lectura por detalle.
create policy "UploadReportPhotoAuthenticated"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = 'report_photos'
  );

create policy "AuthenticatedReadReportPhotos"
  on storage.objects for select to authenticated
  using (bucket_id = 'report-photos');
