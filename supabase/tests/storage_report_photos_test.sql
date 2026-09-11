-- tests/storage_report_photos_test.sql — Pruebas de las políticas RLS del
-- bucket privado `report-photos` (Sprint 02, corrección de storage).
--
-- Ejecutar contra una BD Supabase con las migraciones aplicadas:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/storage_report_photos_test.sql
--
-- Todo ocurre en una transacción con rollback final. Las filas de
-- storage.objects se insertan aquí para probar las políticas; la
-- verificación de los binarios reales (subida/lectura/borrado vía la API
-- de Storage) se hizo además de forma manual contra el Storage local.

begin;
set role postgres;
reset request.jwt.claims;

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'storagea@gota.test'),
  ('22222222-2222-4222-8222-222222222222', 'storageb@gota.test')
on conflict (id) do nothing;

-- =====================================================================
-- 0. El bucket sigue siendo privado
-- =====================================================================
do $$
declare v_public boolean;
begin
  select public into v_public from storage.buckets where id = 'report-photos';
  assert v_public is not null, 'FALLO 0: el bucket report-photos no existe';
  assert v_public = false, 'FALLO 0: el bucket report-photos es público';
  raise notice 'OK 0: bucket report-photos existe y es privado';
end $$;

-- =====================================================================
-- 1. Rol authenticated: usuario A
-- =====================================================================
set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 1a. A sube a su propia carpeta.
do $$ begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('report-photos',
          'report_photos/11111111-1111-4111-8111-111111111111/upA/1.jpg',
          '11111111-1111-4111-8111-111111111111',
          '11111111-1111-4111-8111-111111111111',
          '{"mimetype":"image/jpeg","size":10000}'::jsonb);
  raise notice 'OK 1a: A sube a su propia carpeta';
end $$;

-- 1b. A NO puede escribir en la carpeta de B (la prueba 1a confirma que
-- el rol sí tiene privilegio; por tanto este fallo es de RLS).
do $$ begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('report-photos',
          'report_photos/22222222-2222-4222-8222-222222222222/upB/1.jpg',
          '22222222-2222-4222-8222-222222222222',
          '22222222-2222-4222-8222-222222222222',
          '{"mimetype":"image/jpeg","size":10000}'::jsonb);
  raise exception 'FALLO 1b: A pudo escribir en la carpeta de otro usuario';
exception when insufficient_privilege then
  raise notice 'OK 1b: RLS bloqueó la escritura en carpeta ajena';
end $$;

-- 1c. A NO puede escribir fuera de la estructura esperada del bucket.
do $$ begin
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values ('report-photos', 'report_photos/otra-cosa/1.jpg', null, null,
          '{"mimetype":"image/jpeg","size":10}'::jsonb);
  raise exception 'FALLO 1c: A pudo escribir fuera de su carpeta';
exception when insufficient_privilege then
  raise notice 'OK 1c: RLS bloqueó rutas fuera de la carpeta propia';
end $$;

-- =====================================================================
-- 2. Usuario B sube su archivo (como administrador de BD, ya que el rol
--    authenticated de A no podría) y comprobamos aislamiento de lectura.
-- =====================================================================
reset role;
set role postgres;
insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
values ('report-photos',
        'report_photos/22222222-2222-4222-8222-222222222222/upB/1.jpg',
        '22222222-2222-4222-8222-222222222222',
        '22222222-2222-4222-8222-222222222222',
        '{"mimetype":"image/jpeg","size":10000}'::jsonb);

set role authenticated;
set request.jwt.claims =
  '{"role": "authenticated", "sub": "11111111-1111-4111-8111-111111111111", "aud": "authenticated"}';

-- 2a. A ve su archivo.
do $$
declare n int; begin
  select count(*) into n from storage.objects
   where name = 'report_photos/11111111-1111-4111-8111-111111111111/upA/1.jpg';
  assert n = 1, 'FALLO 2a: A no ve su propio archivo';
  raise notice 'OK 2a: A lee su propio archivo';
end $$;

-- 2b. A NO ve el archivo de B.
do $$
declare n int; begin
  select count(*) into n from storage.objects
   where name = 'report_photos/22222222-2222-4222-8222-222222222222/upB/1.jpg';
  assert n = 0, 'FALLO 2b: A puede leer el archivo de B';
  select count(*) into n from storage.objects where bucket_id = 'report-photos';
  assert n = 1, format('FALLO 2b: A ve %s archivos del bucket (esperaba 1)', n);
  raise notice 'OK 2b: A no ve los archivos ajenos (lectura aislada)';
end $$;

-- 2c. El borrado NO se hace con SQL directo: Supabase lo bloquea y obliga
-- a usar la API de Storage (que es lo que usa la app en _cleanupUploaded).
-- La verificación real de borrado vive en
-- supabase/tests/storage_rls_e2e.sh, que ejercita la API con dos usuarios.
do $$ begin
  delete from storage.objects
   where name = 'report_photos/22222222-2222-4222-8222-222222222222/upB/1.jpg';
  raise exception 'FALLO 2c: el borrado directo por SQL no fue bloqueado';
exception when others then
  if sqlerrm like '%Direct deletion from storage tables is not allowed%' then
    raise notice 'OK 2c: el borrado directo está bloqueado (usar Storage API)';
  else
    raise exception 'FALLO 2c: error inesperado al borrar: %', sqlerrm;
  end if;
end $$;

-- 2d. La política de DELETE existe y está acotada a la carpeta propia
-- (se comprueba su definición; la ejecución real va por la API).
do $$
declare v_qual text;
begin
  select qual into v_qual
    from pg_policies
   where schemaname = 'storage'
     and tablename = 'objects'
     and policyname = 'Borrado de fotos propias';
  assert v_qual is not null,
    'FALLO 2d: no existe la política de borrado de fotos propias';
  assert v_qual like '%report_photos%' and v_qual like '%auth.uid()%',
    'FALLO 2d: la política de borrado no está acotada al usuario';
  raise notice 'OK 2d: política de borrado acotada al usuario autenticado';
end $$;

-- =====================================================================
-- 3. Anon no toca nada del bucket
-- =====================================================================
reset role;
set role anon;
set request.jwt.claims = '{"role": "anon", "sub": null, "aud": "anonymous"}';

do $$
declare n int; begin
  select count(*) into n from storage.objects where bucket_id = 'report-photos';
  assert n = 0, 'FALLO 3a: anon ve archivos del bucket privado';
  raise notice 'OK 3a: anon no lee archivos del bucket';

  begin
    insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
    values ('report-photos', 'report_photos/anon/1.jpg', null, null,
            '{"mimetype":"image/jpeg","size":10}'::jsonb);
    raise exception 'FALLO 3b: anon pudo escribir en el bucket';
  exception when insufficient_privilege then
    raise notice 'OK 3b: anon no puede escribir en el bucket';
  end;
end $$;

reset role;
reset request.jwt.claims;
do $$ begin
  raise notice 'Todas las pruebas de Storage RLS pasaron.';
end $$;
rollback;
