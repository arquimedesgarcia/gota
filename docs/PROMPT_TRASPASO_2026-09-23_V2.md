# GOTA — Prompt de traspaso (sesión nueva) · 2026-09-23 v2

> Pegá este bloque completo como primer mensaje de la sesión nueva. Sustituye a
> `docs/PROMPT_TRASPASO_2026-09-23.md` (v1): todo lo de abajo está verificado contra el repo, no contra
> los documentos anteriores.

## 0. Rol, antecedentes y regla de arranque

Eres el agente que **continúa** el trabajo del 2026-09-22/23 en Gota. No repitas lo ya hecho: su salida
está en el repositorio y en `docs/audits/`.

**Antes de ejecutar cualquier cosa, proponé con `clarify`:** (a) el plan, (b) quién ejecuta y **qué
modelo**, (c) si hay commit/push/deploy, pedir aprobación explícita. Reinspeccioná `git log`, `git status`,
`git branch --show-current`, `git worktree list` y `adb devices` antes de proponer.

**Política de motores (instrucción explícita del dueño, actualizada hoy):**

| Tarea | Motor |
|---|---|
| **Trabajo puntual ya especificado** (contrato con `archivo:línea`, tests enumerados), tests, copy, mecánica | **el más barato**: `opencode run --model opencode/ling-3.0-flash-fin-free` ($0, probado), Copilot `gpt-5-mini` por cuota, Ollama local (`qwen3-coder-instruct-128k`), Haiku |
| Diagnóstico abierto (sin causa establecida) y refactors con criterio | Sonnet |
| Arquitectura y dictámenes | Opus |
| Verificación mecánica (analyze/test/mutación/adb/git) y device | el orquestador (Hermes), sin agente |

Regla: **empezá barato y escalá solo si el intento barato falla el criterio de aceptación.** La suite
verde **no** es evidencia: el criterio es el **control de mutación** (revertir el fix debe poner el test
nuevo en rojo).

## 1. Proyecto y entorno

- **Gota**: app Flutter (Android) + Supabase para reportar fugas de agua. Piloto controlado en Margarita.
- **Repo local:** `D:\Proyectos\Gota\v0.2` (bash MSYS). App Flutter Android + Supabase.
- **Device:** Samsung SM-A245M, Android 16, 1080x2340, serial `R58W709201M`, `com.gota.app`, RAM 3.77 GB.
  `adb` = `C:/Users/arqui/AppData/Local/Android/Sdk/platform-tools/adb.exe`.
- **Cloud piloto:** proyecto `eghphmugrrbvbvodhasq` (`SUPABASE_ENV=pilot`), credenciales en
  `.local-supabase-pilot.env` (**nunca imprimir claves**; cargar con
  `set -a && . <(tr -d '\r' < .local-supabase-pilot.env) && set +a`).
- **Docker local:** `supabase_db_gota` :54322, `supabase_kong_gota` :54321 (`psql` no está en PATH →
  `docker exec -i supabase_db_gota psql -U postgres -d postgres`). El edge-runtime local no emite logs.

### Trampas ya pagadas (no las redescubras)

1. `flutter build apk` muere con `ERROR: JAVA_HOME is set to an invalid directory: …jdk-17.0.20.101-hotspot`.
   Solución: `export JAVA_HOME='C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot'` y verificar
   `"$JAVA_HOME/bin/java" -version`.
2. Un build **fallido deja el APK viejo** en su ruta: exigir mtime nuevo + sha256.
3. `versionName` no distingue builds (`1.0.0+1`): comparar **sha256** del APK compilado contra el
   `base.apk` extraído del device (`adb pull` del `pm path`).
4. `adb pull` a `/tmp` falla en este host: usar un directorio propio del scratch.
5. Las pantallas Flutter **no siempre aparecen en `uiautomator dump`**: ubicar controles por análisis de
   píxeles del PNG.
6. Selector de fotos: «Done» ≈ `(950, 2126)`; visor Samsung, confirmar captura ≈ `(784, 2103)`.
7. Coordenadas del flujo: tab **Reportar** ≈ `(540, 2092)`, «Usar mi ubicación (GPS)» ≈ `(540, 774)`,
   «Continuar» ≈ `(540 ó 787, 2092)`, tile de foto 0 fotos ≈ `(180, 750)`, con 1 foto ≈ `(500, 825)`,
   «Tomar con la cámara» ≈ `(540, 1969)`, «Elegir de la galería» ≈ `(540, 2126)`.
8. En los pasos con `ListView`, lo que queda fuera de pantalla **no se construye**: usar
   `tester.scrollUntilVisible(...)`/`ensureVisible` antes de buscar o pulsar.
9. `adb pull`/rutas nativas: pasar rutas `C:/...` a los binarios nativos, no `/c/...`.

## 2. Estado exacto al cierre (verificado por el orquestador, no por el agente)

- **`main` = `origin/main` = `e5ce181`**. Árbol limpio. Nada pendiente de push.
- **Suite: 221/221 en verde** (`flutter test` corrido por el orquestador) y `flutter analyze` sin issues.
- **Commits relevantes:** `fb55dfe` (Tanda A: repara la suite y añade 11 tests), `abc71ac` (R1–R5 del
  prompt 9: borrador persistente, orden del paso Ubicación, copy sin GUID, Home/Agua), `70e6a2f` (mapa: el
  área vacía no desmonta MapLibre), `39485f5` (sector de interés), `10e6826` (fotos: tope 2, seam,
  1280@75, «Continuar»).
- **Implementado y verificado:** H1 mapa (no desmonta con área vacía), H4 sector de interés, H3 «Continuar»
  con preselección (confirmado en device), H2 fotos (tope 2 cliente + presupuesto 1280@75 + `catch` que
  cubre `Error`), `R1` (leyenda fuera), `R2` (orden dirección → coordenadas/precisión → mapa),
  `R3` (sin GUID), `R5` (Home sin «Resumen de hoy» y Agua sin «Resumen», con la constante muerta
  `WaterCopy.summaryTitle` eliminada).
- **Implementado pero SIN verificación de mutación:** `R4` (borrador persistente). El commit `fb55dfe`
  documenta la mutación **solo** de R3; los controles de `T4-1…T4-8` son afirmación del agente. `R4` es el
  **BLOCKER** del piloto, así que esto hay que reverificarlo antes de darlo por bueno.
- **Nuance abierta:** el test `T4-7` dice «foto restaurada cuyo archivo no existe se descarta
  **silenciosamente**»; el spec pedía **informar** al usuario. Confirmar en device; si no avisa, es una
  brecha de UX a decidir.
- **APK del piloto:** el instalado en el device es **anterior** a `abc71ac` (sha256
  `fa5d37aa9944e1e5d485c43a94917b1b9d9a2145409d9c9278bddb961bf6dfd4`, build del 2026-09-23 23:32). Para
  cualquier device pass hay que **recompilar desde el commit verificado** y probar con sha256.
- **Gate F6:** sigue **BLOCKER = 1** (la ruta de cámara mata la app por LMK). No distribuir APK.

## 3. Worktrees (no tocar a ciegas)

`git worktree list` muestra:

- `D:/Proyectos/Gota/v0.2` → `main` @ `e5ce181`.
- `D:/Proyectos/Gota/gota-p10` → rama **`fix/prompt10-suite-y-mapa`** @ **`acffe6a`**: es la rama del
  trabajo del mapa, con **base OBSOLETA** (anterior a `fb55dfe`, cuando la suite tenía 5 rojos). Antes de
  usarla, actualizarla a `fb55dfe`; si no, se ven 5 fallos que ya no existen.
- `.claude/worktrees/tanda1-fotos`, `tanda1-mapa`, `tanda1-sector`, `tanda2-continuar`,
  `tanda2-tests-free` → todos en `bbef6ae` (detached). **Verificado con hashes: no aportan código**; se
  pueden podar (`git worktree remove --force` + `git worktree prune`). El único a **no** borrar sin
  revisar es `.claude/worktrees/agent-a429749783d7a8538` (sesiones previas).

## 4. Pendientes, en orden recomendado

1. **Tanda B · mapa** — spec completa en **`docs/PROMPT_11_DELEGACION_MAPA_Y_CIERRE_2026-09-23.md`**
   (§3–§6: el mapa se monta siempre en modo Mapa y la cámara solo se mueve por acción del usuario).
   Incluye el aviso del worktree obsoleto. Trabajo puntual → **motor barato**.
2. **Reverificar la mutación de `R4`** (`T4-1…T4-8`): revertir cada fix y comprobar que el test cae en
   rojo. Lo ejecuta el orquestador; es lo que falta para poder llamar «verificado» al BLOCKER.
3. **`T4-7`** contra el spec (informar vs silenciar).
4. **T3 · prompt 6** — `docs/PROMPT_6_IS_SAVING_2026-09-23.md`: eliminar `copyWithPrevious` (API
   `@internal` de Riverpod, hoy en `notification_providers.dart:69` con
   `// ignore: invalid_use_of_internal_member`) conservando el valor visible durante el guardado y los 4
   tests del H4. Criterio: `grep -c "copyWithPrevious|invalid_use_of_internal_member" lib/` → **0**.
5. **T4 · A1/A2 (datos, requiere aprobación del dueño)** — `system_config.photo_limits.max_count` de 3 a 2
   en local (`docker exec … psql`, con `SELECT` antes y después) y en el cloud piloto **solo** con
   `npx supabase db query --linked -f <archivo.sql>`. **Prohibido `npx supabase db push`.**
6. **Device pass** (orquestador, con APK recién compilado y sha256 verificado): los 14 pasos del mapa,
   los 16 de Reportar (incluido que **el borrador sobreviva al kill por cámara** y que aparezca el banner
   «Recuperamos tu reporte sin enviar» con «Descartar»), y los 3 de Home/Agua que **nunca** se
   verificaron en device.
7. **Higiene T6** — podar los worktrees y los `PROMPT*.md` sin trackear.
8. **F6** — re-auditoría (analyze + tests + SQL + E2E crítico + smoke en device) y veredicto
   `READY FOR CONTROLLED PILOT`. Sin el punto 6 en verde, el veredicto es `NOT READY`.

## 5. Documentos de referencia (fuente de verdad)

- Especificaciones: `docs/FUNCTIONAL_SPEC.md`, `docs/UX_SPEC.md`, `docs/ARCHITECTURE.md`,
  `docs/DATA_MODEL.md`, `docs/API_SPEC.md`, `docs/REVIEW_CHECKLIST.md`.
- Plan y diagnóstico: `docs/PLAN_IMPLEMENTACION_2026-09-22.md`,
  `docs/DIAGNOSTICO_PRE_IMPLEMENTACION_2026-09-22.md`.
- Specs de delegación vigentes: `docs/PROMPT_5_UX_2026-09-23.md` (incluye el orden del paso Ubicación),
  `docs/PROMPT_6_IS_SAVING_2026-09-23.md`, `docs/PROMPT_8_BORRADOR_PERSISTENTE_2026-09-23.md`,
  `docs/PROMPT_9_DELEGACION_REPORTAR_2026-09-23.md`,
  `docs/PROMPT_10_DELEGACION_HOME_AGUA_Y_MAPA_2026-09-23.md`,
  `docs/PROMPT_11_DELEGACION_MAPA_Y_CIERRE_2026-09-23.md`.
- Auditorías: `docs/audits/INDEX.md`,
  `docs/audits/2026-09-23_device_qa_build_piloto.md` (8 PASS + BLOCKER del LMK con `logcat` crudo).

## 6. Decisiones ya tomadas por el dueño (no reabrir sin motivo)

- El orden del paso de **Datos** (tarjeta de dirección vs dropdowns) **no** se reordena: el requisito se
  resolvió dentro del paso de **Ubicación** (dirección → coordenadas/precisión → mapa), sin duplicar
  información. La frase del plan viejo que pedía moverla después del sector quedó **anulada**.
- Borrador persistente: **TTL 24 h**, banner **«Recuperamos tu reporte sin enviar»** con **«Descartar»**,
  `path_provider` como dependencia directa.
- Los modelos se eligen por coste con la tabla del §0: puntual → barato, diagnóstico → Sonnet,
  dictamen → Opus, verificación y device → el orquestador.

## 7. Reglas duras

1. **Nunca imprimir secretos** (anon key, JWT, service-role, tokens, FCM): `[REDACTED]`; enmascarar los
   `.env`.
2. **No cambiar** backend/RPC/contrato de datos/RLS/migraciones/`system_config` salvo aprobación explícita
   del dueño y con justificación `archivo:línea`.
3. **No crear infraestructura de tests nueva** ni borrar/marcar `skip` tests existentes.
4. **Un informe por cambio con evidencia real** (`archivo:línea`, salida de comandos). Lo no verificado se
   marca `NOT VERIFIED`; «no probado» **nunca** es PASS.
5. **Un fix sin control de mutación no está verificado.** Prohibido reimplementar la lógica de producción
   dentro del test.
6. **No commitear ni pushear** nada no acordado; los docs van en commits `docs:` separados y **trackeados**
   (al dueño le molestan los entregables untracked).
7. Clasificar cada hallazgo como `BLOCKER` / `BETA FIX` / `REGRESSION` / `POLISH` / `PASS`.
8. Cada spec delegada se muestra **en el chat** antes de lanzar cualquier agente, y el agente se lanza
   **después** de la confirmación del dueño.
9. **Prohibido `npx supabase db push`** en cualquier forma. Los comandos mutantes contra la base van por
   `npx supabase db query --linked -f <archivo.sql>` y con aprobación.

## 8. Primeras acciones que espero de ti (en este orden)

1. Reconfirmar la base: `git log --oneline -3`, `git status --short`, `git branch --show-current`,
   `git worktree list`, `adb devices`.
2. Correr `flutter analyze` y `flutter test` **tú mismo** y reportar el conteo real (referencia: **221**).
3. Proponerme con `clarify`: por dónde arrancamos (recomendado: **Tanda B del prompt 11**, con motor
   barato), quién ejecuta y qué modelo, y qué autorizás de commits/push/device.
4. No ejecutes nada de código, de device ni de deploy hasta que responda.