# GOTA — Prompt de traspaso (sesión nueva, 2026-09-23)

> Pegar este bloque completo como primer mensaje de la sesión nueva. Sustituye a cualquier contexto previo:
> todo lo necesario está enlazado abajo. Léelo primero, luego propón plan y modelo (gate del usuario) antes de ejecutar.

---

## 0. Rol y regla de arranque

Eres el agente que **continúa** el trabajo del 2026-09-22/23. No repitas lo ya hecho: su salida está en el repositorio y en `docs/audits/`.

**Antes de ejecutar cualquier cosa, propón con `clarify`:** (a) el plan, (b) quién ejecuta y **qué modelo**, y (c) si hay push/merge/deploy, pedir aprobación explícita. Reinspecciona `git log`/`git status`/`git branch` para confirmar la base antes de proponer.

**Política de modelos por capa de coste (instrucción explícita del usuario: *"no uses Sonnet para test, para test usa un modelo gratuito o muy barato"*):**

| Tarea | Motor |
|---|---|
| Tests, copy, cambios mecánicos | gratis o lo más barato: `opencode run --model opencode/ling-3.0-flash-fin-free` (probado, $0), Copilot `gpt-5-mini` por cuota, Ollama local (`qwen3-coder-instruct-128k`) |
| Diagnóstico y refactors con criterio | Sonnet (Claude Code) |
| Arquitectura y dictámenes | Opus |
| Verificación mecánica (analyze/test/mutación, adb, git) | Hermes directo, sin agente |

Coste real de referencia de esta tanda: prompt 1 (fotos) 40 turnos/$1.62, prompt 2 (mapa) 17/$1.61, prompt 4 (sector) 28/$2.32 con Sonnet; prompt 3 con Haiku 20/$0.33 (**rechazado**: tests vacíos); reintento de tests con `opencode` free $0 (≈25 min de máquina). **La suite verde no es evidencia: el criterio es el control de mutación** (revertir el fix debe hacer fallar los tests nuevos).

## 1. Proyecto y entorno

- **Gota**: app Flutter (Android) + Supabase para reportar fugas/eventos de agua. Piloto controlado en la Isla de Margarita.
- **Repo local:** `D:\Proyectos\Gota\v0.2` (bash MSYS; `psql` no está en PATH → `docker exec -i supabase_db_gota psql -U postgres -d postgres`).
- **Ramas:** `main` = `a5d008e` (ya contiene todo lo de esta sesión, pusheado). `fix/map-r5-r6` = el mismo commit (fast-forward, quedó idéntica). **No hay rama pendiente de merge.**
- **Docs fuente de verdad:** `docs/FUNCTIONAL_SPEC.md`, `docs/UX_SPEC.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `docs/API_SPEC.md`, `docs/REVIEW_CHECKLIST.md`; auditorías + índice en `docs/audits/INDEX.md`.
- **Cloud piloto:** proyecto `eghphmugrrbvbvodhasq` (`SUPABASE_ENV=pilot`), credenciales en `.local-supabase-pilot.env` (**nunca imprimir claves**; al usar el env: `set -a && . <(tr -d '\r' < .local-supabase-pilot.env) && set +a`).
- **Docker local:** `supabase_db_gota` :54322, `supabase_kong_gota` :54321. El edge-runtime local **no emite logs**: validar edge functions en cloud.
- **Device físico:** Samsung SM-A245M, Android 16, 1080x2340, serial `R58W709201M`, paquete `com.gota.app`, RAM total 3.77 GB.
  `adb` = `C:/Users/arqui/AppData/Local/Android/Sdk/platform-tools/adb.exe`.

### Trampas de entorno ya resueltas (no las redescubras)

1. **`flutter build apk` muere con `ERROR: JAVA_HOME is set to an invalid directory: ...jdk-17.0.20.101-hotspot`** (el JDK no existe). Solución, sin tocar el sistema:
   `export JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot'` y verificar `"$JAVA_HOME/bin/java" -version`.
2. **Un build fallido deja el APK viejo en su ruta**: mirar `ls -la` del APK engaña. Exigir **mtime nuevo + sha256**.
3. **`versionName` no distingue builds** (`1.0.0+1` no cambia). Para probar que el device corre el build nuevo: `adb pull` del `pm path` + **sha256 contra el APK compilado**.
4. **`adb pull` a `/tmp` falla** en este host: usar un directorio propio del scratch.
5. Las pantallas Flutter **no siempre aparecen en `uiautomator dump`** (los tiles de foto, por ejemplo): localizar los controles por **análisis de píxeles** del PNG (bbox del botón azul, etc.) en vez de confiar en estimaciones visuales de un modelo.
6. En el selector de fotos de Android, "Done" está en la barra inferior (≈ `(950, 2126)` en 1080x2340); puede ignorar taps desviados. En el visor de Samsung, confirmar la captura es `OK` ≈ `(784, 2103)`.
7. Coordenadas útiles del flujo: tab **Reportar** ≈ `(540, 2092)`, "Usar mi ubicación (GPS)" ≈ `(540, 774)`, "Continuar" del asistente ≈ `(540 ó 787, 2092)`, tile de foto con 0 fotos ≈ `(180, 750)` y con 1 foto ≈ `(500, 825)`, hoja "Tomar con la cámara" ≈ `(540, 1969)` / "Elegir de la galería" ≈ `(540, 2126)`.

## 2. Estado exacto al cierre (léelo, no lo re-derives)

**Repositorio:** `main` = `origin/main` = `a5d008e`. `flutter analyze` **No issues** y **209/209 tests** corridos sobre `main` por el orquestador. Árbol limpio.

**Commits de esta sesión (ya en `main`):**

| Commit | Qué |
|---|---|
| `10e6826` | `fix: stabilize leak report photos and form state` — tope 2 fotos, seam `PhotoCompressCall`, presupuesto 1280 px @75 de un solo pase, "Continuar" con preselección (prompts 1, 3, 7) |
| `70e6a2f` | `fix(map)` — el área vacía no desmonta MapLibre ni limpia los bounds (prompt 2) |
| `39485f5` | `fix(notifications)` — no perder ni ocultar el sector de interés al guardar (prompt 4) |
| `e441a0b`, `7ab7ae8`, `a5d008e` (+1) | `docs:` plan revisado v4/v5, `PROMPT_5_UX`, `PROMPT_6_IS_SAVING`, `PROMPT_7_PRESUPUESTO_FOTO`, auditoría de device |

**Prompts del plan:** 1 (fotos), 2 (mapa), 3 (Continuar), 4 (sector) y 7 (presupuesto de foto, adoptado del prompt del dueño) **implementados y verificados** con control de mutación. **Prompt 5 (UX) y prompt 6 (`_isSaving`) tienen spec escrita y NO están ejecutados**.

**Artefacto de piloto:** APK release compilado desde la rama con los `--dart-define` de piloto, sha256 `fa5d37aa9944e1e5d485c43a94917b1b9d9a2145409d9c9278bddb961bf6dfd4`, **instalado y verificado en el device** (sha256 del `base.apk` idéntico). Ese APK **no** debe distribuirse: el gate F6 no está cerrado.

**QA en device (informe completo: `docs/audits/2026-09-23_device_qa_build_piloto.md`) — 8 PASS:**

Home de piloto presente en el APK · mapa que no se desmonta con resultado vacío (1.061.452 px no-blancos en los 4 estados de filtro; el bug era 506.438 → 3.146) · contador "Fotos agregadas: N **de 2**" · tercera foto sin camino (el tile desaparece) · "Continuar" **habilitado** con municipio/sector preseleccionados por GPS · flujo completo hasta Revisar · cierre del asistente sin crash · ruta de galería con borrador conservado.

**BLOCKER ABIERTO (el más importante del repo hoy):** la ruta de **cámara** mata la app y **pierde el borrador**. Evidencia cruda:

```
23:54:11.386 lmkd: Reclaim 'com.gota.app' (30364), oom_score_adj 700, state 15
                  to free 113444kB rss, 138548kB swap; reason: min watermark
23:54:11.616 Zygote: Process 30364 exited due to signal 9 (Killed)
```

**No es una excepción**: `logcat -b crash` y `dumpsys dropbox` están vacíos para Gota (ni FATAL ni ANR). Es el **low-memory killer**, con la cámara en primer plano y el teléfono justo (940 MB disponibles; ese minuto el LMK también reclamó Settings, GMS, Photos y Facebook). La app venía pesando **PSS 241 MB / RSS 279 MB** tras visitar el mapa. Es el "cierre al tomar foto" que la auditoría RC había declarado **no reproducido** (reproduce por cámara y bajo presión, no por galería).

**NOT VERIFIED (no tratar como PASS):** FCM con la app cerrada (falta vía de envío de push en este entorno) · mensaje de confirmación sin GUID (prompt 5 no ejecutado, por eso el GUID sigue) · el kill por cámara ¿es determinista en frío? (solo se aisló bajo presión) · A1/A2 del límite de fotos en base de datos.

**Estado de los worktrees** (los cinco están en `bbef6ae`, detached HEAD): `tanda1-fotos`, `tanda1-mapa`, `tanda1-sector`, `tanda2-continuar`, `tanda2-tests-free`. Cada uno tiene `PROMPT*.md` sin trackear.

**Verificado con hashes (normalizando CRLF) antes de escribirlo:** `main` contiene todo lo que hay en los worktrees. Lo único exclusivo de un worktree es material **superado**: `tanda2-continuar` y `tanda2-tests-free` conservan la versión anterior de `photo_service.dart` (+23 líneas que `main` ya no tiene porque evolucionaron al seam `PhotoCompressCall`) y `tanda2-continuar` conserva los **3 tests vacíos de Haiku** que se rechazaron (+94 líneas frente al archivo corregido de `main`). `tanda1-fotos` aporta 0 líneas únicas. **Se pueden podar sin pérdida**:

```bash
cd /d/Proyectos/Gota/v0.2
for w in tanda1-fotos tanda1-mapa tanda1-sector tanda2-continuar tanda2-tests-free; do
  git worktree remove --force ".claude/worktrees/$w"
done
git worktree prune
```

El único **a NO reutilizar** es `agent-a429749783d7a8538` (sesiones previas, `683e574`): no lo borres sin revisar antes.

**Lección operativa de esta sesión (para no repetirla):** los diffs de los worktrees se fueron apilando y consolidarlos al final obligó a arqueología con hashes. **Consolidá cada prompt a `main` en cuanto pase su verificación** (analyze + tests + mutación), y anotá el commit en el informe; un worktree que sobrevive a su propio commit es solo deuda.

**Aprobaciones A1–A6 del plan:** A1/A2 (límite `photo_limits.max_count 3 → 2` en local y en cloud piloto; en cloud **solo** `npx supabase db query --linked -f <archivo.sql>`, **prohibido `npx supabase db push`**) siguen **pendientes**. A3 (merge a `main`) quedó **cerrada** hoy. A4 (device) cerrada. A5 (medir `onCameraIdle` antes de cualquier debounce) y A6 (limpieza de datos de prueba en el piloto, requiere service-role) **pendientes**.

**Residuo de datos en el piloto:** datos de prueba escritos con autorización del usuario (1 reporte, 2 eventos de agua, 2 notificaciones, 1 `notification_preferences`) + 3 anónimos del Docker local. En esta sesión de QA **no se envió ningún reporte nuevo** (el asistente se cerró antes de "Enviar reporte"). **No eliminar sin service-role y aprobación.**

## 3. Trabajo pendiente, en orden recomendado

**T1 — BLOCKER de memoria (prioridad máxima para el piloto).** **Spec escrita y PENDIENTE DE EJECUTAR:
`docs/PROMPT_8_BORRADOR_PERSISTENTE_2026-09-23.md`** (incluye la recuperación de la captura perdida con
`retrieveLostData`, que es el único camino que devuelve la foto tomada, y el seam `DraftStore`). Antes de
ejecutarla hay que resolver el gate del §8 de esa spec (TTL, UX de reanudación, `path_provider` como
dependencia directa, motor). Especificar e implementar, en este orden: (a) **persistir el borrador** del asistente y reanudarlo si el proceso muere (es la única mitigación que salva el caso raíz: la muerte la decide el sistema), y (b) **reducir la huella base** (liberar/desmontar MapLibre al salir de la pestaña del mapa, acotar caché de tiles) con medición de PSS en frío y después de usar el mapa. El presupuesto de foto ya enviado reduce el pico del pipeline, pero no protege del kill ocurrido con la cámara en primer plano. Criterio de cierre: repetir la corrida de cámara del §2 y demostrar que el borrador **sobrevive** (o que el PSS baja lo suficiente para que el LMK no elija a Gota con la cámara abierta).

**T2 — Prompt 5 (UX).** Spec lista en `docs/PROMPT_5_UX_2026-09-23.md`. Incluye: quitar la leyenda bajo "¿Dónde está la fuga?", copy del paso de fotos, quitar el GUID del mensaje de confirmación, "Resumen de hoy" y el chip "Nuevo", y el orden/limpieza del bloque de agua. **Incluye el punto 5.4 (orden), restituido**: la revisión v5 lo había descartado afirmando que «el orden
pedido ya es el actual», y eso es **falso** contra el código — hoy en el paso de datos el orden es
`Dirección (601-633) → Municipio (643-661) → Sector (676-682) → Descripción (684-692)`, y el plan exige
`Municipio → Sector → Dirección → Descripción`. Decisión del dueño (2026-09-23): **se ejecuta el
movimiento**. Detalle en `docs/PROMPT_5_UX_2026-09-23.md` C4. Las coordenadas (`'Lat: …'`) siguen en el
paso de ubicación (`:190`): traerlas al paso de datos sería un cambio nuevo, no especificado.

**T3 — Prompt 6 (`_isSaving`).** Spec en `docs/PROMPT_6_IS_SAVING_2026-09-23.md`: sustituir `copyWithPrevious` (API `@internal` de Riverpod, hoy usada con `// ignore: invalid_use_of_internal_member` en `notification_providers.dart:68-69`) por un flag propio. Criterio verificable: `grep -c` de `copyWithPrevious` y de `invalid_use_of_internal_member` en `lib/` → **0**.

**T4 — A1/A2.** `system_config.photo_limits.max_count` de 3 a 2 en local y en el cloud piloto (comandos exactos en `docs/PLAN_IMPLEMENTACION_2026-09-22.md`; en cloud solo `db query --linked`, nunca `db push`). Cierra la asimetría cliente/servidor: hoy el cliente bloquea la tercera foto, pero la RPC todavía la aceptaría de otro cliente.

**T5 — Cerrar los NOT VERIFIED de device:** FCM con la app cerrada (notificación de sistema) y, si el dueño lo pide, repetir la ruta de cámara tras T1.

**T6 — Higiene:** podar los cinco worktrees y los `PROMPT*.md` sin trackear una vez confirmado que `main` tiene todo.

Después de T1–T5: **re-auditoría F6** (analyze + tests + SQL + E2E + smoke en device) y veredicto de gate. **No distribuir ningún APK antes de eso.**

## 4. Reglas duras

1. **Nunca imprimir secretos** (anon key, JWT, service-role, tokens, FCM): `[REDACTED]`; enmascarar cualquier `.env`.
2. **No cambiar** backend/RPC/contrato de datos/RLS/migraciones salvo evidencia directa de que es imprescindible; justificar con `archivo:línea`.
3. **No crear infraestructura de tests nueva** ni borrar/marcar `skip` tests existentes.
4. **Un informe por cambio con evidencia real** (`archivo:línea`, salida de comandos). "No probado" **nunca** es PASS; lo no verificable se marca `NOT VERIFIED`.
5. **Un fix sin control de mutación no está verificado**: revertir el cambio debe hacer fallar los tests nuevos. Prohibido reimplementar la lógica de producción dentro del test.
6. **No commitear ni pushear** nada no acordado; los docs van en commits `docs-only` separados de los cambios de código (el usuario pide que los docs queden trackeados, no untracked).
7. Clasificar todo hallazgo como `BLOCKER` / `BETA FIX` / `POLISH` / `REGRESSION` / `PASS`.
8. **Gate de piloto:** `READY FOR CONTROLLED PILOT` solo si BLOCKER = 0, BETA FIX = 0, REGRESSION = 0, E2E crítico PASS, smoke en device PASS, analyze PASS, tests PASS, FCM real PASS, GPS/reporte PASS y mapa PASS. Hoy: **BLOCKER = 1** (memoria/cámara).

## 5. Primeras acciones que espero de ti (en este orden)

1. Reconfirmar la base: `git log --oneline -3`, `git status --short`, `git branch --show-current` en `D:\Proyectos\Gota\v0.2`, y `adb devices`.
2. Leer `docs/audits/2026-09-23_device_qa_build_piloto.md` y `docs/PLAN_IMPLEMENTACION_2026-09-22.md` (secciones de prompts y aprobaciones).
3. Proponerme con `clarify`: (a) si arrancamos por **T1** (blocker de memoria) escribiendo primero el spec en `docs/` para que yo lo revise, (b) qué modelo ejecuta cada tarea según la tabla del §0, y (c) si autorizo el spec de T1 antes de tocar código.
4. No ejecutes nada de código ni de deploy hasta que responda.