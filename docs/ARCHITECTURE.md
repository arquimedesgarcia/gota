# Gota — Architecture

**Versión:** 0.2

## 1. Arquitectura general

```text
Flutter
 ├─ Presentation
 ├─ State (Riverpod)
 ├─ Domain
 └─ Data
       │
       ▼
Supabase
 ├─ Auth
 ├─ PostgreSQL + PostGIS
 ├─ Storage
 ├─ Edge Functions
 └─ Realtime
       │
       └── FCM
```

## 2. Flutter

Estructura:

```text
lib/
├── app/
│   ├── app.dart
│   ├── router/
│   └── theme/
├── core/
│   ├── config/
│   ├── errors/
│   ├── network/
│   └── utils/
├── features/
│   ├── home/
│   ├── leaks/
│   ├── water/
│   ├── map/
│   ├── notifications/
│   └── information/
└── shared/
    ├── models/
    ├── services/
    └── widgets/
```

Cada feature puede separar `data/domain/presentation` cuando tenga suficiente complejidad.

## 3. Backend

Supabase es el backend principal.

- Auth: identidad anónima.
- PostgreSQL: persistencia.
- PostGIS: consultas espaciales.
- Storage: fotografías.
- Edge Functions: operaciones críticas.
- Realtime: actualizaciones donde aporte valor.
- RLS: autorización de datos.

## 4. Regla de dependencias

La UI no consulta Supabase directamente.

```text
UI → Provider → Repository/Use Case → Supabase
```

## 5. Operaciones críticas

Estas deben ejecutarse server-side:

- crear reporte con revisión de duplicados;
- validar fuga;
- confirmar resolución;
- registrar/validar evento de agua cuando requiera reglas;
- rate limiting;
- notificaciones.

## 6. Mapas

MapLibre + OpenStreetMap inicialmente, detrás de una abstracción.

No acoplar el dominio al proveedor.

## 7. Fotos

La app comprime y valida antes de subir.

Storage mantiene binarios; PostgreSQL mantiene referencias y metadatos.

## 8. Seguridad

- RLS.
- UUID.
- timestamps UTC.
- secretos fuera del repositorio.
- Edge Functions para operaciones sensibles.
- logs de auditoría mínimos.

## 9. Ambientes

Preparar separación dev/prod.

No introducir staging adicional hasta que sea necesario.

## 10. Qué no construir

No usar:
- microservicios;
- Kubernetes;
- Redis sin necesidad;
- RabbitMQ;
- API Gateway;
- CQRS;
- Event Sourcing;
- Elasticsearch;
- IA de visión;
- backend adicional en Railway.

Railway solo se añade si aparece una necesidad concreta que Supabase no resuelva.
