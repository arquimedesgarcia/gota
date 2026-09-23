# PROMPT 7 — PRESUPUESTO DE RESOLUCIÓN DE FOTO (adoptado del prompt del owner)

**Origen:** instrucción del dueño del producto pegada el 2026-09-23 (punto 6: «No necesitamos fotografía
de alta resolución … evitar procesamiento excesivo en memoria»), adoptada en la **revisión v5** del plan.
**Clasificación:** BETA FIX de mantenibilidad/estabilidad (no es BLOCKER de piloto).
**Estado:** código implementado por el orquestador; tests delegados al motor gratuito.

## Qué cambia

| | Antes | Ahora |
|---|---|---|
| Recorte en `image_picker` (`maxWidth/maxHeight`) | 1920 | `kReportPhotoPickerMaxDimension` = **1280** |
| Pase de compresión (`minWidth/minHeight`) | 1920 / 1080 | `kReportPhotoCompressMaxDimension` = **1280** |
| Calidad del pase de compresión | 82 | `kReportPhotoCompressQuality` = **75** |
| Inyección del pase | directo al plugin | `PhotoCompressCall` inyectable (`compressWithPlugin` por defecto) |

Archivos: `lib/features/leaks/data/photo_limits.dart` (constantes nuevas) y
`lib/features/leaks/data/photo_service.dart` (constantes + seam + `compressedPath` provisto por el pase).

## Por qué

- El hallazgo 2 (cierres al tomar/elegir foto) tiene como hipótesis principal **muerte de proceso / OOM
  nativo** durante el decode de una foto de 12 MP. Bajar el techo de resolución reduce directamente ese
  pico: `image_picker` recorta primero (resize nativo) y el segundo decode/reencode trabaja sobre una
  imagen menor.
- Subida más estable y almacenamiento razonable (evidencia visual de una fuga no necesita más de 1280 px).

## Semántica del plugin (verificada, no asumida)

`flutter_image_compress` documenta que `minWidth`/`minHeight` **acotan el tamaño de salida** pese al
nombre (`README.md:149-169`, con la FAQ «Why is minWidth/minHeight named that if it acts like a max»).
El pase de compresión **sigue existiendo** porque es el que elimina el EXIF GPS que `image_picker`
reinyecta (`image_picker_android/.../ExifDataCopier.java`): bajarlo a un no-op de resize es correcto,
eliminarlo no.

**Límite declarado:** el recorte del lado mayor lo hace el resize nativo de `image_picker`, no testeable
en Dart. Lo que la suite fija es **qué parámetros pide nuestro código** (seam `compress`), no el pixel
final.

## Cobertura

`test/features/leaks/photo_service_test.dart`, grupo nuevo con el seam:
1. el pase se pide acotado (≤ 1280 px, calidad acotada) y se usa la ruta devuelta como
   `compressedPath`;
2. compresión que devuelve `null` → `PhotoValidationException`;
3. compresión que lanza un `Error` → `PhotoValidationException` (no se propaga).

Control de mutación (lo ejecuta el orquestador): volver a 1920/1080/82 debe **hacer fallar** el test 1;
quitar el `try/catch` debe hacer fallar el test 3.

## Lo que NO cambia

La regla de máximo **2 fotos** y su mensaje, la validación de formato/tamaño (10 MB), el contrato de
`PreparedPhoto`, la RPC `create_leak_report`, RLS/Storage y el modelo de datos.
