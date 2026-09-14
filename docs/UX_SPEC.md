# Gota — UX Specification

**Versión:** 0.2

## 1. Principios

- Español.
- Mobile-first.
- Acciones claras y grandes.
- Poco texto.
- Confianza y neutralidad.
- Bajo consumo de datos.
- No exponer identidad.
- Pedir permisos solo cuando hacen falta.
- Si GPS no está disponible, permitir selección manual.

## 2. Estructura

Bottom nav de cinco posiciones:

**Inicio · Mapa · Reportar · Agua · Más**

La acción central de reportar debe tener mayor jerarquía visual.

## 3. Home

Orden recomendado:

1. estado de agua;
2. Reportar fuga;
3. Llegó/Se fue el agua;
4. fugas cercanas;
5. resumen comunitario.

## 4. Reportar

Pantallas/estados:

1. Ubicación
2. Fotografías
3. Municipio/Sector
4. Descripción
5. Revisar
6. Enviado / error

El usuario siempre debe saber:
- dónde se reportará;
- cuántas fotos agregó;
- si la ubicación es GPS o manual;
- si existe un posible duplicado.

## 5. Duplicados

Mensaje conceptual:

> “Ya existe un reporte de fuga cerca.”

Acciones:
- Ver reporte y validar.
- Es otra fuga.

No bloquear silenciosamente.

## 6. Detalle

La acción primaria es “Validar”.

La resolución muestra el progreso comunitario.

Ejemplo conceptual:
`2 de 3 personas han confirmado que la fuga fue resuelta.`

## 7. Agua

Dos acciones grandes:
- Llegó
- Se fue

El historial debe priorizar fecha/hora/sector.

## 8. Estados vacíos y errores

Deben explicar qué ocurre y qué puede hacer el usuario.

Evitar:
- stack traces;
- códigos técnicos;
- mensajes genéricos sin acción.

## 9. Microcopy

Mantener un tono comunitario, directo y neutral.

Ejemplos reutilizables del prototipo:
- “Fugas cerca de ti”
- “Eventos recientes de tu sector”
- “Sin datos todavía”
- “Ya validaste este reporte”
- “La comunidad lo está validando”

## 10. Cambios Sprint 09

Sprint 09 adaptó la interfaz al nuevo prototipo visual:

### Home Screen
- Header con gradient (primaryDark → primary) + tagline “Juntos encontramos y cuidamos cada gota”
- Botón “Reportar fuga” hero-sized (64dp) con icono + dual-line text
- Grid 2-columnas para “Llegó/Se fue agua” y “Mapa de fugas”
- Card de estadísticas comunitarias (reportadas/resueltas/validadas)

### Report Flow
- Indicador visual de progreso (4 pasos: Ubicación → Fotos → Datos → Revisar)
- Barra de progreso horizontal por paso
- Labels: “Ubicación”, “Fotos”, “Datos”, “Revisar”

### Leak Detail
- Structure preparada para photo carousel (en desarrollo)
- Cards mantienen styling consistente
- Buttons ahora con AppSpacing constantes

### General
- All buttons now ≥48dp minimum touch target
- Consistent use of AppSpacing (4dp base) throughout
- Status indicators use color + text (nunca solo color)
- All screens tested en 119/121 test cases

El copy definitivo debe mantenerse centralizado y no ser inventado pantalla por pantalla.

## 10. Referencia visual

`prototipo/index.html` es referencia de interacción y composición.

No es fuente de:
- reglas de negocio;
- estados;
- backend;
- seguridad;
- nombres definitivos de entidades.
