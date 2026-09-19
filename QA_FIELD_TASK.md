# GOTA — QA DE CAMPO POST ba2a5d4

REPO local: D:/Proyectos/Gota/v0.2 (branch main, commit 0e31130; el fix a validar es ba2a5d4)
DISPOSITIVO: SM-A245M, ya conectado por USB (adb en C:/Users/arqui/AppData/Local/Android/sdk/platform-tools).
HERRAMIENTAS: adb NO está en PATH — exporta primero:
`export PATH="/c/Users/arqui/AppData/Local/Android/sdk/platform-tools:$PATH"`
JAVA_HOME (si haces build) debe ir en formato Windows: 'C:\\Program Files\\Eclipse Adoptium\\jdk-21...' (busca el exacto con find). El APK debe construirse con --dart-define leyendo .env con `tr -d '\\r'` (ver guia de abajo).

GUIA DE QA OBLIGATORIA (leyela antes de empezar):
- C:/Users/arqui/AppData/Local/hermes/skills/software-development/android-on-device-qa/SKILL.md
- .../references/adb-setup-windows.md
- .../references/adb-qa-recipes.md
- .../scripts/marker_blob_counter.py
- .../references/supabase-backend-probes.md (si necesitas verificar datos en backend)

## OBJETIVO

Validar en dispositivo Android real los cambios del flujo de eventos de agua, historial, resolución de fugas y mapa.

No modificar código. No hacer commits.

## R1 — REGISTRO DE AGUA

Probar "Llegó el agua" y "Se fue el agua". Verificar:
1. Flujo reducido: Tipo → Municipio → Sector → Resumen
2. Fecha y hora se asignan automáticamente.
3. El usuario puede modificar la hora desde Resumen.
4. Confirmación explícita.
5. Evento creado correctamente.
6. Los datos finales corresponden a lo mostrado/seleccionado.

## R2 — HISTORIAL

Registrar un evento y volver al historial sin cerrar/reabrir la aplicación. Verificar que el nuevo evento aparece inmediatamente.

## R3 — RESOLUCIÓN

Con una fuga no confirmada: verificar que no se pueda resolver; verificar que la UI respete el estado de confirmación. Después de confirmar, verificar que la resolución continúa respetando la regla comunitaria existente.

## R4 — MAPA / ZOOM (punto principal)

Abrir el mapa y realizar repetidamente: zoom in, zoom out, zoom rápido, zoom lento, varios niveles consecutivos, pan + zoom.

Observar: marcadores que saltan; desaparición/reaparición; cambios de posición bruscos; reconstrucción del mapa completo; si el salto ocurre durante el gesto o al terminar; si ocurre siempre u ocasionalmente.

No asumir la causa. Si R4 falla, capturar capturas de pantalla + logcat como evidencia y describir exactamente el momento del salto. Usa scripts/marker_blob_counter.py para verificar marcadores programaticamente en las capturas, no a ojo.

## DISCIPLINA DE EVIDENCIA

- `adb logcat -c` antes de cada grupo de escenarios; captura a archivo y cuenta con grep -c.
- Distingue CRITICAL del error bajo prueba vs warnings no bloqueantes ya conocidos.
- Confirma que el proceso sigue vivo (`adb shell pidof <pkg>`) antes de concluir que algo funcionó.
- Lo que no puedas reproducir de forma controlada: NOT TESTED, nunca inventar resultados.
- Evidencia en D:/Proyectos/Gota/v0.2/qa-evidence/ (screenshots, logcat, dumps) — NO commitearla.

## ENTREGA (formato obligatorio de tu respuesta final)

STATUS: PASS / FAIL / BLOCKED
FINDINGS: solo hallazgos concretos. Para cada uno: categoría; comportamiento observado; comportamiento esperado; evidencia.
NEXT ACTION: solo si existe una acción necesaria.

VERBOSE = none (no narrar el proceso, solo el formato de entrega).
