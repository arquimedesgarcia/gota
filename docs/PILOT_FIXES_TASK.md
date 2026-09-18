# GOTA — CORRECCIONES PILOTO

REPO: https://github.com/arquimedesgarcia/gota
BRANCH: `main`
BASE ACTUAL: `87a24ce`

## OBJETIVO

Implementar únicamente las correcciones indicadas abajo.
No rediseñar arquitectura. No agregar funcionalidades no solicitadas. Cambios mínimos y localizados.

## R1 — SIMPLIFICAR REGISTRO DE AGUA

Actualmente registrar "Llegó el agua" / "Se fue el agua" requiere demasiados pasos.

Nuevo flujo: `Llegó/Se fue → Municipio + Sector → fecha/hora automáticas → Resumen → Confirmar`

Reglas:
* Municipio y sector continúan siendo selección explícita.
* Fecha y hora se inicializan automáticamente con la fecha/hora actual.
* No pedir al usuario que configure fecha/hora durante el flujo principal.
* En el resumen final debe poder tocar fecha y hora para editarlas.
* La confirmación final debe ser explícita.
* Mantener la semántica existente de `water_events`.
* No modificar modelo/backend salvo que sea estrictamente necesario.

## R2 — ACTUALIZAR HISTORIAL

Después de crear exitosamente un evento de agua:
* el historial debe actualizarse inmediatamente;
* no debe requerir cerrar/reabrir la aplicación.

Identificar el provider/cache correspondiente e invalidarlo o refrescarlo en el punto correcto después del create exitoso. No introducir polling ni refresh periódico.

## R3 — IMPEDIR RESOLUCIÓN SIN CONFIRMACIÓN

Una fuga no confirmada no puede marcarse como resuelta.

Flujo obligatorio: `REPORTADA → CONFIRMADA → RESUELTA`

La UI no debe ofrecer una acción válida de resolver cuando la fuga aún no está confirmada. Además, la lógica de negocio/backend existente debe seguir siendo respetada. No reemplazar ni modificar la regla comunitaria existente de resolución.

## R4 — SALTOS DURANTE ZOOM DEL MAPA

Investigar el problema real antes de modificar código.

Durante zoom in/out del mapa de fugas actualmente se observan saltos en el renderizado.

Determinar si la causa está relacionada con: reconstrucción de widgets; actualización de markers; listeners de cámara; cambios de estado; lifecycle/style de MapLibre; otra causa concreta.

Aplicar la corrección mínima. NO sustituir MapLibre. NO rediseñar el mapa. NO introducir una solución basada simplemente en ocultar/recrear todo el mapa.

## RESTRICCIONES

* No tocar D2 salvo regresión causada directamente por estos cambios.
* No tocar reverse-geocode.
* No migraciones salvo necesidad absolutamente demostrada.
* No refactors generales.
* No cambios cosméticos no relacionados.
* No modificar tests existentes innecesariamente.

## VALIDACIÓN

Ejecutar la suite existente (flutter test).
Agregar únicamente cobertura necesaria para las reglas nuevas, especialmente: fecha/hora automáticas; edición desde resumen; refresh del historial; imposibilidad de resolver fuga no confirmada.

Para R4 documentar brevemente la causa encontrada y la corrección aplicada.

## ENTREGA (formato obligatorio de tu respuesta final)

STATUS: PASS / FAIL
CHANGES: solo cambios realizados.
TESTS: resultado.
FINDINGS: solo problemas encontrados durante implementación.
COMMIT: hash y mensaje.

VERBOSE = none (no narrar el proceso, solo el formato de entrega).
