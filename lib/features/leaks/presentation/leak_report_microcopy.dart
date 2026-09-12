/// Microcopy del flujo Reportar fuga (UX_SPEC §4/§5), centralizado.
abstract final class LeakReportCopy {
  // ---------- Ubicación (Sprint 05: mapa) ----------
  static const manualHint =
      'Por ahora indicas la coordenada exacta; en el próximo paso de la app '
      'podrás elegir el punto en el mapa.';

  // ---------- Fotos ----------
  static const pickSourceTitle = 'Agregar foto';
  static const fromCamera = 'Tomar con la cámara';
  static const fromGallery = 'Elegir de la galería';
  static const canceledPick =
      'No se agregó ninguna foto (seleccionaste cancelar).';

  // ---------- Duplicado (UX_SPEC §5) ----------
  static const duplicateTitle = 'Ya existe un reporte de fuga cerca.';
  static String duplicateDistance(int meters) =>
      'A $meters metros hay un reporte activo. ¿Tu fuga es la misma?';
  static const duplicateViewAndValidate = 'Ver y validar';
  static const duplicateUseExisting = 'Es la misma: usar ese reporte';
  static const duplicateOtherLeak = 'Es otra fuga';

  // ---------- Resultado ----------
  static const useExistingResult =
      'Usaste el reporte existente. Puedes validarlo en su detalle.';
}
