# Gota — Design System

**Versión:** 0.2

## 1. Paleta

| Token | Valor | Uso |
|---|---|---|
| color.primaryDark | #0B3C5D | encabezados, identidad |
| color.primary | #1D84B5 | acciones secundarias, navegación |
| color.accent | #FF6B5B | acción principal |
| color.success | #2E9E5B | validación, resuelto, llegó |
| color.danger | #E23B3B | fuga/alerta/error, se fue |
| color.warning | #F2A93B | pendiente/alerta suave |
| color.bg | #FBFDFE | fondo |
| color.surface | #FFFFFF | tarjetas |
| color.border | #DCE7EE | bordes |
| color.text | #12314A | texto principal |
| color.textMuted | #5B7282 | texto secundario |
| color.badgeSync | #E3EEF7 | sincronización |

## 2. Regla del coral

El coral es el color de atención principal. Evitar usarlo en todo.

Como referencia, máximo un elemento coral dominante por pantalla.

## 3. Tipografía

- display: 24sp bold
- title: 17sp semibold
- body: 15sp regular
- caption: 13sp regular
- badge: 11sp bold

Usar tipografía del sistema.

## 4. Espaciado

Base 4dp.

- pantalla: 16dp
- tarjeta: 16dp
- separación: 12dp
- botones y tarjetas: radio 14dp
- inputs: 10dp
- badges: 20dp

Objetivo táctil mínimo: 48dp.

## 5. Componentes

### Primario
Coral + texto blanco. Para acción principal.

### Secundario
Outline azul.

### Estados
Usar texto + color, nunca color como único indicador.

### Tarjeta
Blanca, borde sutil, sombra ligera.

### Banner offline
Debe ser claro y accionable, sin bloquear la app.

## 6. Accesibilidad

- contraste adecuado;
- targets ≥48dp;
- labels comprensibles;
- estados no dependientes solo del color;
- compatibilidad con tamaños de texto razonables.

## 7. Relación con el prototipo

El prototipo aporta:
- composición;
- jerarquía;
- navegación;
- colores iniciales;
- patrones de tarjetas/chips.

La implementación Flutter debe usar estos tokens y no copiar CSS literalmente.

## 8. Componentes Reutilizables (Sprint 09)

### AppSpacing
- xs = 4dp
- sm = 8dp
- md = 12dp
- lg = 16dp
- xl = 24dp

### AppRadius
- sm = 8dp
- md = 12dp
- lg = 16dp
- xl = 20dp

### AppComponents
Estilos de botones reutilizables:
- `primaryButtonStyle()` — acción principal (relleno, coral)
- `secondaryButtonStyle()` — acción alternativa (outline, azul)
- `largeButtonStyle()` — acciones prominentes (64dp mínimo)
- `compactButtonStyle()` — acciones compactas

### GotaStatusBadge
Badge de estado con color semántico + texto (nunca solo color):
- "Resuelta" (verde)
- "Activa" (rojo)
- "Pendiente" (ámbar)

## 9. Cambios Sprint 09

Sprint 09 incorporó:
- Design system constants (spacing, radius)
- Home screen visual refresh (gradient header, hero button, 2-column grid, community stats)
- Report flow step indicator (4 visual steps with progress)
- Photo carousel structure (deferred - ready for implementation)
- Reusable status badge component
- Consistent use of AppSpacing throughout layouts
