# Gota — Setup

## Requisitos

- Flutter estable compatible con el proyecto.
- Android Studio + SDK.
- Git.
- Supabase CLI.
- cuenta Supabase.

## Crear proyecto

Crear un proyecto Supabase para desarrollo.

Configurar:
- Database;
- Auth;
- Storage.

## Flutter

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Supabase CLI

Inicializar el proyecto y mantener migraciones versionadas.

Las migraciones son la fuente reproducible del esquema; evitar cambios manuales no documentados.

## Variables

Usar configuración por ambiente.

Nunca incluir:
- service role key;
- secretos FCM;
- claves privadas;
- credenciales de producción.

La app móvil solo recibe credenciales públicas apropiadas para cliente.

## Anonymous Auth

Activar Anonymous Sign-ins en Supabase.

Al iniciar:
1. comprobar sesión;
2. si no existe, crear sesión anónima;
3. crear/asegurar `app_users`;
4. continuar a Home.

## Seed inicial

Crear:
- Maneiro;
- Arismendi;
- Mariño (piloto).

**Estado de sectores — catálogo piloto cargado (migración `20260914000028`):**
los tres municipios del piloto tienen sectores y el flujo de reporte es ejecutable.

| Municipio  | Sectores activos |
|------------|------------------|
| Arismendi  | 27               |
| Maneiro    | 27               |
| Mariño     | 42               |
| **Total**  | **96**           |

**Fuente y trazabilidad.** Municipios: FeatureServer ArcGIS
`División_Político_Territorial` (capa `DPT002_MUNICIPIO`, códigos INE). Sectores:
OpenStreetMap vía Overpass API (licencia ODbL), asignados a municipio por
point-in-polygon sobre la geometría oficial. El dataset completo de la isla
(10 municipios, 307 sectores) queda en
`supabase/seed_data/ne_margarita_sectores.json` para ampliar el piloto.

**Calidad de los nombres.** Se cargaron tal cual la fuente y se depuran con el
uso real. Casos conocidos a revisar: nombres seriados (`Vista Bella I–IV`,
`1°.`/`2°. Etapa de Jorge Coll`) y variantes por proximidad (`Los Cocos` /
`Los Cocos Norte`).

**Ampliar a más municipios:** regenerar la migración desde
`supabase/seed_data/ne_margarita_sectores.json` añadiendo el municipio al
conjunto deseado (UUIDs determinísticos por `uuid5`, idempotente).

**Verificación:** `bash supabase/tests/pilot_catalog_e2e.sh` — crea un usuario
anónimo, sube una foto a Storage y crea un reporte real en un sector sembrado
(Mariño/Genovés), comprobando `CREATED` y que el catálogo es legible por `anon`.

## Android

Android es la plataforma prioritaria del MVP.

iOS debe mantenerse compatible desde arquitectura, pero su release puede venir después.

### Build de release (Sprint 08)

1. **Signing:** el build de release usa `android/key.properties` (`storeFile`, `keyAlias`, `storePassword`, `keyPassword`) si existe; en su ausencia firma con la clave de debug, lo que permite compilar desde un clon limpio, pero no constituye un artefacto de release reproducible ni apto para distribución. Generar el keystore con `keytool` y crear `key.properties` solo en máquinas de release (ambos ignorados por Git).
2. **Firebase:** para que el APK tenga FCM, colocar `google-services.json` en `android/app/` antes de compilar (ignorado por Git). Sin él la app compila y funciona sin push.
3. **Comando:**

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<proyecto>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-public> \
  --dart-define=SUPABASE_ENV=production
```

`versionCode`/`versionName` salen de `pubspec.yaml`. Los `--dart-define` se incrustan en el binario: nunca pasar credenciales distintas a las públicas de cliente. El release activa R8 (minify + shrinkResources) con las reglas de `android/app/proguard-rules.pro`. Verificado en Sprint 08: el comando compila y produce un APK válido desde un clon limpio sin secretos.

### Tráfico claro en desarrollo (AUD-S2-17)

Para ejecutar contra un Supabase **local** (`http://10.0.2.2:54321` en el
emulador, o `localhost`/`127.0.0.1`), el build de **debug** habilita
`cleartextTraffic` únicamente para esos hosts, vía
`android/app/src/debug/res/xml/network_security_config.xml` referenciado desde
`android/app/src/debug/AndroidManifest.xml`. **No** se activa en release: el
manifest de release no incluye `networkSecurityConfig`, así que Android bloquea
`http://` por defecto y la app debe apuntar a un proyecto `https://`.

Las pruebas E2E (`supabase/tests/*.sh`) asumen ese Supabase local, salvo
`storage_rls_e2e.sh`, que también acepta `SUPABASE_URL`/`SUPABASE_ANON_KEY`
de un proyecto remoto. Todas hacen cleanup de sus recursos (incluido ante
interrupción) y distinguen `PASS`/`FAIL`/`NOT EXECUTED`.

## Push notifications (Sprint 06)

La entrega push usa **FCM HTTP v1** con OAuth2 (service account). El
endpoint Legacy está prohibido.

### Configuración Firebase (cliente)

1. Crear proyecto Firebase y app Android (`com.gota.app`); descargar
   `google-services.json` a `android/app/` (fuera de Git; el plugin Gradle
   se aplica condicionalmente: sin el archivo la app compila y funciona sin
   push).
2. iOS: añadir `GoogleService-Info.plist` al Runner (fuera de Git). El
   `AppDelegate` solo inicializa Firebase si el plist existe.

### Secreto de la Edge Function (servidor)

`supabase/functions/notify-push` lee `FCM_SERVICE_ACCOUNT_JSON` (JSON
completo de la service account; el `project_id` se toma del propio JSON).
En el entorno self-hosted (Supabase CLI + Docker) se inyecta con el
archivo `supabase/functions/.env` (ya ignorado por `.gitignore`):

```text
FCM_SERVICE_ACCOUNT_JSON={"project_id":"...","client_email":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"}
```

Después de crear/modificar el `.env`, reiniciar el stack
(`supabase stop && supabase start`) para que el Edge Runtime lo recargue.

### Database Webhook (self-hosted)

La función se dispara por un trigger sobre `public.notifications`:

```sql
create extension if not exists pg_net;  -- si no está instalada

create trigger notifications_webhook_notify_push
  after insert on public.notifications
  for each row execute function supabase_functions.http_request(
    'http://kong:8000/functions/v1/notify-push',
    'POST',
    '{"Content-Type": "application/json", "Authorization": "Bearer <service_role_key>"}'
  );
```

La función está declarada en `supabase/config.toml`
(`[functions.notify-push] verify_jwt = true`): el webhook debe enviar el
service role key. El código de la función vive en el repo
(`supabase/functions/notify-push/`) y el stack lo monta en caliente.

## Regla

No agregar Firebase, Railway, Redis ni otro backend al camino crítico sin una decisión explícita.
