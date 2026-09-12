class PossibleDuplicateCandidate {
  const PossibleDuplicateCandidate({
    required this.id,
    required this.sectorId,
    required this.distanceMeters,
    required this.createdAt,
  });

  factory PossibleDuplicateCandidate.fromJson(Map<String, dynamic> json) =>
      PossibleDuplicateCandidate(
        id: json['id'] as String,
        sectorId: json['sector_id'] as String? ?? '',
        distanceMeters: (json['distance_meters'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  final String id;
  final String sectorId;
  final int distanceMeters;
  final DateTime createdAt;
}

/// Resultado de la RPC `create_leak_report`.
sealed class CreateLeakReportOutcome {
  const CreateLeakReportOutcome();
}

class ReportCreated extends CreateLeakReportOutcome {
  const ReportCreated({required this.reportId});

  final String reportId;
}

/// El backend detectó reportes ACTIVE ≤50 m creados en ≤48 h.
class PossibleDuplicateFound extends CreateLeakReportOutcome {
  const PossibleDuplicateFound({required this.candidates});

  final List<PossibleDuplicateCandidate> candidates;
}

class LeakReportUnauthorized extends CreateLeakReportOutcome {
  const LeakReportUnauthorized();
}
