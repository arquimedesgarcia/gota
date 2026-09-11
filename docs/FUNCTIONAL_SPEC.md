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

## 5. Validar fuga

Una acción por identidad y reporte.

Si es propia:
- no se permite.

Si ya validó:
- acción deshabilitada y mensaje claro.

## 6. Resolver fuga

La UI muestra progreso `0/3`, `1/3`, `2/3`, `3/3`.

La transición ACTIVE → RESOLVED ocurre únicamente en backend al alcanzar 3 identidades distintas.

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
