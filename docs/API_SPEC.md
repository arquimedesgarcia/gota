# Gota — API Specification

**Versión:** 0.2

## 1. Principio

Lecturas simples pueden usar Supabase SDK con RLS.

Las reglas críticas se ejecutan mediante Edge Functions o SQL protegido.

## 2. Operaciones

### create-leak-report
Entrada:
- municipality_id
- sector_id
- location
- location_source
- description
- photo references

Proceso:
1. autenticar;
2. validar sector;
3. validar ubicación;
4. validar fotos;
5. buscar duplicados 50m/48h;
6. devolver `POSSIBLE_DUPLICATE` si corresponde o crear ACTIVE.

### validate-leak
- reporte debe existir y estar ACTIVE;
- usuario autenticado anónimamente;
- usuario != creador;
- una validación por usuario;
- rate limit;
- operación atómica.

### confirm-leak-resolution
- reporte ACTIVE;
- una confirmación por usuario;
- rate limit;
- transición atómica a RESOLVED al llegar a 3.

### register-water-event
- validar municipio/sector;
- registrar event_type y event_time;
- aplicar rate limit.

### validate-water-event
- usuario != creador;
- una validación por usuario;
- rate limit.

### register-notification-token
Registra/actualiza token FCM del usuario.

### update-notification-preferences
Actualiza preferencias de fugas/suministro y sector.

## 3. Errores

- UNAUTHORIZED
- FORBIDDEN
- NOT_FOUND
- VALIDATION_ERROR
- DUPLICATE_ACTION
- POSSIBLE_DUPLICATE
- RATE_LIMITED
- INVALID_LOCATION
- INVALID_SECTOR
- REPORT_ALREADY_RESOLVED
- STORAGE_ERROR
- INTERNAL_ERROR

## 4. Paginación

Usar cursor/paginación para listas.

## 5. Payload de mapa

Solo campos necesarios para pintar y abrir detalle.

## 6. Fotos

No enviar binarios dentro de la función. Usar Storage y persistir referencias.

## 7. Notificaciones

Eventos:
- REPORT_VALIDATED
- REPORT_RESOLVED
- WATER_ARRIVED
- WATER_LEFT

El backend determina destinatarios según sector y preferencias.

## 8. Versionado

Los contratos deben ser compatibles y versionarse cuando exista una ruptura real.
