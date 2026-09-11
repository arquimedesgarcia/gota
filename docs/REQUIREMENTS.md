# Gota — Requirements

**Versión:** 0.2

## 1. Actores

- **Vecino:** reporta, valida, confirma resolución y registra/valida eventos de agua.
- **Sistema:** autentica anónimamente, aplica reglas, almacena datos y envía notificaciones.
- **Administración técnica:** acceso restringido para configuración/mantenimiento; no es una experiencia pública del MVP.

## 2. Geografía

**REQ-010** La cobertura inicial será Maneiro y Arismendi.  
**REQ-011** Municipio y sector deben estar asociados a reportes y eventos de agua.  
**REQ-012** Los sectores deben ser datos configurables.  
**REQ-013** La estructura debe poder extenderse a otros municipios sin rediseño.

## 3. Fugas

**REQ-020** El usuario puede crear una fuga con ubicación, sector, municipio, descripción opcional y 1–3 fotos.  
**REQ-021** La ubicación puede proceder de GPS o selección manual en mapa.  
**REQ-022** La fuente de ubicación se registra como GPS o MANUAL.  
**REQ-023** Las fotos deben validarse, comprimirse y almacenarse de forma segura.  
**REQ-024** El backend debe revisar posibles duplicados antes de crear un reporte.  
**REQ-025** Un posible duplicado no bloquea automáticamente: permite ver/validar el existente o declarar que es otra fuga.

## 4. Duplicados

**REQ-030** La detección inicial considera reportes ACTIVE dentro de un radio configurable de **50 m** y una ventana configurable de **48 h**.  
**REQ-031** El resultado debe indicar reporte(s) candidato(s) y distancia.  
**REQ-032** No se usará reconocimiento de imágenes para deduplicación en MVP.

## 5. Validación

**REQ-040** Un usuario anónimo puede validar una fuga activa de otro usuario.  
**REQ-041** El creador no puede validar su propio reporte.  
**REQ-042** Una identidad solo puede validar una vez el mismo reporte.  
**REQ-043** El backend debe hacer cumplir la regla, no solo la UI.  
**REQ-044** Las validaciones se registran con timestamp e identidad anónima.

## 6. Resolución

**REQ-050** Cualquier usuario puede indicar que una fuga parece resuelta.  
**REQ-051** El creador puede participar solo si no está confirmando su propio reporte como mecanismo de validación de existencia; el backend debe aplicar las reglas definidas en la operación.  
**REQ-052** Una identidad solo puede confirmar resolución una vez por reporte.  
**REQ-053** Con **3 identidades distintas** confirmando resolución, ACTIVE pasa atómicamente a RESOLVED.  
**REQ-054** El historial de resueltas es público.  
**REQ-055** No existe expiración automática en MVP.

## 7. Agua

**REQ-070** El usuario puede registrar WATER_ARRIVED o WATER_LEFT.  
**REQ-071** El evento pertenece a municipio y sector.  
**REQ-072** La hora efectiva del evento puede diferir del created_at y se almacena como event_time.  
**REQ-073** Un usuario puede validar un evento de otro usuario.  
**REQ-074** El creador no puede validar su propio evento.  
**REQ-075** Una identidad solo puede validar una vez cada evento.  
**REQ-076** Se muestran eventos recientes e historial.  
**REQ-077** La app no debe presentar predicciones como hechos.

## 8. Notificaciones

**REQ-080** Se soportan notificaciones de fugas y suministro de agua.  
**REQ-081** El usuario puede configurar su municipio/sector de interés.  
**REQ-082** Las notificaciones deben respetar preferencias.  
**REQ-083** El backend decide destinatarios y evita spam evidente.  
**REQ-084** El token FCM se registra de forma segura.

## 9. Antiabuso y seguridad

**REQ-090** Debe existir identidad anónima persistente.  
**REQ-091** Deben existir rate limits configurables para reportes, validaciones, resoluciones y eventos.  
**REQ-092** Las acciones duplicadas deben rechazarse server-side.  
**REQ-093** Deben registrarse acciones relevantes en audit_events.  
**REQ-094** El diseño debe permitir detección posterior de actividad anómala.

## 10. Privacidad

**REQ-100** La identidad del reportante no es pública.  
**REQ-101** La ubicación pública corresponde a la fuga, no a la ubicación personal del usuario.  
**REQ-102** No se exige nombre, teléfono, correo ni perfil social.

## 11. Información

**REQ-110** La app puede mostrar contenido educativo básico sobre agua, fugas y uso responsable.  
**REQ-111** El contenido no debe interferir con el flujo principal.

## 12. Plataforma

**REQ-150** Android es prioridad.  
**REQ-151** iOS debe ser arquitectónicamente compatible.  
**REQ-152** Web queda fuera del MVP de producto.

## 13. Calidad

**REQ-170** Las reglas críticas deben probarse server-side.  
**REQ-171** Flutter analyze y tests deben pasar antes de cerrar un sprint.  
**REQ-172** Las migraciones de base de datos deben estar versionadas.  
**REQ-173** No se deben introducir servicios o infraestructura no justificados.

## 14. Escenarios de aceptación principales

### Fuga
Usuario → ubicación → fotos → revisión → backend → posible duplicado → creación ACTIVE.

### Duplicado
Backend encuentra ACTIVE dentro de 50 m/48 h → app muestra candidato → usuario valida existente o declara otra fuga.

### Resolución
Tres identidades distintas confirman resolución → transacción → ACTIVE pasa a RESOLVED.

### Agua
Usuario registra llegada/salida → evento público → otros usuarios pueden validarlo → notificaciones según preferencias.
