import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ReportAbuseRepository {
  Future<void> flagReport({
    required String reportId,
    required String reporterId,
    required String reason,
    String? note,
  });
}

class SupabaseReportAbuseRepository implements ReportAbuseRepository {
  const SupabaseReportAbuseRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<void> flagReport({
    required String reportId,
    required String reporterId,
    required String reason,
    String? note,
  }) async {
    await _client.from('report_abuse_flags').insert({
      'report_id': reportId,
      'reporter_id': reporterId,
      'reason': reason,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }
}

final reportAbuseRepositoryProvider = Provider<ReportAbuseRepository>(
  (ref) => SupabaseReportAbuseRepository(Supabase.instance.client),
);
