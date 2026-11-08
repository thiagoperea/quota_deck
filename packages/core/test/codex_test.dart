import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

class _RespondingCodexSession extends FakeProcessSession {
  @override
  void writeLine(String line) {
    super.writeLine(line);
    if (line.contains('account/rateLimits/read')) {
      Future<void>.microtask(() {
        emit(
          jsonEncode({
            'id': 1,
            'result': {
              'rateLimits': {
                'limitId': 'codex',
                'primary': {
                  'usedPercent': 25,
                  'windowDurationMins': 300,
                  'resetsAt': 1794163949,
                },
                'secondary': {
                  'usedPercent': 62,
                  'windowDurationMins': 10080,
                  'resetsAt': 1794517920,
                },
                'rateLimitReachedType': null,
              },
              'rateLimitResetCredits': {'availableCount': 2},
            },
          }),
        );
        finish();
      });
    }
  }
}

void main() {
  late Directory temp;
  late File auth;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_codex_');
    auth = File('${temp.path}/auth.json');
    await auth.writeAsString(
      jsonEncode({
        'auth_mode': 'chatgpt',
        'tokens': {
          'access_token': 'test-access-token',
          'account_id': 'acct-123',
          'email': 'user@example.com',
        },
      }),
    );
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  ProviderContext context(http.Client client) => ProviderContext(
    paths: AppPaths(temp),
    http: client,
    process: FakeProcessRunner(),
    env: {'QDECK_CODEX_AUTH': auth.path},
    now: () => DateTime.utc(2026, 11, 8, 12),
    log: (_) {},
  );

  test('reads wham usage and credits', () async {
    final fixture = File('test/fixtures/codex-wham-usage.json')
        .readAsStringSync();
    final snapshot = await const CodexProvider().read(
      context(MockClient((_) async => http.Response(fixture, 200))),
    );

    expect(snapshot.provider, ProviderId.codex);
    expect(snapshot.windows, hasLength(2));
    expect(snapshot.windows[0].id, 'primary-5h');
    expect(snapshot.windows[1].id, 'secondary-7d');
    expect(snapshot.account.plan, 'plus');
    expect(snapshot.account.maskedEmail, 'us***@e***.com');
    expect(snapshot.credits?.note, contains('2 resets'));
  });

  test('uses app-server when codex binary is available', () async {
    final session = _RespondingCodexSession();
    final process = FakeProcessRunner(
      results: {
        'codex --version': const ProcessResultData(
          exitCode: 0,
          stdout: 'codex 1.0.0',
          stderr: '',
        ),
        'codex.cmd --version': const ProcessResultData(
          exitCode: 0,
          stdout: 'codex 1.0.0',
          stderr: '',
        ),
      },
      sessions: {'codex app-server': session, 'codex.cmd app-server': session},
    );
    final ctx = ProviderContext(
      paths: AppPaths(temp),
      http: MockClient((_) async => http.Response('{}', 500)),
      process: process,
      env: {'QDECK_CODEX_AUTH': auth.path},
      now: () => DateTime.utc(2026, 11, 8, 12),
      log: (_) {},
    );

    final snapshot = await const CodexProvider().read(ctx);
    expect(snapshot.source, 'codex-app-server');
    expect(snapshot.confidence, Confidence.high);
    expect(snapshot.windows, hasLength(2));
    expect(snapshot.windows.first.id, 'primary-5h');
    expect(snapshot.windows.first.usedPercent, 25);
    expect(snapshot.credits?.note, contains('2 resets'));
  });

  test('maps 401 to authExpired', () async {
    expect(
      () => const CodexProvider().read(
        context(MockClient((_) async => http.Response('{}', 401))),
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
