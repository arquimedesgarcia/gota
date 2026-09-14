# Cierre de seguridad Sprint 08

**Alcance:** únicamente AUD-S08-01 y AUD-S08-04, más la clasificación de objetos residuales y la higiene E2E solicitadas tras el veredicto `BLOCKED` del commit `1491952`.

## Correcciones

- `water_events`: se sustituyó el `GRANT SELECT` de tabla por `GRANT SELECT` explícito de las columnas públicas. `created_by` no es seleccionable por `anon` ni `authenticated`. Las RPC server-side siguen leyendo la fila con sus privilegios de propietario y no cambia la API funcional.
- `system_config`: RLS quedó habilitado, se retiró la policy pública inactiva y se revocó el acceso de `anon` y `authenticated`. `get_rate_limit()` y las demás RPC `SECURITY DEFINER` continúan leyendo la tabla internamente.
- E2E: se conservó el mecanismo administrativo ya existente para eliminar `auth.users` y se añadió la eliminación explícita de `audit_events`, que no tiene FK. No se añadió `service_role` al producto ni se modificó el límite de rate limiting.

## Objetos residuales

`public.temp`, `test_func()`, `test_simple_update()` y `test_get_rate_limit()` no aparecen en migraciones, seed, código ni historial del repositorio. Son residuos del volumen local de prueba, no objetos desplegables del producto. No se creó una migración destructiva para ellos. Deben limpiarse en el entorno donde fueron creados; el volumen local usado para esta verificación fue limpiado y se verificó su ausencia.

## Build

`docs/SETUP.md` ya no afirma que el build de release sea reproducible desde cualquier clon: un clon limpio puede compilar con la firma debug de fallback, pero la distribución requiere la configuración de firma de release.
