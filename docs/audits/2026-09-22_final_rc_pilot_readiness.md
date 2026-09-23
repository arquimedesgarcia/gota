# Gota — Auditoría final RC / Preparación piloto controlado

- **Fecha:** 2026-09-22 (UTC-4)
- **Rama auditada:** `fix/map-r5-r6`. HEAD al inicio `295f77d`; al cierre `525725c` (commit *docs-only* aparecido **durante** la auditoría, no generado por el auditor).
- **Dispositivo físico:** Samsung SM-A245M, Android 16, serial `R58W709201M`, 1080x2340 @450 dpi, paquete `com.gota.app`.
- **Backend:** Supabase **cloud piloto** (`eghphmugrrbvbvodhasq`), `SUPABASE_ENV=pilot`.
- **Modo:** SOLO LECTURA sobre código/DB/configuración. Sin commits, sin migraciones, sin cambios de config. Las únicas mutaciones fueron **datos de prueba en el piloto, autorizados explícitamente por el usuario** (ver *Notas*).

## Veredicto

# NOT READY

Gate de piloto: BLOCKER 0 verificados (1 declarado por el equipo, **no reproducido** en esta auditoría) · BETA FIX 4 · REGRESSION 0 · `flutter analyze` PASS · `flutter test` 189/189 PASS · SQL 9/9 PASS · E2E 6/6 PASS.

Causa principal del NO READY: **no existe todavía un artefacto de build de piloto que contenga el Home objetivo** (el único APK release no lo incluye y el Home nuevo + migración `…29` viven solo en `fix/map-r5-r6`, sin mergear a `main`), más 2 hallazgos técnicos abiertos (desmontaje de MapLibre con resultado vacío, duplicidad de guardas del stepper de agua/validación de fotos) y 4 POLISH.

## Checklist

| Ítem | Estado | Evidencia (sin secretos) |
|------|--------|--------------------------|
| BUILD / artefacto | ⚠️ BETA FIX | `app-debug.apk` 22-sep 15:25: contiene el Home nuevo (strings en `kernel_blob.bin`), apunta al cloud piloto (URL extraída del binario); instalado en device (`lastUpdateTime` 15:25:30). `app-release.apk` 20-sep 18:27: **no** contiene el Home nuevo (ausente en `lib/arm64-v8a/libapp.so`). |
| HOME | ✅ PASS | Banner, Resumen de hoy (9 reportadas · 0 validadas → 10 tras el reporte de prueba; Resueltas hoy 0; "Agua en tu sector: Llegó · hace 23 min" = `event_time` real), 3 acciones exactas, 4ª acción ausente, sin `RecentLeaksList` montado, Actividad reciente poblada ("Los Cerritos · Maneiro · hace 45 min · 0 validaciones · Activa"), nav de 5 pestañas, sin botones muertos. |
| LEAK_REPORT | ✅ PASS (con reserva) | Flujo real en device: permiso GPS, captura GPS 11.01891/-63.82649, reverse-geocode cloud con sugerencia visible ("Sugerido según ubicación GPS") y aviso "Municipio y sector se confirman por separado", sugerencias de municipio y sector, fallback manual (diálogo lat/lng), foto presente, y **persistencia real** en el piloto: `000c9969…` ACTIVE, lat 11.0188853 / lng -63.826492 (= GPS sin alterar), sector Los Cerritos / municipio Maneiro. Duplicados: PASS por E2E. **Reserva:** el diagnóstico del equipo declara crash al tomar/elegir foto; verificado el hueco de código (`on Exception` no captura `Error`), **no reproducido** aquí. |
| GPS | ✅ PASS | GPS es la fuente geométrica: `requestGps()` fija coordenadas y `LocationSuggestion` devuelve `municipalityId/sectorId = null` (nunca convierte texto en selección); las sugerencias solo pueblan campos `suggested*`; edición manual explícita; el reporte persistido conserva las 5 decimales del GPS. |
| WATER | ✅ PASS | "Llegó"/"Se fue", stepper Municipio→Sector→Resumen, hora automática + **editable** ("Hora del evento · Editar"), historial con municipio/sector, resumen honesto ("Sin datos suficientes"), y **2 eventos WATER_ARRIVED persistidos** en el piloto con sus notificaciones, con el Resumen del Home actualizado. |
| MAP | ⚠️ BETA FIX | Basemap OpenFreeMap Liberty con calles/topónimos, leyenda 3 estados, filtros (6 opciones), zoom +/− funcional, markers coherentes con la BD, **sin blink/reset tras pan** (2 capturas separadas 10 s byte-idénticas). **Hallazgo:** con resultado vacío `map_screen.dart:87-98` devuelve `_MapEmptyView` y desmonta MapLibre — reproducido: filtro "Mi sector" → píxeles de mapa 506 438 → 3 146 (pantalla 95 % blanca); al volver a "Todas" se recrea (recuperación OK). |
| COMMUNITY | ✅ PASS | Ciclo real sin resolución prematura: E2E 27 asserts (VALIDATED → duplicado → sigue ACTIVE en 1/3 y 2/3 → RESOLVED a la 3ª identidad) + concurrencia. En el piloto: 1 fuga RESOLVED con `validation_count=3` y `resolution_confirmation_count=3`; otra ACTIVE con `rc=1`. |
| FCM | ✅ PASS (con matiz) | Evento de agua → trigger → fila en `notifications` (2 entradas visibles en la bandeja del teléfono) → recepción FCM en el dispositivo (logcat del propio `com.gota.app` + `FcmRetry`, 1–2 s tras cada evento). Matiz: la notificación **de sistema** (tray) no se observó porque ambas recepciones ocurrieron con la app en primer plano (por diseño solo refresca la bandeja); el intento en segundo plano quedó empatado (~1 s entre HOME y el push). Sin PII en el payload. |
| SECURITY | ✅ PASS | Probes con JWT anon: 401 en `created_by`, `notifications`, `notification_tokens`, `report_validations`, `rate_limit_tracking`, `app_users`, `system_config`, `audit_events`, `report_photos`, `water_event_validations` y `POST /rest/v1/reports`; bucket `report-photos` privado (`public=false`); `validation_threshold` inaccesible (revoke efectivo); escritura RPC-only; RLS activo en todas las tablas públicas; secretos fuera del repo (`.env` y `google-services.json` gitignored). |
| ANDROID | ⚠️ BETA FIX | `applicationId=com.gota.app`, `google-services.json` project `gota-staging` con `package_name` correcto, manifiesto fusionado con `FirebaseMessagingService`/`MESSAGING_EVENT`, permisos de ubicación/INTERNET/POST_NOTIFICATIONS concedidos, Firebase inicializa en device, instalación sin mismatch. **Hallazgo:** el APK release no contiene el Home de piloto y el Home nuevo no está en `main`. |
| TESTS | ✅ PASS | `flutter analyze` → No issues (exit 0). `flutter test` → 189/189. SQL 9/9 PASS. E2E 6/6 PASS. Migración `20260922000029` aplicada (cloud responde 200 en `get_latest_community_activity`). |

## Clasificación de hallazgos

### BETA FIX
1. **Mapa se desmonta con resultado vacío** — `map_screen.dart:87-98` (`reports.isEmpty` → `_MapEmptyView`): la instancia MapLibre se destruye y, al volver a un filtro con datos, se recrea (pierde cámara). Reproducido en device. Fix esperado: mantener el mapa montado y superponer el mensaje vacío.
2. **APK release obsoleto** — `app-release.apk` (20-sep) no incluye el Home objetivo (verificado por strings en `libapp.so`). Reconstruir release desde la rama del piloto antes de distribuir.
3. **Home de piloto no mergeado** — el Home nuevo y la migración `…29` solo existen en `fix/map-r5-r6`; `main` sirve el Home anterior. Definir rama de build/merge.
4. **Viewport refetch sin debounce** — declarado por el diagnóstico del equipo (525725c); no medido en esta auditoría.

### POLISH
1. Ajustes: "Notificaciones de agua" puede activarse **sin** sector de interés (a restringir, según pedido del usuario).
2. Flujo de agua: el `Stepper` material muestra "Continue"/"Cancel" en inglés dentro de UI española.
3. El `Stepper` permite llegar a Resumen con municipio/sector sin elegir (el RPC lo rechaza con `VALIDATION_ERROR`): falta guarda en cliente.
4. Los tiempos relativos no avanzan mientras la pantalla vive (mostró "hace 10 min" con 45 min reales; al recargar, correcto).
5. Con sector de interés activo, "Fallas activas" del Home queda acotado al sector (0) mientras el mapa muestra 10 → posible confusión.

### INFO
- 3 usuarios anónimos residuales en el Docker local por las suites E2E del propio repo.
- Aparecieron durante la auditoría el commit docs-only `525725c` y el archivo sin trackear `docs/PROMPT_EQUIPO_ARQUITECTURA_2026-09-22.md` (no generados por el auditor).
- Datos de prueba escritos en el piloto con autorización explícita: 1 reporte de fuga (`000c9969…`), 2 eventos de agua (`77a65e90…`, `01cea612…`), 2 notificaciones y 1 fila de `notification_preferences` (sector de interés = Urbanización Guanare). No eliminados: la auditoría prohíbe mutar la BD.

### BLOCKER
- **0 verificados.** 1 declarado por el equipo y **no reproducido**: crash al tomar/elegir foto (`leak_report_controller.dart:307` usa `on Exception`, que no captura `Error` nativo; el diagnóstico propone además bajar el límite de fotos de 3 a 2 con `system_config.photo_limits`). Requiere reproducción con cámara/galería antes de clasificar.

### REGRESSION
- **0.** R1 (Water Events), R2 (History), R3 (validación/resolución), R4 (Mapa), D2 (arquitectura GPS), B1 (UX de ubicación), FCM, `notify-push`, webhook→FCM y `com.gota.app` siguen verdes.

## Notas

- Ambos artefactos APK existen en `build/app/outputs/flutter-apk/`; el de debug (212 MB) apunta al cloud piloto, el release no contiene el Home nuevo.
- La recepción FCM se evidenció por logcat del propio paquete (hilo Firebase + `FcmRetry`), no por suposición.
- Se usó un helper propio de captura/medición de pantalla (pixel-banding) para localizar controles y medir el montaje del mapa.

## Acción necesaria

1. **Fusionar/decidir la rama del piloto** (`fix/map-r5-r6` → `main`) y **reconstruir el APK release** desde esa rama con `dart-define` de piloto + `google-services.json`; instalarlo y repetir el smoke en dispositivo (es el único paso que desbloquea el gate de build).
2. **Mapa:** no desmontar MapLibre cuando el resultado es vacío (mantener la instancia y superponer el mensaje) + debounce del refetch por viewport.
3. **Fotos:** reproducir el crash con cámara/galería; cambiar `on Exception` por captura de `Error`/`PlatformException`; decidir el límite (3 vs 2) alineando cliente y `system_config.photo_limits`.
4. **Stepper de agua:** localizar Continue/Cancel y bloquear "Continuar" hasta elegir municipio/sector (o precargar la sugerencia en el borrador).
5. **Ajustes:** impedir activar "Notificaciones de agua" sin sector de interés.
6. **FCM:** prueba final de notificación de sistema con la app cerrada (el gate exige bandeja **y** tray).
7. **Higiene:** limpiar los datos de prueba del piloto (requiere service-role) y los anónimos residuales del Docker local.
8. Re-ejecutar los gates (`flutter analyze`, `flutter test`, suites SQL/E2E) sobre el build release y repetir este informe para el veredicto READY.