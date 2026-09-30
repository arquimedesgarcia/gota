# Plan de expansión por oleadas (decisión 2026-09-30)

**Decisión:** la app sale a producción cubriendo todo el estado Nueva Esparta. La expansión nacional se hace por oleadas después. No se declara la app como "nacional" en la ficha hasta que haya cobertura real en varias entidades.

## Estado actual (verificado)
- `supabase/migrations/20260925000031_parishes.sql` ya carga TODOS los municipios y parroquias de Nueva Esparta.
- No hay filtro por municipio en `lib/` que limite el uso a Maneiro.
- Consecuencia: cubrir NE completo no requiere migraciones nuevas, solo validación y la ficha de Play.

## Antes de salir a producción
- [ ] Validar en el dispositivo que el selector de parroquia muestra todo NE y que un reporte en Porlamar/Juan Griego fluye end-to-end.
- [ ] Ficha de Play: descripción con posicionamiento honesto — "operativa en Nueva Esparta; llegando a más estados".
- [ ] Flujo de moderación (PROMPT 16, botón Reportar) funcionando antes de abrir el área de cobertura.

## Oleadas nacionales (post-producción)
| Oleada | Alcance | Prerequisitos |
|---|---|---|
| 1 | Nueva Esparta (producción) | QA NE + ficha honesta + moderación |
| 2 | Ciudades mayores: Caracas, Maracaibo, Valencia, Barquisimeto | Importación masiva de catálogo por CSV (parroquias de Distrito Capital, Zulia, Carabobo, Lara), plan pagado Supabase, moderador/flujo consolidado |
| 3 | Resto del país por regiones | Mismo mecanismo CSV + validación local por ciudad (1 mini-piloto por región) |

## Requisito técnico clave para las oleadas 2-3
- Crear mecanismo de **importación masiva de municipios/parroquias por CSV** (script + validación de duplicados contra `unique (municipality_id, name)`), para que agregar una ciudad sea un upload y no desarrollo nuevo. → PROMPT 17 (candidato).

## Criterio de anuncio
Cada oleada se anuncia en la descripción de la ficha y en "Novedades" de Play Console; ese update es además el gancho de re-engagement de usuarios existentes.
