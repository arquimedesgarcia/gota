-- 00012: Bucket privado para fotos de reportes.
--
-- Los binarios viven en Supabase Storage; PostgreSQL guarda solo
-- referencias (docs/ARCHITECTURE.md §7, docs/API_SPEC.md §6).
--
-- Estructura de rutas (la pertenencia se deriva de la ruta):
--   report_photos/{auth_user_id}/{upload_key}/{photo_uuid}.jpg
--
-- Reglas:
--  * el bucket es y sigue siendo privado (`public = false`);
--  * un usuario autenticado solo escribe dentro de su propia carpeta
--    (`report_photos/<su auth.uid()>/...`);
--  * no puede leer las fotografías de otros usuarios;
--  * puede eliminar sus propios temporales, lo que habilita la limpieza
--    de binarios huérfanos cuando la creación del reporte falla o se
--    detecta un duplicado;
--  * no se usa `service_role` en el cliente: la app solo lleva la clave
--    pública y su propia sesión.

insert into storage.buckets (id, name, public)
values ('report-photos', 'report-photos', false)
on conflict (id) do update set public = false;

-- ---------- subida: solo a la carpeta del propio usuario ----------
create policy "Subida a carpeta propia de fotos de reporte"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = 'report_photos'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ---------- lectura: solo las propias ----------
-- Sprint 02 no publica binarios: la app no muestra fotos de otros
-- usuarios todavía. La lectura pública/por detalle, si hiciera falta,
-- se resuelve server-side (URLs firmadas) en un sprint posterior.
create policy "Lectura de fotos propias"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = 'report_photos'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ---------- borrado: solo los temporales propios (cleanup) ----------
create policy "Borrado de fotos propias"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'report-photos'
    and (storage.foldername(name))[1] = 'report_photos'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
