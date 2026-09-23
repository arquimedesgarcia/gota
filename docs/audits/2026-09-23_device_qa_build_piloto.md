# QA en device — build release de piloto (2026-09-23)

**Artefacto:** `build/app/outputs/flutter-apk/app-release.apk`, sha256 `fa5d37aa9944e1e5d485c43a94917b1b9d9a2145409d9c9278bddb961bf6dfd4`
**Instalado y verificado:** sha256 del `base.apk` en el device **idéntico** al compilado (`adb pull` + `sha256sum`), `lastUpdateTime=2026-09-22 23:32:42`, `versionName=1.0.0` (versionCode sin incrementar: la versión por sí sola **no** distingue este build del anterior).
**Rama:** `fix/map-r5-r6` en `39485f5` (commits `10e6826` fotos/formulario, `70e6a2f` mapa, `39485f5` sector). **No** mergeado a `main`.
**Device:** Samsung SM-A245M, Android 16, 1080x2340 @450 dpi, serial `R58W709201M`. RAM total **3.77 GB**, `MemAvailable` 940 MB al momento de las pruebas.
**Método:** `adb` (uiautomator dump + `input tap` + `screencap` + `logcat`). Los conteos de píxeles se hacen con PIL sobre los PNG (`no-blancos` en la zona del mapa, y = 420–1900).

---

## 1. Resultados verificados en device

| Punto | Resultado | Evidencia |
|---|---|---|
| Home de piloto presente en el APK | **PASS** | "Resumen de hoy" (0 fallas / 0 resueltas / Llegó), 3 acciones, "Actividad reciente" en `content-desc`; el APK del 20-sep no lo tenía |
| Mapa no se desmonta con resultado vacío | **PASS** | Filtro `Resueltas` (0 marcadores) → mapa renderizado, 1.061.452 px no-blancos (66.4 % del área), idéntico al estado con resultados; el bug documentado por la RC era 506.438 → 3.146 px |
| Mapa con la excepción "Mi sector" | **PASS** | `Todas` → `Resueltas` → `Mi sector` → `Todas`: el mapa se mantiene montado en los cuatro estados (sin crash, pid estable) |
| Contador de fotos y tope 2 | **PASS** | Paso Fotos muestra "Agrega de 1 a 2 fotos de la fuga" y "Fotos agregadas: N de 2" (antes "de 3") |
| Tercera foto imposible | **PASS** | Con 2 de 2, el tile de agregar **ya no existe**: tocar su posición no abre la hoja (sin "Tomar con la cámara"/"Elegir de la galería"), no hay excepción y las 2 fotos se conservan |
| "Continuar" habilitado con preselección | **PASS** | Paso Datos sin tocar nada: "Municipio · Maneiro · Sugerido según ubicación GPS", "Sector · Los Cerritos · Sugerido según ubicación GPS", `Continuar clickable=true` |
| Flujo completo hasta Revisar | **PASS** | GPS (11.01890, -63.82649) → 2 fotos → Datos → Revisar con "Ubicación por GPS / 2 foto(s) agregada(s). / Municipio y sector: Maneiro · …" y acciones "Enviar reporte"/"Editar datos". Pid estable durante todo el recorrido |
| Cierre del asistente (descartar) | **PASS** | `Close` vuelve al Home, pid sin cambios, sin crash |
| Ruta de galería (elegir foto) | **PASS** | Picker → "Done" → vuelve al paso Fotos con el contador en 1 y 2; **mismo pid**, borrador conservado |

## 2. BLOCKER nuevo — la ruta de **cámara** mata la app (LMK), se pierde el borrador

**Reproducido el 2026-09-22 23:54:11**, paso Fotos, segunda foto por `Tomar con la cámara` → visor de Samsung → `OK`:

```
23:54:11.386  467  467 I lmkd    : Reclaim 'com.gota.app' (30364), uid 10274, oom_score_adj 700, state 15
                                   to free 113444kB rss, 138548kB swap; reason: min watermark
23:54:11.616 27501 27501 I Zygote  : Process 30364 exited due to signal 9 (Killed)
23:54:11.617 27716 28629 I ActivityManager: Process com.gota.app (pid 30364) has died: prev LAST(10,623)
```

- **No es una excepción Dart:** el crash buffer (`logcat -b crash`) y `dumpsys dropbox` **no tienen ninguna entrada** de Gota (ni `FATAL`, ni `ANR`). El proceso muere por **SIGKILL del low-memory killer**.
- Al volver del visor de cámara el pid cambió (30364 → 11157) y la app reapareció en el **Home**: el asistente y el borrador se perdieron.
- Contexto de presión: el mismo minuto el LMK reclamó `com.android.settings`, `com.google.android.gms`, `com.google.android.apps.photos`, `googlequicksearchbox` y `com.facebook.katana`. La cámara en primer plano activa su `CameraMode`/ionheap y el sistema aprieta el agua.
- La huella de la app no es inocente: en la sesión de pruebas `TOTAL PSS 241 MB / TOTAL RSS 279 MB / SWAP 31 MB` (tras haber visitado el mapa). Con 3.77 GB de RAM y ~940 MB disponibles, Gota es candidata directa del reaper.

**Impacto para el piloto:** un usuario que adjunta la segunda foto con la cámara puede perder el reporte completo. Es el "cierre al tomar/elegir foto" que la auditoría RC declaró **no reproducido**: se reproduce por la vía de cámara y bajo presión de memoria, no por la vía de galería.

**Mitigaciones a evaluar (no implementadas):**
1. **Persistir el borrador** (sobrevivir a la muerte del proceso y reanudar al volver): es la única mitigación que salva el caso raíz, porque la muerte la decide el sistema.
2. **Reducir la huella base**: liberar MapLibre al salir de la pestaña del mapa, límite de tiles en caché, y medir el PSS en frío y después de usar el mapa.
3. El presupuesto de foto ya enviado (1280 px, un solo pase JPEG, commit `10e6826`) baja el pico del *pipeline* de imagen, pero **no** protege del kill ocurrido mientras la cámara tenía el primer plano.

## 3. Pendientes / NOT VERIFIED

- **FCM con la app cerrada** (notificación de sistema): no ejecutado — falta una vía de envío de push en este entorno.
- **Mensaje de confirmación sin GUID** (prompt 5.5): el prompt 5 **no** está en este build, así que el GUID sigue presente por diseño.
- **Cierre de foto al tomar con cámara sin presión de memoria**: no aislado; la corrida reproducida ocurrió bajo presión del sistema, no se determinó si es determinista en frío.
- **A1/A2** (límite `photo_limits.max_count 3 → 2` en local y cloud): sin ejecutar. El cliente ya bloquea la tercera foto, pero un tercer cliente con la RPC directa todavía podría enviarla.