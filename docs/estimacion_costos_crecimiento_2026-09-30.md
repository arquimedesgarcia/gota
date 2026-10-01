# Estimación de costos operativos por crecimiento de usuarios (2026-09-30)

**Propósito:** documento para presentar a instituciones potenciales de apoyo. Muestra el costo de mantener Gota operativo según rango de usuarios activos mensuales (MAU), bajo el supuesto de éxito de la etapa 1 (Nueva Esparta en producción) y la expansión nacional por oleadas (`backlog/expansion_oleadas_2026-09-30.md`).

## Supuestos

- "Usuarios" = usuarios activos mensuales (MAU), no registrados totales. Es la métrica que cobra Supabase.
- App gratuita en Google Play (no genera ingresos; el costo es solo la cuenta).
- Mapa: MapLibre + OpenStreetMap / reverse geocoding público → **costo $0** (sin API de mapas paga).
- Almacenamiento de fotos: reportes comunitarios, ~1 MB por foto. A mayor escala los reportes crecen ~2 GB/mes por cada 5-10K reportes.
- Precios en USD, verificados en fuentes oficiales en sep-2026. No incluyen el costo del tiempo humano (mantenimiento, moderación, soporte).

## Costos por servicio según rango de usuarios

Base: Supabase Pro $25/mes (incluye 100K MAU, 8 GB BD, 100 GB storage, 250 GB egress). Exceso de MAU: $0.00325 por usuario activo. Plan Team $599/mes incluye 500K MAU (a partir de ~184K MAU conviene Team en vez de Pro con excedentes).

| Rango MAU/mes | Escenario Gota | Supabase | Google Play | Dominio + email | Infra extra (CDN/estimación) | **Total mensual** |
|---|---|---|---|---|---|---|
| 0 – 1.000 | Piloto Nueva Esparta | $0 (Free: 50K MAU, 500 MB BD, 1 GB storage) | $0 | $0 | $0 | **$0** |
| 1.000 – 50.000 | Producción NE + oleada 1 | $0 – $25 (Free llega hasta 50K MAU; subir a Pro solo si BD/storage exceden) | $0 | ~$10-15/año dominio (opcional) | $0 | **$0 – $25** |
| 50.000 – 100.000 | NE consolidada + oleada 2 (Caracas, Maracaibo, Valencia, Barquisimeto) | $25 (Pro) | $0 | ~$15/mes (dominio + email Resend) | $0 | **~$40** |
| 100.000 – 250.000 | Oleada 2 activa | $25 + excedente: $512 a 250K MAU | $0 | ~$15/mes | ~$0-50 (egress extra si excede 250 GB) | **~$40 – $590** |
| 250.000 – 500.000 | Oleada 3 nacional parcial | **$599 (Team: incluye 500K MAU)** | $0 | ~$15/mes | ~$50-150 (compute add-on BD) | **~$665 – $765** |
| 500.000 – 1.000.000 | Nacional | $599 + excedente hasta ~$1.325 (Pro a esta escala) / Team + $1.625 a 1M | $0 | ~$15/mes | ~$150-400 (compute + egress) | **~$765 – $2.300** |

Nota: en el rango 100K-250K, Pro con excedentes ($512) sigue siendo más barato que Team ($599). El cruce está en ~184K MAU.

## Costos fijos puntuales

| Ítem | Costo | Frecuencia |
|---|---|---|
| Cuenta Google Play Console | $25 | Única vez (ya pagada o por pagar) |
| Dominio (ej. gota.app / gotavenezuela.org) | $10-20 | Por año |
| Auditoría de seguridad / revisión RLS externa (recomendada al escalar) | $500-2.000 | Una vez por gran oleada |

## Resumen para presentaciones (rango anual)

| Rango MAU | Costo anual estimado |
|---|---|
| Piloto / <50K activos | $0 – $300 |
| 50K – 100K | ~$480 |
| 100K – 250K | ~$480 – $7.100 |
| 250K – 500K | ~$8.000 – $9.200 |
| 500K – 1M | ~$9.200 – $27.600 |

**Mensaje clave para instituciones:** mantener Gota operativo durante toda la etapa piloto es prácticamente gratis; el presupuesto serio solo aparece al superar ~100K usuarios activos mensuales, lo que da tiempo y margen para gestionar apoyo institucional con anticipación. La partida más realista a mediano plazo no es infraestructura sino tiempo humano (moderación y soporte), que este documento no cuantifica.

## Fuentes

- Supabase Pricing (sep-2026): supabase.com/pricing — Free 50K MAU; Pro $25, 100K MAU + $0.00325/MAU; Team $599.
- Google Play Console: US$25 único, sin renovación anual.
