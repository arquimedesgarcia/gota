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
|------|-----------------|
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