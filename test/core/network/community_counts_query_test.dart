import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:gota/core/network/gota_community_database.dart';

/// Regresión D1 (S10-C): los conteos comunitarios deben pedir una columna
/// explícita permitida (`select=id`), nunca un `select=*` implícito.
///
/// `reports.created_by` está revocado para `anon`: una petición sin `select`
/// responde HTTP 401 (PG 42501) y la tarjeta quedaba en error permanente.
void main() {
  const start = '2026-09-16T04:00:00.000Z';
  const end = '2026-09-17T04:00:00.000Z';
  const sector = 'af2685cb-a083-5bd2-b5c3-2885da147da9';

  SupabaseGotaCommunityDatabase databaseFor(
    List<http.BaseRequest> seen, {
    int status = 200,
    String contentRange = '0-1/2',
    String body = '[{"id":"a"},{"id":"b"}]',
  }) {
    final client = MockClient((request) async {
      seen.add(request);
      return http.Response(
        body,
        status,
        request: request,
        headers: {
          'content-range': contentRange,
          'content-type': 'application/json',
        },
      );
    });
    return SupabaseGotaCommunityDatabase(
      supabase.SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: client,
      ),
    );
  }

  String selectOf(http.BaseRequest request) =>
      request.url.queryParameters['select'] ?? '';

  test('reportadas con sector: select explícito y conteo del header', () async {
    final seen = <http.BaseRequest>[];
    final db = databaseFor(seen);

    final count = await db.countReportsCreatedBetween(
      startIso: start,
      endIso: end,
      sectorId: sector,
    );

    expect(count, 2);
    expect(seen, hasLength(1));
    final params = seen.single.url.queryParameters;
    expect(selectOf(seen.single), 'id');
    expect(selectOf(seen.single), isNot(contains('created_by')));
    expect(selectOf(seen.single), isNot(contains('*')));
    expect(params['created_at'], contains('lt.'));
    expect(
      seen.single.url.queryParametersAll['created_at'],
      contains(contains('gte.')),
    );
    expect(params['sector_id'], 'eq.$sector');
    expect(seen.single.headers['prefer'], contains('count=exact'));
  });

  test('reportadas global: sin filtro de sector pero con select', () async {
    final seen = <http.BaseRequest>[];
    final db = databaseFor(seen, contentRange: '*/0', body: '[]');

    final count = await db.countReportsCreatedBetween(
      startIso: start,
      endIso: end,
    );

    expect(count, 0);
    expect(selectOf(seen.single), 'id');
    expect(seen.single.url.queryParameters.containsKey('sector_id'), isFalse);
  });

  test('resueltas: filtra RESOLVED + resolved_at con select', () async {
    final seen = <http.BaseRequest>[];
    final db = databaseFor(seen);

    final count = await db.countReportsResolvedBetween(
      startIso: start,
      endIso: end,
      sectorId: sector,
    );

    expect(count, 2);
    final params = seen.single.url.queryParameters;
    expect(selectOf(seen.single), 'id');
    expect(params['status'], 'eq.RESOLVED');
    expect(params['resolved_at'], contains('lt.'));
    expect(
      seen.single.url.queryParametersAll['resolved_at'],
      contains(contains('gte.')),
    );
    expect(params['sector_id'], 'eq.$sector');
  });

  test('401 del backend se propaga como PostgrestException', () async {
    final seen = <http.BaseRequest>[];
    final db = databaseFor(seen, status: 401, body: '{"message":"x"}');

    expect(
      () => db.countReportsCreatedBetween(
        startIso: start,
        endIso: end,
        sectorId: sector,
      ),
      throwsA(isA<supabase.PostgrestException>()),
    );
  });
}
