import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late Directory temp;
  late File db;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_opencode_');
    db = File('${temp.path}/opencode.db');
    final database = sqlite3.open(db.path);
    database.execute('''
      CREATE TABLE credential (
        id TEXT, integration_id TEXT, label TEXT, value TEXT, active INTEGER
      )
    ''');
    database.execute(
      'INSERT INTO credential(id, integration_id, label, value, active) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        'cred_1',
        'opencode-go',
        'OpenCode Go',
        jsonEncode({
          'type': 'key',
          'key': 'oc_test_abcdefghijklmnopqrstuvwxyz',
        }),
        1,
      ],
    );
    database.close();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  ProviderContext context(http.Client client) => ProviderContext(
    paths: AppPaths(temp),
    http: client,
    process: FakeProcessRunner(),
    env: {'QDECK_OPENCODE_DB': db.path},
    now: () => DateTime.utc(2026, 11, 8, 12),
    log: (_) {},
  );

  test('reads and normalizes usage', () async {
    final fixture = File('test/fixtures/opencode-go-usage.json')
        .readAsStringSync();
    final provider = const OpenCodeProvider();
    final snapshot = await provider.read(
      context(MockClient((_) async => http.Response(fixture, 200))),
    );

    expect(snapshot.provider, ProviderId.opencode);
    expect(snapshot.windows, hasLength(3));
    expect(snapshot.windows[0].id, 'rolling');
    expect(snapshot.windows[0].usedPercent, 2);
    expect(snapshot.windows[1].usedPercent, 20);
    expect(snapshot.windows[2].usedPercent, 16);
    expect(snapshot.confidence, Confidence.medium);
  });

  test('reads oauth credential and sends org header', () async {
    final database = sqlite3.open(db.path);
    database.execute(
      'UPDATE credential SET value = ? WHERE integration_id = ?',
      [
        jsonEncode({
          'type': 'oauth',
          'access': 'oauth-token',
          'metadata': {'orgID': 'wrk_123'},
        }),
        'opencode-go',
      ],
    );
    database.close();

    Map<String, String>? sentHeaders;
    final fixture = File('test/fixtures/opencode-go-usage.json')
        .readAsStringSync();
    final snapshot = await const OpenCodeProvider().read(
      context(
        MockClient((request) async {
          sentHeaders = request.headers;
          return http.Response(fixture, 200);
        }),
      ),
    );
    expect(snapshot.windows, hasLength(3));
    expect(sentHeaders?['x-opencode-org-id'], 'wrk_123');
  });

  test('detects credential', () async {
    final result = await const OpenCodeProvider().detect(
      context(MockClient((_) async => http.Response('{}', 200))),
    );
    expect(result.detected, isTrue);
  });

  test('maps 401 to authExpired', () async {
    final provider = const OpenCodeProvider();
    expect(
      () => provider.read(
        context(MockClient((_) async => http.Response('{"error":"no"}', 401))),
      ),
      throwsA(
        isA<QdeckException>().having(
          (e) => e.code,
          'code',
          QdeckErrorCode.authExpired,
        ),
      ),
    );
  });
}
