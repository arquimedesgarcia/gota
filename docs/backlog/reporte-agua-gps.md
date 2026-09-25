# Backlog — Reportar evento de agua por ubicación GPS (paridad con flujo de fugas)

> [ITERACIÓN FUTURA] Guardado como prompt para ejecutar más adelante. No iniciar sin aprobación.

## Contexto
El flujo actual de "Reportar agua" usa Stepper con selección manual de municipio
y sector desde un catálogo. El flujo de "Reportar fuga" usa GPS + reverse geocoding
(Nominatim / BigDataCloud) para capturar ubicación y autocompletar municipio, sector
y dirección. La propuesta es migrar el flujo de agua al mismo mecanismo.

## Objetivo
- Reemplazar los pasos "Municipio" y "Sector" del WaterRegisterScreen por un
  único paso "Ubicación" que reutilice el LocationStep/GotaMapView del flujo de fugas.
- Capturar y guardar la dirección completa sugerida por el geocoder (campo `address`)
  junto al evento de agua, para mostrarla en WaterEventDetailScreen.
- En esta iteración también introducir un campo search/autocomplete para el sector
  (caja de texto que filtra el listado del catálogo en tiempo real) como fallback
  cuando el geocoding no resuelve el sectorId exacto del catálogo.

## Archivos clave (Flutter)
- lib/features/water/presentation/water_register_screen.dart — Stepper principal
- lib/features/water/presentation/water_register_controller.dart — state: añadir
  latitude, longitude, address; quitar municipalityId obligatorio como requisito
  de validación local
- lib/features/water/presentation/water_register_step_municipality.dart — eliminar
  o convertir en fallback de autocomplete
- lib/features/water/presentation/water_register_step_sector.dart — añadir TextField
  de búsqueda que filtre la lista en tiempo real
- lib/features/location/ — LocationStep, location_providers.dart (GPS + geocoding)
  ya implementados para fugas; reutilizar directamente
- lib/features/water/data/water_event_repository.dart — añadir parámetro `address`
  al método register()
- lib/features/water/domain/water_event_detail.dart — añadir campo address nullable

## Prerequisito de backend
- Migración: agregar columna `address TEXT NULL` a la tabla de eventos de agua.
- Endpoint de registro debe aceptar `address` en el body.
- Endpoint de detalle debe devolver `address` en la respuesta.

## Decisión pendiente de producto
¿El sectorId sigue siendo obligatorio (resolviéndose por autocomplete del catálogo)
o se acepta coordenadas + texto libre de dirección, dejando la asociación al sector
como inferencia del backend? La respuesta define si se necesita el autocomplete
contra el catálogo o basta con el campo de geocoding.

## Criterio de aceptación
1. El usuario puede registrar un evento de agua tocando su ubicación en el mapa
   o usando "Mi ubicación" (GPS).
2. El municipio y sector se autocompletan desde el resultado del geocoder; el usuario
   puede corregirlos con el autocomplete.
3. La dirección completa (ej. "Calle Bolívar, Urbanización Los Pinos, Porlamar")
   queda guardada y se muestra en el detalle del evento.
4. El flujo no regresa el registro manual (catálogo) para zonas sin cobertura GPS.
