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
- Arismendi.

Los sectores se agregan mediante migraciones/seed controlado cuando exista una fuente validada.

**Estado de sectores (AUD-S1-02):** la estructura (`sectors`, RLS de solo lectura sobre activos) está lista, pero el catálogo está vacío. Hasta que exista una fuente validada de los sectores de Maneiro y Arismendi, el flujo de reporte es inejecutable (`create_leak_report` responde `INVALID_SECTOR`). La carga se hará por una migración nueva posterior a `20260911000015`, con nombres verificados, nunca sembrados a mano ni por la app.

## Android

Android es la plataforma prioritaria del MVP.

iOS debe mantenerse compatible desde arquitectura, pero su release puede venir después.

## Regla

No agregar Firebase, Railway, Redis ni otro backend al camino crítico sin una decisión explícita.
