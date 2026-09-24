# FASE 5 — Polish Técnico y Documentación (P3)

**Prerequisito:** Fases 1-4 completadas. `flutter test` en verde.
**Hallazgos cubiertos:** H-09, H-11, H-13, H-14, H-15, H-18, H-20, H-21, H-22, H-23
**Commit al terminar:** `fix(quality): fase 5 — polish técnico y docs`

---

## Corrección C5-01 — Mover _currentStep al WaterRegisterController

**Hallazgo:** H-09
**Archivos:** `lib/features/water/presentation/water_register_screen.dart`
            `lib/features/water/presentation/water_register_controller.dart`

### Problema

`_currentStep` es estado local del `ConsumerStatefulWidget`. Un cambio de configuración
(rotación) lo resetea a 0 mientras el controller conserva los datos del paso 3.

### Cambio exacto

**En `water_register_controller.dart`:**
Añadir el campo `currentStep` a `WaterRegisterState`:
```dart
class WaterRegisterState {
  const WaterRegisterState({
    // ... campos existentes ...
    this.currentStep = 0,   // <-- nuevo
  });
  // ... otros campos ...
  final int currentStep;   // <-- nuevo

  WaterRegisterState copyWith({
    // ... parámetros existentes ...
    int? currentStep,   // <-- nuevo
  }) => WaterRegisterState(
    // ... otros campos ...
    currentStep: currentStep ?? this.currentStep,   // <-- nuevo
  );
}
```

Añadir métodos al controller:
```dart
void goToStep(int step) {
  if (step >= 0 && step <= 3) {
    state = state.copyWith(currentStep: step);
  }
}
void nextStep() => goToStep(state.currentStep + 1);
void previousStep() => goToStep(state.currentStep - 1);
```

**En `water_register_screen.dart`:**
Convertir `_WaterRegisterScreenState` de `ConsumerStatefulWidget` a `ConsumerWidget`
(si solo se usaba para _currentStep). Si hay otras razones para mantenerlo Stateful,
eliminar únicamente `_currentStep` y usar `state.currentStep` del provider.

Reemplazar:
```dart
setState(() => _currentStep++);   →   ref.read(waterRegisterControllerProvider.notifier).nextStep();
setState(() => _currentStep--);   →   ref.read(waterRegisterControllerProvider.notifier).previousStep();
currentStep: _currentStep         →   currentStep: state.currentStep
```

**Nota:** El reset del controller (C1-01) ya reinicia `currentStep` a 0 al invalidar
el provider, así que este campo se resetea correctamente al abrir el flujo.

### Validación

- `flutter test` → En verde.
- Verificar que el Stepper sigue funcionando correctamente con el step del provider.

---

## Corrección C5-02 — Renombrar dx/dy a dMinLat/dMinLng en setBounds

**Hallazgo:** H-13
**Archivo:** `lib/features/map/presentation/map_providers.dart`
**Método:** `MapFilterNotifier.setBounds()`

### Cambio exacto

Renombrar las variables locales dentro del método (no son campos de clase):

```dart
// ANTES:
final dx = (state.minLat ?? minLat) - minLat;
final dy = (state.minLng ?? minLng) - minLng;
final dx2 = (state.maxLat ?? maxLat) - maxLat;
final dy2 = (state.maxLng ?? maxLng) - maxLng;
if (dx.abs() < _boundsTolerance &&
    dy.abs() < _boundsTolerance &&
    dx2.abs() < _boundsTolerance &&
    dy2.abs() < _boundsTolerance) {

// DESPUÉS:
final dMinLat = (state.minLat ?? minLat) - minLat;
final dMinLng = (state.minLng ?? minLng) - minLng;
final dMaxLat = (state.maxLat ?? maxLat) - maxLat;
final dMaxLng = (state.maxLng ?? maxLng) - maxLng;
if (dMinLat.abs() < _boundsTolerance &&
    dMinLng.abs() < _boundsTolerance &&
    dMaxLat.abs() < _boundsTolerance &&
    dMaxLng.abs() < _boundsTolerance) {
```

### Validación

- `flutter analyze` → No issues.
- `flutter test` → En verde (los tests de C4-02 deben seguir pasando).

---

## Corrección C5-03 — Reemplazar primaryColor deprecated

**Hallazgo:** H-14
**Archivos:** `lib/features/water/presentation/water_register_step_municipality.dart`
            `lib/features/water/presentation/water_register_step_sector.dart`

### Cambio exacto

En ambos archivos, buscar todas las ocurrencias de:
```dart
Theme.of(context).primaryColor
```

Reemplazar por:
```dart
Theme.of(context).colorScheme.primary
```

Si el archivo importa `AppColors` (verificar), también se puede usar:
```dart
AppColors.primary
```

Pero `colorScheme.primary` es la opción correcta para consistencia con Material 3.

### Validación

- `flutter analyze` → No issues (puede eliminar warnings de deprecated).
- `flutter test` → En verde.

---

## Corrección C5-04 — Eliminar TODO obsoleto en build.gradle.kts

**Hallazgo:** H-15
**Archivo:** `android/app/build.gradle.kts`

### Cambio exacto

Buscar y eliminar el comentario:
```
// TODO: Specify your own unique Application ID (https://...)
```

El Application ID ya está correctamente especificado como `"com.gota.app"` en la
línea siguiente. El comentario es un artefacto de la plantilla de Flutter.

### Validación

- El archivo compila correctamente (no ejecutar flutter build, solo verificar sintaxis).

---

## Corrección C5-05 — Crear docs/SECURITY.md

**Hallazgo:** H-11
**Archivo nuevo:** `docs/SECURITY.md`

### Contenido a crear

```markdown
# Gota — Modelo de Seguridad

## Anon Key de Supabase

La `SUPABASE_ANON_KEY` se inyecta en el APK vía `dart-define` durante la compilación.
Es técnicamente extraíble del binario con herramientas de análisis (apktool, strings).

**Esto es intencional y aceptable** porque:

1. La anon key no otorga acceso a datos. Toda autorización real está en RLS
   (Row Level Security) en PostgreSQL.
2. Supabase está diseñado para que la anon key sea pública: cada operación del cliente
   pasa por las políticas RLS, que validan `auth.uid()` para cada fila.
3. El modelo es equivalente a una API key de solo lectura que el servidor valida
   con sus propias reglas.

## Responsabilidades de seguridad

| Capa | Responsabilidad |
|------|----------------|
| RLS en Supabase | Autorización por fila (usuario solo ve/modifica sus datos) |
| RPCs protegidas | Operaciones sensibles (crear reporte, validar, registrar evento) |
| Autenticación anónima | Identidad única por dispositivo (Supabase Auth) |
| App Flutter | No almacena datos sensibles localmente; fotos son temporales |

## Permisos Android

- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`: solo se solicitan cuando el usuario
  toca "Usar mi ubicación GPS". No hay tracking continuo.
- `POST_NOTIFICATIONS`: para FCM. Solo se solicita en el flujo de activar notificaciones.
- `INTERNET`: necesario para Supabase.

## Fotos

Las fotos se comprimen y suben a Supabase Storage en carpetas privadas
(`report_photos/{auth.uid()}/...`). La política RLS del bucket garantiza que cada
usuario solo puede leer y escribir su propia carpeta. Las fotos temporales locales
se eliminan del borrador al completar o cancelar el flujo.

## FCM tokens

Los tokens FCM se registran en la tabla `notification_tokens` asociados al `auth.uid()`
del usuario. El RLS de esta tabla garantiza que cada usuario solo gestiona sus propios
tokens. Al desinstalar o revocar permisos, el token queda inactivo y no se usa para
envíos futuros.
```

### Validación

- Archivo creado correctamente.

---

## Corrección C5-06 — Limpiar TODO de carrusel en leak_detail_screen

**Hallazgo:** H-18
**Archivo:** `lib/features/leaks/presentation/leak_detail_screen.dart`

### Cambio exacto

Buscar la línea:
```dart
// TODO: Photo carousel - reintroduce after test refactoring
```

Eliminar esa línea de comentario. Si hay código relacionado que también está comentado,
evaluar su eliminación (el carrusel es funcionalidad futura que se añadirá por separado).

### Validación

- `flutter analyze` → No issues.

---

## Corrección C5-07 — Renombrar supabaseAnonKey a supabasePublishableKey

**Hallazgo:** H-20
**Archivos:** `lib/core/config/app_config.dart`, `lib/main.dart`
            y cualquier archivo que referencie `supabaseAnonKey`

### Cambio exacto

En `lib/core/config/app_config.dart`:
```dart
// ANTES:
final String supabaseAnonKey;
// DESPUÉS:
final String supabasePublishableKey;
```

Actualizar el constructor, el factory `fromValues` y cualquier uso interno.

En `lib/main.dart`:
```dart
// ANTES:
publishableKey: config.supabaseAnonKey,
// DESPUÉS:
publishableKey: config.supabasePublishableKey,
```

Buscar todas las referencias a `supabaseAnonKey` en el proyecto:
```bash
grep -rn "supabaseAnonKey" lib/ test/
```

Reemplazarlas todas.

### Validación

- `flutter analyze` → No issues.
- `flutter test` → En verde.

---

## Corrección C5-08 — Actualizar Firebase minor bumps

**Hallazgo:** H-21
**Archivo:** `pubspec.yaml`

### Cambio exacto

En `pubspec.yaml`, actualizar:
```yaml
# ANTES:
firebase_core: ^4.14.0
firebase_messaging: ^4.14.0

# DESPUÉS:
firebase_core: ^4.15.0
firebase_messaging: ^16.7.0
```

Luego ejecutar:
```bash
flutter pub upgrade firebase_core firebase_messaging
```

Verificar que no haya breaking changes ejecutando `flutter test`.

**No actualizar geolocator**: el cambio de 13.x a 14.x es un major bump que puede
tener breaking changes en la API. Evaluar en una sesión separada post-beta.

### Validación

- `flutter pub get` sin errores.
- `flutter test` → En verde.

---

## Corrección C5-09 — Corregir features/information/ en ARCHITECTURE.md

**Hallazgo:** H-22
**Archivo:** `docs/ARCHITECTURE.md`

### Cambio exacto

Buscar en el diagrama de estructura la línea:
```
│   └── information/
```

Reemplazar por:
```
│   └── contact/
```

O si la feature `contact/` tiene un rol diferente al de "información", eliminar
la línea del diagrama o añadir ambas:
```
│   ├── contact/
│   └── location/
```

Verificar con `ls lib/features/` cuál es la estructura real actual.

### Validación

- El diagrama en ARCHITECTURE.md refleja la estructura real del repositorio.

---

## Corrección C5-10 — Añadir nota de estado real de paginación en MIGRATION_NOTES

**Hallazgo:** H-23
**Archivo:** `docs/MIGRATION_NOTES.md`

### Cambio exacto

Buscar en MIGRATION_NOTES la sección sobre paginación de `water_events` (línea ~111):
```
| Paginación | Keyset (cursor: event_time + id), default limit 20. Implementación simplificada... |
```

Añadir una nota después de esa fila (o actualizar el texto):

```
| Paginación | Keyset (cursor: event_time + id), default limit 20.
             Implementado en DB layer (fetchRecentWaterEvents acepta cursor).
             El filtro lte('event_time') aplica el keyset en la query.
             WaterHistoryController.loadMore() usa state.nextCursor.
             [Corregido en auditoría pre-beta 2026-09-24: H-02, H-19] |
```

### Validación

- El texto refleja el estado real tras las correcciones de Fase 1.

---

## Checklist de finalización de Fase 5

- [ ] C5-01: `_currentStep` movido al controller.
- [ ] C5-02: Variables renombradas a `dMinLat/dMinLng/dMaxLat/dMaxLng`.
- [ ] C5-03: `primaryColor` deprecated reemplazado en 2 archivos.
- [ ] C5-04: TODO obsoleto eliminado de `build.gradle.kts`.
- [ ] C5-05: `docs/SECURITY.md` creado.
- [ ] C5-06: TODO de carrusel eliminado de `leak_detail_screen.dart`.
- [ ] C5-07: `supabaseAnonKey` renombrado a `supabasePublishableKey` en todos los archivos.
- [ ] C5-08: Firebase minor bumps aplicados.
- [ ] C5-09: `ARCHITECTURE.md` corregido (information → contact).
- [ ] C5-10: Nota de estado de paginación añadida a `MIGRATION_NOTES.md`.
- [ ] `flutter analyze` → No issues.
- [ ] `flutter test` → Todos en verde.
- [ ] Commit: `fix(quality): fase 5 — polish técnico y docs`

---

## PROMPT PARA EL AGENTE DE CODIFICACIÓN

```
Eres un agente de codificación trabajando en Gota v0.2 (Flutter · Riverpod 3 · Supabase).
Rama de trabajo: fix/map-r5-r6. Las Fases 1-4 ya fueron aplicadas.

Tu tarea es aplicar 10 correcciones de polish técnico y documentación (P3).
Pueden aplicarse en cualquier orden, pero ejecuta flutter test entre grupos de cambios.

Antes de empezar: ejecuta `flutter test` y confirma baseline verde.

C5-01: Mover _currentStep de _WaterRegisterScreenState al WaterRegisterController.
  - Añadir campo currentStep: int = 0 a WaterRegisterState con su copyWith.
  - Añadir métodos nextStep()/previousStep()/goToStep() al controller.
  - Reemplazar setState() en el widget por ref.read(...notifier).nextStep/previousStep.
  flutter test después.

C5-02: En map_providers.dart, método MapFilterNotifier.setBounds():
  Renombrar dx → dMinLat, dy → dMinLng, dx2 → dMaxLat, dy2 → dMaxLng.
  flutter analyze después.

C5-03: En water_register_step_municipality.dart y water_register_step_sector.dart:
  Reemplazar Theme.of(context).primaryColor por Theme.of(context).colorScheme.primary.
  flutter analyze después.

C5-04: En android/app/build.gradle.kts:
  Eliminar el comentario "TODO: Specify your own unique Application ID".

C5-05: Crear docs/SECURITY.md con el modelo de seguridad de la anon key.
  Ver contenido completo en FASE_5_POLISH_PROMPT.md.

C5-06: En lib/features/leaks/presentation/leak_detail_screen.dart:
  Eliminar la línea: // TODO: Photo carousel - reintroduce after test refactoring

C5-07: Renombrar supabaseAnonKey a supabasePublishableKey en todos los archivos.
  Buscar con: grep -rn "supabaseAnonKey" lib/ test/
  Actualizar: app_config.dart (campo y uso), main.dart, y cualquier test.
  flutter analyze y flutter test después.

C5-08: En pubspec.yaml, actualizar firebase_core a ^4.15.0 y firebase_messaging a ^16.7.0.
  Ejecutar: flutter pub upgrade firebase_core firebase_messaging
  flutter test después.

C5-09: En docs/ARCHITECTURE.md:
  En el diagrama de features, reemplazar "│   └── information/" por "│   └── contact/"
  (verificar primero con ls lib/features/ qué directorios existen realmente).

C5-10: En docs/MIGRATION_NOTES.md:
  En la fila sobre paginación keyset de water_events, añadir nota indicando que
  el cursor se implementó correctamente en la auditoría pre-beta 2026-09-24 (H-02, H-19).

Al terminar:
1. `flutter analyze` → No issues found.
2. `flutter test` → Todos en verde.
3. Commit: `fix(quality): fase 5 — polish técnico y docs`
```
