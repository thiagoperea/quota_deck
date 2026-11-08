import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late Directory temp;
  late File creds;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_claude_');
    creds = File('${temp.path}/credentials.json');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<void> writeCreds({required int expiresAt}) async {
    await creds.writeAsString(
      jsonEncode({
        'claudeAiOauth': {
          'accessToken': 'claude-test-token',
          'refreshToken': 'refresh-test',
          'expiresAt': expiresAt,
          'subscriptionType': 'pro',
        },
      }),
    );
  }

  ProviderContext context(http.Client client) => ProviderContext(
    paths: AppPaths(temp),
    http: client,
    process: FakeProcessRunner(),
    env: {'QDECK_CLAUDE_CREDS': creds.path},
    now: () => DateTime.utc(2026, 11, 8, 12),
    log: (_) {},
  );

  test('reads oauth usage with extra_usage', () async {
    await writeCreds(expiresAt: 1795000000000); // futuro
    final fixture = File('test/fixtures/claude-oauth-usage.example.json')
        .readAsStringSync();
    final snapshot = await const ClaudeProvider().read(
      context(
        MockClient(
          (_) async => http.Response(
            fixture,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      ),
    );

    expect(snapshot.provider, ProviderId.claude);
    expect(snapshot.windows, hasLength(3)); // opus null é omitido
    expect(snapshot.windows.first.usedPercent, 12);
    expect(snapshot.credits?.hasCredits, isTrue);
    expect(snapshot.account.plan, 'pro');
  });

  test('does not hit network when token is expired', () async {
    await writeCreds(expiresAt: 1782791603444); // passado
    var called = false;
    expect(
      () => const ClaudeProvider().read(
        context(
          MockClient((_) async {
            called = true;
            return http.Response('{}', 200);
          }),
        ),
      ),
      throwsA(
        isA<QdeckException>().having(
          (e) => e.code,
          'code',
          QdeckErrorCode.authExpired,
        ),
      ),
    );
    expect(called, isFalse);
  });
}
