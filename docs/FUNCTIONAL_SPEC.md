# Gota — Functional Specification

**Versión:** 0.2

## 1. Navegación

Bottom navigation:

1. Inicio
2. Mapa
3. Acción central: Reportar fuga
4. Agua
5. Más

Los destinos aún no implementados muestran un estado claro de “próximamente”; nunca simulan funcionalidad.

## 2. Inicio

Debe mostrar:

- estado/evento reciente de agua del sector;
- acción principal “Reportar fuga”;
- acción “Llegó / Se fue el agua”;
- acceso al mapa;
- resumen de actividad comunitaria;
- fugas cercanas o recientes.

## 3. Reportar fuga

Flujo:

**Ubicación → Fotos → Datos → Revisar → Enviar**

Ubicación:
- intenta GPS cuando el usuario lo solicita;
- si falla o se deniega, permite seleccionar manualmente en mapa;
- guarda GPS/MANUAL.

Fotos:
- mínimo 1, máximo 3;
- cámara o galería;
- compresión;
- validación de formato/tamaño;
- miniaturas.

Datos:
- municipio;
- sector;
- descripción opcional.

Antes de crear:
- backend busca posibles duplicados (50 m / 48 h configurables);
- si encuentra candidatos, muestra distancia y **tres** acciones (REQ-025):
  - **Ver y validar**: abre el detalle del candidato (`LeakDetailScreen`) con el
    `id` que ya devolvió la RPC — reutiliza la pantalla de detalle de Sprint 03,
    no implementa validación dentro del diálogo;
  - **Es la misma: usar ese reporte**: cierra el flujo sin crear nada;
  - **Es otra fuga**: reenvía con `p_ignore_duplicate = true` (confirmación
    explícita, no estado pegajoso del controlador).
- la confirmación "es otra fuga" es un argumento del envío; mutar ubicación,
  municipio, sector o fotos y reenviar sin volver a pulsarla viaja con
  `p_ignore_duplicate = false` (AUD-S2-04).
- la pantalla de resultado **nunca** muestra "Reporte enviado" a menos que el
  backend haya creado el reporte (`submitState == done`); en la ruta "usar el
  reporte existente" muestra "No se creó un reporte nuevo" (AUD-S2-06, §12).

## 4. Detalle de fuga

Muestra:

- estado ACTIVE/RESOLVED;
- fotos;
- municipio/sector;
- antigüedad;
- validaciones;
- confirmaciones de resolución;
- descripción;
- ubicación en mapa;
- acciones disponibles.

No muestra identidad del creador.

Se abre desde la lista de fugas recientes de Inicio. La lectura del detalle
pasó por la operación protegida `get_leak-report-detail`, porque las tablas de
acciones comunitarias no son accesibles desde el cliente.

Las fotografías todavía no se publican entre usuarios (Sprint 02 decidió que
cada usuario solo accede a sus propios binarios); el detalle muestra el
conteo de fotos y no binarios ajenos. Publicarlas requiere URLs firmadas
server-side y corresponde a un sprint posterior.

## 5. Validar fuga

Una acción por identidad y reporte.

Si es propia:
- no se permite.

Si ya validó:
- acción deshabilitada y mensaje claro.

Estados de la acción: disponible, en curso (deshabilitada para evitar doble
ejecución), validada, bloqueada y error. El creador no ve la acción
habilitada y recibe la razón explícita ("No puedes validar tu propio
reporte"). El contador mostrado proviene del backend tras cada operación.

## 6. Resolver fuga

La UI muestra progreso `0/3`, `1/3`, `2/3`, `3/3`.

La transición ACTIVE → RESOLVED ocurre únicamente en backend al alcanzar 3 identidades distintas.

El umbral lo reporta el backend (`system_config.resolution.threshold`), no la
app. Al alcanzarlo, la pantalla refresca el detalle y muestra `Fuga resuelta`
con la fecha; una fuga resuelta no ofrece acciones de validación ni de
confirmación. Un mensaje de éxito solo aparece después de que el backend
confirma la operación.

## 7. Mapa

Modos:

- mapa;
- lista.

Filtros iniciales:

- Todas;
- Activas;
- Resueltas;
- Mi sector;
- Recientes;
- Más validadas.

La capa de mapa debe abstraerse para permitir cambiar proveedor.

## 8. Agua (Sprint 04)

Acciones principales:

- **Llegó** (WATER_ARRIVED)
- **Se fue** (WATER_LEFT)

Flujo de registro:
1. Seleccionar tipo (Llegó/Se fue).
2. Seleccionar municipio.
3. Seleccionar sector (del municipio elegido).
4. Indicar hora efectiva del evento (puede ser pasada, no futura).
5. Comentario opcional (max 500 caracteres).
6. Revisar y confirmar.

Cada evento registra:
- municipio;
- sector;
- event_time (hora efectiva, declarada por el usuario);
- creador (identidad anónima, no pública);
- comentario opcional.

Validación comunitaria:
- Otros usuarios pueden validar eventos.
- El creador no puede validar su propio evento (regla server-side).
- Una identidad valida una sola vez el mismo evento (autoridad: `UNIQUE (water_event_id, user_id)`).

Estadísticas descriptivas:
- Total de eventos.
- Cuentas: "Llegadas" y "Salidas".
- Última llegada y última salida (timestamps).
- Duración promedio de suministro (media de pares ARRIVED→LEFT consecutivos).
- Duración promedio de interrupción (media de pares LEFT→ARRIVED consecutivos).
- Muestra "Sin datos suficientes" si faltan pares completos.
- **Sin predicciones, sin tendencias, sin promedios móviles.**

Historial:
- Lista de eventos recientes paginada (keyset, limit 20 default).
- Ordenada por `event_time` descendente (más recientes primero).
- Muestra tipo, hora, sector/municipio, validaciones, comentario (si existe).
- Toque para abrir detalle (donde se puede validar).

## 9. Notificaciones

Categorías:

- fugas;
- suministro.

El usuario puede elegir sector de interés.

Eventos posibles:
- reporte validado;
- reporte resuelto;
- llegó el agua;
- se fue el agua.

## 10. Mis reportes e historial

“Más” contiene:

- Mis reportes;
- Historial de fugas resueltas;
- historial de eventos de agua;
- preferencias de notificaciones;
- información básica.

## 11. Estados

Fuga:
- ACTIVE
- RESOLVED

Ubicación:
- GPS
- MANUAL

Evento de agua:
- WATER_ARRIVED
- WATER_LEFT

No usar estados históricos del prototipo anterior como PENDIENTE/CONFIRMADA/CERRADA_REPARADA/CERRADA_INEXISTENTE.

## 12. Conectividad

MVP:
- lecturas pueden requerir red;
- operaciones de escritura deben informar claramente su resultado;
- no se debe mostrar “enviado” hasta que el backend confirme;
- la estrategia offline avanzada puede evolucionar posteriormente.

El prototipo anterior proponía una cola offline completa; se conserva como referencia futura, pero no se convierte en requisito del Sprint 01.
