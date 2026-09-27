# Backlog — Notificación de proximidad a fuga reportada (app abierta)

> [ITERACIÓN FUTURA] Guardado como prompt para ejecutar más adelante. No iniciar sin aprobación.

## Contexto
Gota ya tiene el pipeline completo de push (Sprint 06): tabla `notifications` como fuente de verdad,
Database Webhook → Edge Function `notify-push` → FCM HTTP v1 con deep-link por `data payload`.
Los reportes de fuga viven en `reports` con `location geography(Point,4326)` (PostGIS),
`status` ACTIVE/RESOLVED, y contadores `validation_count` / `resolution_confirmation_count`.
La app ya usa `geolocator` (flujo de fugas) y tiene preferencias de notificación
(`save_notification_preferences` + SettingsScreen).

La idea: cuando un usuario obtiene una ubicación con la app ABIERTA y hay un reporte
ACTIVE de fuga a menos de ~300 m, sugerirle validarla o marcarla resuelta.

## Modalidad decidida: solo con la app abierta (foreground)
- NO se usa `ACCESS_BACKGROUND_LOCATION` ni geofencing en esta iteración. La detección
  ocurre únicamente cuando la app ya obtiene un fix de GPS en primer plano (abrir el mapa,
  iniciar un reporte, abrir la app).
- Geofencing / background queda explícitamente postergado a una V2, y solo si el piloto
  demuestra que las notificaciones de la V1 generan validaciones reales
  (métrica objetivo: % de notificaciones que terminan en validación o resolución).
- Ventaja: sin permisos nuevos, sin riesgo de revisión de tiendas, batería neutra.

## Objetivo
- Tras cada fix de GPS en primer plano, consultar si hay reportes ACTIVE cercanos y
  generar una notificación (registro en `notifications` + push si el dispositivo está
  suscrito) con mensaje tipo: "Pasaste cerca de una fuga reportada — ¿sigue ahí?
  Ayúdanos a validarla o marcarla resuelta."
- El tap abre el detalle del reporte (deep-link ya soportado por el payload del Sprint 06),
  donde el usuario puede validar o marcar resuelta usando los contadores existentes.

## Backend (Supabase)
- RPC `get_nearby_active_reports(p_lat double precision, p_lng double precision,
  p_radius_m int default 300)`:
  - `ST_DWithin(location, ST_MakePoint(p_lng,p_lat)::geography, p_radius_m)`
  - filtro `status = 'ACTIVE'`
  - filtro de frescura: `created_at >= now() - interval '14 days'` (regla anti-reporte-viejo)
  - devuelve id, dirección/descripción, distancia, created_at.
  - RLS: solo reportes visibles al usuario autenticado; test pgTAP en `supabase/tests/`
    siguiendo el patrón existente (`map_reports_test.sql`).
- La notificación se crea con el mecanismo existente (INSERT en `notifications` →
  webhook → `notify-push`), con `type` nuevo (ej. `nearby_report`) y el `report_id`
  en el data payload para navegación.
- El backend NO recibe ubicación continua: el RPC es puntual, invocado por el cliente
  solo cuando ya hay un fix de GPS en uso legítimo.

## Flutter
- Servicio nuevo (ej. `lib/features/notifications/nearby_reports_service.dart`) que:
  1. se engancha a los fix de GPS de primer plano ya existentes (LocationStep / mapa),
  2. con throttle (ej. máx. 1 consulta cada 5 min), llama al RPC,
  3. aplica cooldown local antes de notificar (ver reglas),
  4. crea la notificación vía el repositorio existente.
- Respetar `water_notifications_enabled` / preferencias: añadir toggle propio
  "Avisarme de fugas cerca de mí (con la app abierta)" en SettingsScreen, default ON.
- Navegación al detalle desde el tap (patrón ya existente en el router).

## Reglas anti-spam (obligatorias)
1. Cooldown por (usuario, reporte): no re-avisar del mismo reporte en 7 días
   ni mientras el reporte siga ACTIVE y ya fue avisado — guardar en la BD local de
   notificaciones (`gota_notifications_database`).
2. Frescura: solo reportes con `created_at` <= 14 días.
3. Throttle de consultas: máx. 1 RPC cada 5 minutos.
4. Máx. 1 notificación de proximidad por sesión de uso de la app.

## Archivos clave
- supabase/migrations/ — nueva migración con el RPC + test en supabase/tests/
- lib/features/notifications/ — servicio de proximidad + providers
- lib/features/notifications/presentation/settings_screen.dart — toggle de la feature
- lib/core/network/gota_notifications_database.dart — cooldown local por reporte
- Edge Function `notify-push` — soportar el nuevo `type` en el data payload
  (verificar que el mapeo de navegación lo trate)

## Criterio de aceptación
1. Con la app abierta, al obtener GPS a <300 m de un reporte ACTIVE reciente, el usuario
   recibe la notificación y el tap abre el detalle del reporte.
2. No se pide ningún permiso nuevo; con la app cerrada no llega ninguna notificación
   de proximidad.
3. El mismo reporte no vuelve a notificar dentro de la ventana de cooldown, ni siquiera
   reabriendo la app.
4. Reportes RESOLVED o con más de 14 días nunca generan notificación.
5. El toggle en Settings desactiva la feature por completo (ni RPC ni notificación).
6. Test pgTAP del RPC cubre: dentro/fuera del radio, reporte RESOLVED, reporte viejo.

## Decisión de producto (pendiente)
- Radio: 300 m como default propuesto — validar en piloto si es muy ruidoso en zonas
  densas de reportes.
- ¿La notificación también aplica a reportes de agua (water_events) o solo fugas?
  Esta iteración cubre solo fugas (`reports`); evaluar paridad después.

## Métrica de éxito del piloto
- % de notificaciones de proximidad que terminan en validación o confirmación de
  resolución. Si es bajo, no justificar la V2 (geofencing).
