import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gota/features/leaks/data/leak_community_repository.dart';
import 'package:gota/features/leaks/domain/community_activity.dart';
import 'package:gota/features/leaks/domain/leak_community.dart';
import 'package:gota/features/map/presentation/map_providers.dart';

class _CountingRepository implements LeakCommunityRepository {
  int mapCalls = 0;

  @override
  Future<List<LeakSummary>> recentReports({int limit = 20}) async => const [];

  @override
  Future<LeakDetail> reportDetail(String reportId) => throw UnimplementedError();

  @override
  Future<CommunityActionResult> validateLeak(String reportId) =>
      throw UnimplementedError();

  @override
  Future<CommunityActionResult> confirmResolution(String reportId) =>
      throw UnimplementedError();

  @override
  Future<CommunityActivity?> latestActivity() async => null;

  @override
  Future<List<LeakSummary>> mapReports({
    String? status,
    String? sectorId,
    double? minLat,
    double? minLng,
    double? maxLat,
    double? maxLng,
    String orderBy = 'recent',
    int limit = 100,
  }) async {
    mapCalls++;
    return const [];
  }
}

void main() {
  test('creación exitosa seguida de invalidación reconsulta el mapa', () async {
    final repository = _CountingRepository();
    final container = ProviderContainer(
      overrides: [leakCommunityRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await container.read(mapReportsProvider.future);
    expect(repository.mapCalls, 1);

    // Equivale a la invalidación ejecutada por AppShell al recibir true
    // de LeakReportScreen después de crear el reporte.
    container.invalidate(mapReportsProvider);
    await container.read(mapReportsProvider.future);

    expect(repository.mapCalls, 2);
  });
}
