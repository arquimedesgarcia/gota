# Gota — Project Brief

**Versión:** 0.2  
**Estado:** READY FOR IMPLEMENTATION  
**Fecha:** 2026-09-11

## 1. Propósito

Gota es una aplicación móvil comunitaria para Isla de Margarita, Venezuela, inicialmente enfocada en los municipios **Maneiro y Arismendi**.

Permite hacer visible y validar comunitariamente:

- fugas de agua potable;
- resolución de fugas;
- llegada y salida del agua por sector.

La propuesta central es:

> **Ver → Reportar → Validar → Resolver → Informar**

Gota no sustituye una denuncia oficial ante organismos públicos.

## 2. Problema

El suministro de agua puede ser muy irregular. Cuando llega el agua, una tubería rota puede producir pérdidas durante horas. La información sobre fugas y suministro está dispersa y depende de comunicación informal.

Gota busca convertir esa información dispersa en información comunitaria, geolocalizada y validada.

## 3. MVP

Incluye:

1. identidad anónima sin registro tradicional;
2. reportes de fugas;
3. 1–3 fotografías;
4. ubicación exacta pública de la fuga;
5. detección básica de posibles duplicados;
6. validación comunitaria;
7. resolución con mínimo 3 confirmaciones de usuarios distintos;
8. mapa y lista de fugas activas;
9. historial público de fugas resueltas;
10. eventos de llegada/salida del agua;
11. validación comunitaria de eventos de agua;
12. notificaciones push;
13. sección informativa básica.

No incluye en MVP: panel administrativo completo, integración gubernamental, chat, perfiles sociales, pagos, CRM, IA de visión, detección de fugas por imágenes, analítica avanzada, publicidad operativa, web como producto principal.

## 4. Usuarios

No se exige cuenta tradicional. La app crea una identidad anónima persistente asociada al usuario de Supabase Auth.

La identidad se usa para:

- evitar auto-validación;
- limitar acciones duplicadas;
- aplicar rate limits;
- registrar acciones de forma anónima.

No se publica la identidad del reportante.

## 5. Plataforma y stack

- **Flutter + Dart**
- **Riverpod**
- **Supabase**
- **PostgreSQL + PostGIS**
- **Supabase Storage**
- **Supabase Edge Functions**
- **FCM** para push
- **MapLibre + OpenStreetMap**, mediante abstracción de proveedor
- GitHub + CI/CD
- Railway es opcional y no forma parte del camino crítico del MVP.

Android es la prioridad de lanzamiento. La arquitectura debe mantener compatibilidad con iOS.

## 6. Principios

- Mobile-first.
- Simple y usable con conectividad limitada.
- Backend autoritativo para reglas críticas.
- Sin sobrearquitectura.
- Sin dependencias comerciales innecesarias.
- Configuración de municipios y sectores, no hard-code.
- Privacidad por diseño.
- Documentación corta y accionable.
- El prototipo es referencia visual, no fuente de reglas de negocio.
