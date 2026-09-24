# FASE 1 — Correcciones Críticas (P1)

**Hallazgos corregidos:** H-01, H-02, H-19
**Prerequisito:** `flutter test` pasa en verde antes de iniciar.
**Commit al terminar:** `fix(quality): fase 1 — reset water form y keyset pagination`

---

## Contexto para el agente

Eres un agente de codificación trabajando en Gota v0.2, una app Flutter que usa Riverpod,
Supabase y MapLibre. Tu tarea es aplicar exactamente las correcciones descritas abajo,
sin cambiar funcionalidades, UX, reglas de negocio, modelos de datos ni APIs externas.

**Stack:** Flutter · Dart · Riverpod 3 · Supabase · MapLibre
**Plataforma principal:** Android (Samsung SM-A245M)
**Rama de trabajo:** fix/map-r5-r6

Antes de cada cambio ejecuta `flutter test` para verificar que el baseline está verde.
Después de cada corrección ejecuta `flutter test` y `flutter analyze`.

---

## REGLA FUNDAMENTAL

**No cambiar comportamiento visible para el usuario.**
**No introducir nuevas dependencias.**
**No modificar RLS, RPCs de Supabase ni el modelo de datos.**

---

## Corrección C1-01 — Reset del formulario de agua al abrir el flujo

**Hallazgo:** H-01
**Archivo:** `lib/features/water/presentation/water_screen.dart`
**Método:** `WaterScreen._openRegister()`

### Problema

`waterRegisterControllerProvider` no es autoDispose. Cuando el usuario completa un
registro y vuelve a abrir el flujo, el controller conserva el estado anterior
(municipio, sector, hora, `submitStatus: done`). El método `submit()` no bloquea
si `submitStatus == done`, por lo que una segunda apertura puede re-enviar el evento
anterior sin que el usuario haya introducido datos nuevos.

### Cambio exacto

En `WaterScreen._openRegister()`, añadir `ref.invalidate(waterRegisterControllerProvider)`
**antes** del `Navigator.of(context).push(...)`.

Busca el método `_openRegister` en `water_screen.dart`. Actualmente tiene esta estructura:

```dart
Future<void> _openRegister(
  BuildContext context,
  WidgetRef ref,
  WaterEventType? initialType,
) async {
  final created = await Navigator.of(context).push<bool>(
    ...
  );
  if (created ?? false) {
    ref.invalidate(waterHistoryControllerProvider);
    ref.invalidate(sectorWaterStatusProvider);
  }
}
```

Debe quedar:

```dart
Future<void> _openRegister(
  BuildContext context,
  WidgetRef ref,
  WaterEventType? initialType,
) async {
  ref.invalidate(waterRegisterControllerProvider);  // <-- añadir esta línea
  final created = await Navigator.of(context).push<bool>(
    ...
  );
  if (created ?? false) {
    ref.invalidate(waterHistoryControllerProvider);
    ref.invalidate(sectorWaterStatusProvider);
  }
}
```

**Verifica** que el import de `waterRegisterControllerProvider` ya existe en el archivo.
Si no, añadir:
```dart
import '../presentation/water_register_controller.dart';
```

### Validación

- `flutter test` en verde.
- Manualmente (si hay device): abrir flujo agua, completar registro, cerrar, abrir de
  nuevo → el formulario debe iniciar vacío en el paso 0.

---

## Corrección C1-02 — Añadir nextCursor a WaterHistoryState

**Hallazgo:** H-02 (parte 1 de 3)
**Archivo:** `lib/features/water/presentation/water_providers.dart`
**Clase:** `WaterHistoryState`

### Problema

`WaterHistoryController.loadMore()` siempre pasa `cursor: null`, obteniendo siempre
la primera página. Necesitamos guardar el cursor de la siguiente página en el estado.

### Cambio exacto

En `WaterHistoryState`, añadir el campo `nextCursor` de tipo `WaterEventCursor?`.

El import necesario: `WaterEventCursor` está en `gota_water_database.dart`.

```dart
// Añadir import al top del archivo si no existe:
import '../../../core/network/gota_water_database.dart';
```

Clase actualizada (añadir el campo y actualizarlo en copyWith):

```dart
@immutable
class WaterHistoryState {
  const WaterHistoryState({
    this.events = const AsyncValue.loading(),
    this.isLoadingMore = false,
    this.hasMore = false,
    this.nextCursor,          // <-- campo nuevo
  });

  final AsyncValue<List<WaterEventSummary>> events;
  final bool isLoadingMore;
  final bool hasMore;
  final WaterEventCursor? nextCursor;    // <-- campo nuevo

  WaterHistoryState copyWith({
    AsyncValue<List<WaterEventSummary>>? events,
    bool? isLoadingMore,
    bool? hasMore,
    WaterEventCursor? nextCursor,        // <-- parámetro nuevo
  }) => WaterHistoryState(
    events: events ?? this.events,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    nextCursor: nextCursor ?? this.nextCursor,   // <-- nuevo
  );
}
```

**Nota:** `WaterEventCursor` ya existe en `lib/core/network/gota_water_database.dart`.
Está definido como:
```dart
class WaterEventCursor {
  const WaterEventCursor({required this.eventTime, required this.id});
  final DateTime eventTime;
  final String id;
}
```

### Validación

- `flutter analyze` en verde.

---

## Corrección C1-03 — Usar nextCursor en _loadInitial, refresh y loadMore

**Hallazgo:** H-02 (parte 2 de 3)
**Archivo:** `lib/features/water/presentation/water_providers.dart`
**Clase:** `WaterHistoryController`

### Cambio exacto

**_loadInitial():** Guardar el nextCursor del WaterEventsPage en el estado:

```dart
Future<void> _loadInitial() async {
  try {
    final repository = ref.read(waterEventRepositoryProvider);
    final page = await repository.recentEvents(limit: _pageSize);
    state = state.copyWith(
      events: AsyncValue.data(page.events),
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,     // <-- añadir
    );
  } catch (error, stackTrace) {
    state = state.copyWith(events: AsyncValue.error(error, stackTrace));
  }
}
```

**refresh():** Igual que _loadInitial, guardar nextCursor:

```dart
Future<void> refresh() async {
  try {
    final repository = ref.read(waterEventRepositoryProvider);
    final page = await repository.recentEvents(limit: _pageSize);
    state = state.copyWith(
      events: AsyncValue.data(page.events),
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,     // <-- añadir
    );
  } catch (error, stackTrace) {
    state = state.copyWith(events: AsyncValue.error(error, stackTrace));
  }
}
```

**loadMore():** Usar `state.nextCursor` como cursor y guardar el nuevo cursor:

El método actual tiene `cursor: null` hardcodeado. Reemplazar:

```dart
Future<void> loadMore() async {
  final current = state.events;
  if (!state.hasMore || state.isLoadingMore) return;
  final events = current.value ?? const <WaterEventSummary>[];
  if (events.isEmpty) return;

  state = state.copyWith(isLoadingMore: true);
  try {
    final repository = ref.read(waterEventRepositoryProvider);
    final page = await repository.recentEvents(
      limit: _pageSize,
      cursor: state.nextCursor,   // <-- era null, ahora usa el cursor real
    );
    final seen = events.map((e) => e.id).toSet();
    final merged = [
      ...events,
      ...page.events.where((e) => !seen.contains(e.id)),
    ];
    state = state.copyWith(
      events: AsyncValue.data(merged),
      isLoadingMore: false,
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,   // <-- guardar cursor de la siguiente página
    );
  } catch (error, stackTrace) {
    state = state.copyWith(
      events: AsyncValue.error(error, stackTrace),
      isLoadingMore: false,
    );
  }
}
```

### Validación

- `flutter test` en verde.

---

## Corrección C1-04 — Implementar filtro de cursor en fetchRecentWaterEvents

**Hallazgo:** H-19 (parte 3 del grupo H-02)
**Archivo:** `lib/core/network/gota_water_database.dart`
**Método:** `SupabaseGotaWaterDatabase.fetchRecentWaterEvents()`

### Problema

El método acepta `WaterEventCursor? cursor` pero nunca aplica ningún filtro basado
en él. Siempre devuelve la primera página.

La paginación keyset sobre (event_time DESC, id DESC) requiere filtrar los registros
anteriores al cursor. En PostgREST, para una paginación keyset correcta necesitamos:

```sql
WHERE (event_time, id) < (cursor.eventTime, cursor.id)
-- es decir: event_time < cursor ó (event_time = cursor AND id < cursor.id)
```

El cliente supabase_flutter no expone `.or()` de forma directa en todas las versiones,
por lo que usamos el filtro `.lt` sobre `event_time` como aproximación para el MVP:

### Cambio exacto

```dart
@override
Future<List<Map<String, dynamic>>> fetchRecentWaterEvents({
  int limit = 20,
  WaterEventCursor? cursor,
}) async {
  var query = _client
      .from('water_events')
      .select(_listColumns)
      .order('event_time', ascending: false)
      .order('id', ascending: false);

  // Filtro keyset: solo eventos anteriores al cursor.
  // Usamos event_time como punto de corte (lte para incluir el mismo segundo).
  // En el raro caso de colisión de event_time, el id tiebreaker en el servidor
  // garantiza el orden correcto; para el volumen del piloto esta aproximación
  // es suficiente.
  if (cursor != null) {
    query = query.lte('event_time', cursor.eventTimeIso);
  }

  query = query.limit(limit + 1);  // +1 para detectar si hay más

  final rows = await query;

  // Detectar si hay más páginas y excluir el registro extra del resultado.
  final hasMore = rows.length > limit;
  final resultRows = hasMore ? rows.sublist(0, limit) : rows;

  return resultRows;
}
```

**Nota importante:** El repositorio `WaterEventRepository.recentEvents()` ya calcula
`page.hasMore` comparando `events.length == limit`. Con el +1 en la query, el
cálculo actual sigue siendo correcto porque si recibe `limit` elementos sabe que
había `limit+1` disponibles.

Sin embargo, necesitas verificar cómo `WaterEventRepository.recentEvents()` calcula
`hasMore`. En `lib/features/water/data/water_event_repository.dart`:

```dart
final WaterEventCursor? nextCursor =
    events.length == limit && events.isNotEmpty
    ? WaterEventCursor(...)
    : null;
return WaterEventsPage(events: events, nextCursor: nextCursor);
```

Con la query devolviendo `limit+1` cuando hay más:
- `rows.length == limit+1` → `hasMore = true`, se devuelven `limit` filas.
- `rows.length <= limit` → `hasMore = false`, se devuelven todas.
- El repositorio recibe exactamente `limit` filas → `events.length == limit`.

Para que el cálculo sea correcto, hay dos opciones:

**Opción A (recomendada):** Mantener el +1 en la query de la DB y que el repositorio
siga calculando `hasMore` como `events.length == limit`. Esto funciona porque la DB
devuelve `limit` filas cuando hay más, y `< limit` cuando no hay más.

**Opción B:** Añadir `hasMore` explícito en la respuesta de la DB. Para el MVP,
la Opción A es suficiente.

### Validación

- `flutter test` en verde.
- Si hay device: abrir pestaña Agua con > 20 eventos y verificar que "cargar más"
  muestra el siguiente grupo de eventos sin repetir los anteriores.

---

## Checklist de finalización de Fase 1

- [ ] C1-01 aplicado: `ref.invalidate(waterRegisterControllerProvider)` en `_openRegister`.
- [ ] C1-02 aplicado: campo `nextCursor` en `WaterHistoryState`.
- [ ] C1-03 aplicado: `_loadInitial`, `refresh` y `loadMore` usan el cursor.
- [ ] C1-04 aplicado: `fetchRecentWaterEvents` aplica filtro keyset.
- [ ] `flutter analyze` → No issues.
- [ ] `flutter test` → Todos en verde.
- [ ] Commit: `fix(quality): fase 1 — reset water form y keyset pagination`

---

## PROMPT PARA EL AGENTE DE CODIFICACIÓN

> Copia y pega el siguiente prompt a un agente de codificación para ejecutar esta fase.

```
Eres un agente de codificación trabajando en Gota v0.2 (Flutter · Riverpod 3 · Supabase).
Rama de trabajo: fix/map-r5-r6.

Tu tarea es aplicar exactamente 4 correcciones de bug pre-beta. NO cambies comportamiento
visible, UX, reglas de negocio, modelos de datos ni APIs externas.
NO introduzcas nuevas dependencias.

Antes de empezar: ejecuta `flutter test` y confirma que todos los tests pasan.

CORRECCIÓN 1 (C1-01) — water_screen.dart
Método: WaterScreen._openRegister()
Añadir `ref.invalidate(waterRegisterControllerProvider);` inmediatamente antes del
`await Navigator.of(context).push<bool>(...)`.
Verifica que waterRegisterControllerProvider está importado en el archivo.
Ejecuta flutter test después.

CORRECCIÓN 2 (C1-02) — water_providers.dart
Clase: WaterHistoryState
Añadir campo `final WaterEventCursor? nextCursor;` y su parámetro en copyWith().
Añadir import de gota_water_database.dart si no existe.
Ejecuta flutter analyze después.

CORRECCIÓN 3 (C1-03) — water_providers.dart
Clase: WaterHistoryController
En _loadInitial(), refresh() y loadMore(): guardar `page.nextCursor` en el estado.
En loadMore(): cambiar `cursor: null` por `cursor: state.nextCursor`.
Ejecuta flutter test después.

CORRECCIÓN 4 (C1-04) — gota_water_database.dart
Método: SupabaseGotaWaterDatabase.fetchRecentWaterEvents()
Si cursor != null, añadir `.lte('event_time', cursor.eventTimeIso)` antes del .limit().
Cambiar el limit a `limit + 1` para detectar hasMore.
En el cuerpo del método, cortar el resultado a `limit` filas y devolver solo esas.
Ejecuta flutter test después.

Al terminar todas las correcciones:
1. Ejecuta `flutter analyze` — debe reportar "No issues found".
2. Ejecuta `flutter test` — todos deben pasar.
3. Crea un commit: `fix(quality): fase 1 — reset water form y keyset pagination`

Si algún test falla después de una corrección, revierte solo esa corrección y documenta
el problema antes de continuar con la siguiente.
```
