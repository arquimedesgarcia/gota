# PROMPT 8 — BORRADOR PERSISTENTE DEL ASISTENTE (T1, BLOCKER de memoria)

**Origen:** T1 del traspaso (`docs/PROMPT_TRASPASO_2026-09-23.md` §3) — el blocker abierto del piloto:
la ruta de cámara mata la app por low-memory killer y **pierde el borrador**.
**Clasificación:** BLOCKER.
**Estado:** spec escrita, **nada ejecutado**. Pendiente: revisión del dueño + elección de motor (§8).

---

## 1. Qué cambia

1. **Persistir el borrador** del asistente (estado + fotos) en disco y **reanudarlo** si el proceso muere.
2. **Recuperar la captura perdida**: cuando Android mata la app con la cámara en primer plano, la foto
   tomada sigue siendo recuperable por el plugin (`retrieveLostData`). Hoy se descarta.
3. **Medir** la huella base (PSS en frío y después del mapa) antes de tocar nada de MapLibre. La
   reducción de huella es un segundo paso **condicionado a esa medición** (ver §7).

## 2. Por qué (evidencia, no hipótesis)

```
23:54:11.386 lmkd: Reclaim 'com.gota.app' (30364), oom_score_adj 700, state 15
                  to free 113444kB rss, 138548kB swap; reason: min watermark
23:54:11.616 Zygote: Process 30364 exited due to signal 9 (Killed)
```

No hubo excepción ni ANR (`logcat -b crash` y `dumpsys dropbox` vacíos para Gota): **el sistema decidió
la muerte**. Ningún código de la app puede impedirla; lo único que la app puede garantizar es que el
trabajo del usuario **sobreviva** a ella. PSS 241 MB / RSS 279 MB con el teléfono en 940 MB disponibles
(ese minuto el LMK también reclamó Settings, GMS, Photos y Facebook).

Punto fino que decide el diseño: la foto se tomó **mientras la app estaba en segundo plano** (cámara en
primer plano). Guardar el estado «al volver» no sirve — no se vuelve. Hay que guardar **antes** de abrir
el picker y recuperar el resultado **al arrancar de nuevo**.

## 3. Diseño propuesto

### 3.1 Puerto de persistencia (seam, mismo precedente que `PhotoCompressCall`)

`lib/features/leaks/data/draft_store.dart`

```dart
abstract class DraftStore {
  Future<LeakDraftSnapshot?> read();
  Future<void> write(LeakDraftSnapshot snapshot);
  Future<void> clear();
}
```

- `FileDraftStore`: JSON versionado en el directorio de soporte de la app
  (`getApplicationSupportDirectory()/report_draft.json`), escritura atómica (write a `.tmp` + `rename`).
- `InMemoryDraftStore` para tests (sin filesystem, sin `path_provider`).
- Inyección: `final draftStoreProvider = Provider<DraftStore>(...)`, sustituible en tests por el store
  en memoria — igual que `photoServiceProvider` (`photo_service.dart:153`).

**Decisión de dependencia:** `path_provider` ya está en `pubspec.lock` como transitiva (línea 635), pero
no es dependencia directa. Usarla exige declararla en `pubspec.yaml` + `flutter pub get`. No se introduce
paquete nuevo, solo se hace explícita una que ya se resuelve.

### 3.2 Qué se persiste

Snapshot **versionado** (`schemaVersion: 1`), derivado del estado real del controller
(`leak_report_controller.dart:25-92`):

| Campo | Persistir | Motivo |
|---|---|---|
| `currentStep`, `draft.location`, `draft.municipalityId`, `draft.sectorId`, `draft.description` | sí | es el trabajo del usuario |
| `draft.photos` (id, compressedPath, mimeType, sizeBytes) | sí | ver 3.3 |
| `originalPath`, `width`, `height` | sí, pero **no se exige** que exista al restaurar | rutas de cache del picker |
| `message`, `outcome`, `submitState`, `suggestionLoading` | **no** | transitorios |
| `locationSuggestion`, `suggestedMunicipalityId/SectorId` | **no** | se recalculan; persistirlos los dejaría desalineados |

### 3.3 Las fotos tienen que sobrevivir al cache

Hoy el JPEG comprimido se escribe **junto al archivo elegido** (`'${path}_gota.jpg'`,
`photo_service.dart:110`) y el picker entrega rutas dentro del cache de la app — reclamable por el
sistema. Por tanto: al persistir, el archivo comprimido se **copia a un directorio durable**
(`.../report_draft_photos/`), y el snapshot guarda **esa** ruta. Al restaurar se verifica `exists()`;
una foto que ya no está se descarta del borrador (y se informa, no se silencia).

### 3.4 Cuándo se guarda

- **Antes de abrir el picker** (`addPhoto` → `service.pickAndPrepare`, `leak_report_controller.dart:295`)
  — es el punto crítico: si el LMK mata con la cámara en primer plano, el snapshot ya tiene ubicación,
  municipio/sector, descripción y las fotos previas.
- Tras cada mutación del borrador (`selectMunicipality`, `selectSector`, `setDescription`, `removePhoto`,
  `addPhoto` exitoso, ubicación). Con serialización pequeña; si en device aparece coste, se estrangula
  (debounce) **sin** quitar el guardado pre-picker.
- **Al cerrar el flujo**: `clear()` en envío exitoso (`ReportCreated`), en `useExistingReport()` y en
  descarte explícito del usuario. Nunca queda basura tras un envío.

### 3.5 Restauración

En `LeakReportController.build()`: leer snapshot, validar `schemaVersion` y **TTL**; si es válido,
arrancar con ese estado. Si el JSON está corrupto o la versión es desconocida → estado vacío, sin
excepción, y purga del archivo.

**UX de la reanudación (decisión del dueño, §8):** propuesta recomendada = banner discreto en el
asistente («Recuperamos tu reporte sin enviar · Descartar») en vez de reanudar en silencio. El usuario
debe poder ver y descartar lo restaurado; reanudar sin avisar puede parecer que alguien llenó el
formulario por él.

### 3.6 Recuperar la captura perdida (esto es lo que devuelve la foto)

`image_picker` en Android deja la captura en disco cuando el proceso muere mientras el picker está en
primer plano; `ImagePicker.retrieveLostData()` la entrega al próximo arranque. Requisitos:

- Envolver la llamada en un **seam** (`LostDataCall` inyectable) para poder testear el camino sin device,
  igual que el pase de compresión.
- Al encontrar lost data: `prepareFromFile(...)` → añadir al borrador (respetando el tope de 2) → persistir.
- **Verificar la semántica en el código/README del plugin antes de asumirla** (qué devuelve con varias
  fotos, qué pasa en iOS, si el archivo es reutilizable o solo un buffer). Si la verificación contradice
  este diseño, se anota en el informe y se ajusta; no se implementa a ciegas.

## 4. Archivos previstos

| Archivo | Acción |
|---|---|
| `lib/features/leaks/data/draft_store.dart` | **nuevo** — puerto + `FileDraftStore` + codec JSON |
| `lib/features/leaks/data/draft_photo_store.dart` | **nuevo** — copia durable + poda de huérfanas |
| `lib/features/leaks/presentation/leak_report_controller.dart` | hooks de guardado/restauración/limpieza |
| `lib/features/leaks/data/photo_service.dart` | seam de lost data (sin cambiar el pipeline del prompt 7) |
| `lib/features/leaks/presentation/leak_report_screen.dart` | banner de reanudación + descarte |
| `pubspec.yaml` | `path_provider` como dependencia directa |

## 5. Cobertura y control de mutación

Tests nuevos en `test/features/leaks/` (store en memoria; **prohibido** reimplementar la lógica de
producción dentro del test):

| # | Test | Mutación que debe hacerlo fallar |
|---|---|---|
| 1 | mutar borrador (foto + datos) → el store recibe snapshot con esos campos | no llamar a `write` |
| 2 | `build()` con snapshot válido → borrador y paso restaurados | ignorar el snapshot |
| 3 | snapshot corrupto / `schemaVersion` desconocido → estado vacío, sin excepción | propagar la excepción |
| 4 | `addPhoto` persiste **antes** de invocar el picker | mover el guardado después del picker |
| 5 | envío exitoso / `useExistingReport` → `clear()` | no limpiar |
| 6 | TTL vencido → no restaura y purga | ignorar el TTL |
| 7 | foto restaurada cuyo archivo ya no existe → se descarta del borrador | asumir que existe |
| 8 | lost data presente → se añade al borrador y respeta el tope de 2 | ignorar lost data |

Los tests los escribe un motor **gratuito o muy barato** (regla del §0 del traspaso); Sonnet no se usa
para tests.

## 6. Lo que NO cambia

Contrato de datos, RPC `create_leak_report`, RLS/Storage, modelo de datos, tope de 2 fotos y su copy, el
presupuesto 1280@75 del prompt 7, el orden de las tarjetas del paso de datos y el comportamiento del
mapa (prompt 2). No se toca backend sin evidencia directa.

## 7. Parte b — huella base: **medir primero**

Antes de escribir un solo cambio de MapLibre:

1. PSS/RSS en frío con el asistente abierto y sin tocar el mapa.
2. PSS/RSS tras recorrer el mapa y volver a Reportar.
3. PSS/RSS con la cámara abierta en el paso de fotos.

Contexto relevante ya verificado: `app_shell.dart:81` mantiene las pestañas en un `IndexedStack`, así que
el mapa **nunca se desmonta** al cambiar de pestaña, y su estado se conserva a propósito (retirarlo sería
regresión del hallazgo 1 del prompt 2). Por eso la propuesta de «liberar MapLibre al salir de la pestaña»
**no** se implementa sin medición y sin una alternativa que conserve cámara/estado del mapa. Si la
medición muestra que el mapa no es el peso dominante, esta parte se documenta y se cierra sin código.

## 8. Decisiones que necesito del dueño (gate previo a ejecutar)

1. **TTL** del borrador restaurado: propongo **24 h**.
2. **UX de reanudación**: banner con «Descartar» (recomendado) vs. reanudar en silencio.
3. **`path_provider` como dependencia directa** (ya resuelta en el lock) — requiere editar `pubspec.yaml`.
4. **Motor**: Sonnet para el diseño/implementación (es refactor con criterio), modelo gratuito para los
   tests, y verificación mecánica con Hermes.

## 9. Criterio de cierre (medible, no opinable)

1. Suite completa verde + `flutter analyze` sin issues, y **cada test nuevo con su control de mutación**
   ejecutado (revertir el fix hace fallar el test).
2. En device, **repetir la corrida del §2**: tomar la 2ª foto con la cámara bajo la misma presión de
   memoria. Evidencia esperada: si el proceso muere, el pid cambia **pero** al reabrir el asistente el
   borrador está con la foto recuperada. La cifra de PSS antes/después se reporta sin maquillar.
3. Informe con líneas crudas de `logcat` (`lmkd`/`Zygote`) y capturas, en `docs/audits/`, marcando
   `NOT VERIFIED` lo que no se haya podido medir. El kill es del sistema: si no se reproduce en la
   corrida de cierre, se dice así en vez de declarar PASS.