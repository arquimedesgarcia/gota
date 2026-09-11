# Gota — Review Checklist

**Versión:** 0.2

## Checklist universal

- [ ] Solo modificó archivos permitidos.
- [ ] No cambió contratos de arquitectura sin justificar.
- [ ] No contradice los documentos fuente.
- [ ] No inventó reglas de negocio.
- [ ] No inventó estados.
- [ ] No hard-codeó configuración que debe ser configurable.
- [ ] Textos visibles respetan UX_SPEC.
- [ ] Estilos respetan DESIGN_SYSTEM.
- [ ] Errores son amigables.
- [ ] Reglas críticas existen server-side.
- [ ] No hay secretos en el repositorio.
- [ ] Tests relevantes pasan.
- [ ] `flutter analyze` pasa.
- [ ] README/documentación se actualizó si corresponde.
- [ ] No introdujo infraestructura innecesaria.

## Severidad

**BLOQUEANTE:** rompe requisito, seguridad, contrato, migración o regla crítica.

**IMPORTANTE:** incumplimiento técnico/UX que debe corregirse antes de cerrar.

**MENOR:** pulido que puede resolverse sin cambiar comportamiento.

## Entrega del agente

Debe informar:

A. Implementado  
B. Archivos modificados  
C. Base de datos/migraciones  
D. Flutter/arquitectura  
E. Tests exactos  
F. Configuración requerida  
G. Problemas/supuestos  
H. Siguiente paso sugerido

Nunca debe declarar “terminado” sin mostrar evidencia de las pruebas.

## Revisión humana

El humano ejecuta la aplicación y valida los criterios de aceptación.

Si hay fallos:
- devolver lista numerada;
- indicar severidad;
- no pedir una nueva tarea hasta corregir los bloqueantes.
