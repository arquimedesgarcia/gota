-- 00001: Extensiones
-- postgis se instala en el esquema extensions (convención de Supabase).

create extension if not exists postgis with schema extensions;

-- Verificación: avisar si postgis no quedó habilitada.
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'postgis') then
    raise warning 'postgis no está disponible: las funciones geoespaciales no funcionarán';
  else
    raise notice 'postgis habilitada (versión %)',
      (select extversion from pg_extension where extname = 'postgis');
  end if;
end $$;

-- Nota: gen_random_uuid() es nativo en PostgreSQL 13+ (pgrcrypto no es necesario).
