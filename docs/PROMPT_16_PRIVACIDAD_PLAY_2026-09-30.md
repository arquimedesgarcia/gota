# PROMPT 16 — Privacidad y disclosure para Google Play (2026-09-30)

**Objetivo:** dejar Gota conforme a los requisitos de Google Play (política de privacidad accesible y razonamiento de permisos visible) antes del primer AAB a Pruebas cerradas. Cambios **aditivos**, sin tocar lógica existente.

**Repo:** D:\Proyectos\Gota\v0.2 (rama `main`). Flutter + Supabase.

## Contexto real de la app (verificado)
- Auth: `signInAnonymously()` (lib/core/network/gota_auth.dart) — no hay correo ni registro.
- Permisos en AndroidManifest: `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, `INTERNET`, `POST_NOTIFICATIONS`.
- Datos recolectados: GPS al reportar, dirección persistida, fotos de reporte, UUID anónimo, contenido del reporte.
- La política de privacidad ya está escrita en `docs/POLITICA_PRIVACIDAD.md`.

## Tareas

### 1. Pantalla "Acerca de / Privacidad" en la app
- Nueva pantalla simple accesible desde el menú/ajustes (o desde la pantalla de reporte, donde sea más natural según la navegación actual).
- Debe contener:
  - Título "Privacidad".
  - Resumen en 4-5 líneas: qué recolecta Gota (ubicación al reportar, fotos, identificador anónimo), que no pide datos personales, que los reportes son visibles a otros usuarios pero anónimos.
  - Link que abre la política completa en el navegador: URL pública de GitHub Pages (ver sección 3). Definir la URL como constante en `lib/core/config.dart` o equivalente existente (buscar dónde viven hoy las constantes) con fallback comentado.
  - Email de contacto: arquimedesgr@gmail.com.

### 1b. Pantalla "Términos y Condiciones"
- En la misma pantalla de Privacidad, agregar acceso a "Términos y Condiciones" (mismo patrón: resumen + link a URL pública).
- URL pública esperada: `https://arquimedesgarcia.github.io/gota/terms.html` (archivo `docs/site/terms.html`, mismo mecanismo que la política).
- Al primer arranque de la app (una sola vez, persistido en preferencias), mostrar un diálogo breve: "Al usar Gota aceptas los Términos y la Política de Privacidad" con enlaces a ambos y botones "Aceptar" / "Ver términos". Sin aceptación, la app puede seguir, pero el diálogo no vuelve a aparecer (no bloquear el uso).

### 1c. Botón "Reportar" en cada reporte (requisito UGC de Google Play)
- Google Play exige que apps con contenido de usuarios ofrezcan un mecanismo de **reporte de contenido inapropiado y bloqueo**. Implementar:
  - En el detalle de cada reporte ajeno, acción "Reportar" → selector de motivo (información falsa / contenido ofensivo / fotos inapropiadas / otro + texto opcional) → guarda denuncia en tabla nueva `report_abuse_flags` (migración propia: id, report_id FK, reporter anon uuid, reason, note, created_at, resuelto por defecto false; RLS: solo inserts por usuarios autenticados, selects solo para rol admin/service).
  - Contacto directo por abuso: en la pantalla de Privacidad, nota visible "Denuncia contenido: arquimedesgr@gmail.com".
  - El desarrollador (Arquímedes) revisará las denuncias; NO implementar eliminación automática ni panel de moderación en esta iteración (queda en backlog), solo el registro.
- Crear la migración en `supabase/migrations/` con numeración posterior a la última existente, siguiendo el patrón de las actuales.

### 2. Razonamiento de permisos (pre-permiso)
- Antes de solicitar `ACCESS_FINE_LOCATION` por primera vez, mostrar un diálogo propio (no el nativo) con texto:
  > "Gota usa tu ubicación únicamente para registrar dónde está la fuga que estás reportando. No se rastrea tu posición en segundo plano."
  - Botones: "Continuar" (procede a pedir el permiso nativo) y "Ahora no".
  - Solo se muestra una vez (guardar flag en el draft_store / preferencias existentes).
- Hacer lo mismo (dilogo más corto) antes de `POST_NOTIFICATIONS`:
  > "Te avisaremos cuando haya reportes cerca mientras tengas la app abierta."
- Si el usuario niega, la app debe seguir usable: reporte manual sin GPS (verificar que ese flujo ya existe; si no, NO inventarlo, reportarlo en el PR como hallazgo).
- Ubicar los puntos exactos donde hoy se piden los permisos (buscar `Location.requestPermission` / `permission_handler` / `geolocator` en lib/) y ejecutar el diálogo justo antes, sin reordenar la lógica.

### 3. URL pública de la política
- Crear en el repo los archivos `docs/site/privacy.html` y `docs/site/terms.html` (contenido de `docs/POLITICA_PRIVACIDAD.md` y `docs/TERMINOS_Y_CONDICIONES.md` en HTML simple, enlazándose entre sí), para publicar vía **GitHub Pages** desde la carpeta /docs del repo. El desarrollador NO debe activar Pages (lo hace Arquímedes desde GitHub); solo preparar los archivos y dejar en la descripción del PR las URLs finales esperadas:
  - `https://arquimedesgarcia.github.io/gota/privacy.html`
  - `https://arquimedesgarcia.github.io/gota/terms.html`

### 4. Texto para Play Console (entregable, no código)
- Crear `docs/play_console_textos.md` con:
  - Descripción corta (máx 80 car.) y larga (4000) de la ficha. La descripción debe aclarar: "información comunitaria generada por usuarios, no afiliada a Hidroven ni a entes oficiales, no es un servicio de emergencias".
  - Declaración "Datos y seguridad" lista para copiar: tipos de datos recolectados (ubicación aproximada/precisa, fotos, IDs anónimos) marcados como "no compartidos" y "opcional/borrable por solicitud".
  - Respuestas sugeridas para el cuestionario de Contenido UGC: la app permite publicar contenido de usuarios → declara mecanismo de reporte in-app (función "Reportar" + email de denuncia) y moderación posterior del desarrollador.
  - Nota sobre clasificación de contenido: declarar la app como no dirigida a menores.

## Restricciones
- Sin dependencias nuevas salvo que sea imprescindible (preferir `url_launcher` solo si no hay ya un abrir-enlaces en el código; verificar antes).
- No modificar repositorios, modelos ni migraciones.
- Commits en `main`, uno por tarea, mensajes en español.

## Criterios de aceptación
1. Desde la app se llega a una pantalla de privacidad con links funcionales a la política y a los términos.
2. Primera solicitud de ubicación y notificaciones muestra primero el diálogo explicativo.
3. Negar permisos no rompe el flujo de reporte manual.
4. Cada reporte ajeno ofrece la acción "Reportar" que registra la denuncia en `report_abuse_flags`.
5. `flutter analyze` sin nuevos warnings; `flutter test` pasa.
6. Existen `docs/site/privacy.html`, `docs/site/terms.html` y `docs/play_console_textos.md`.
