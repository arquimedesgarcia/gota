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
- backend busca posibles duplicados;
- si encuentra candidatos, muestra distancia y acciones;
- el usuario puede validar el existente o continuar como otra fuga.

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

## 8. Agua

Acciones principales:

- **Llegó**
- **Se fue**

Cada evento registra:
- municipio;
- sector;
- event_time;
- creador;
- comentario opcional.

Los eventos pueden ser validados por otros usuarios.

La app puede calcular estadísticas descriptivas con datos existentes, pero no predicciones.

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
