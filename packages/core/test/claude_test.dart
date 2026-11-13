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

  group('macOS: Keychain e CLAUDE_CONFIG_DIR', () {
    const keychainQuery =
        'security find-generic-password -s '
        'Claude Code-credentials -w';

    ProviderContext macContext({
      Map<String, String> env = const {},
      Map<String, ProcessResultData> results = const {},
    }) => ProviderContext(
      paths: AppPaths(temp),
      http: MockClient((_) async => http.Response('{}', 200)),
      process: FakeProcessRunner(results: results),
      env: {'HOME': temp.path, ...env},
      now: () => DateTime.utc(2026, 11, 8, 12),
      log: (_) {},
    );

    test('Keychain negado vira permissionDenied, não authMissing', () async {
      if (!Platform.isMacOS) return;
      // CLI instalada (binário em ~/.local/bin), mas o Keychain nega acesso.
      final binDir = Directory('${temp.path}/.local/bin');
      await binDir.create(recursive: true);
      await File('${binDir.path}/claude').writeAsString('#!/bin/sh\n');
      final claudeDir = Directory('${temp.path}/.claude');
      await claudeDir.create();
      await File('${claudeDir.path}/.credentials.json').writeAsString(
        jsonEncode({
          'claudeAiOauth': {'accessToken': 'x', 'expiresAt': 1795000000000},
        }),
      );
      await expectLater(
        const ClaudeProvider().read(
          macContext(
            results: const {
              keychainQuery: ProcessResultData(
                exitCode: 51,
                stdout: '',
                stderr:
                    'The user name or passphrase you entered is not correct.',
              ),
            },
          ),
        ),
        throwsA(
          isA<QdeckException>().having(
            (e) => e.code,
            'code',
            QdeckErrorCode.permissionDenied,
          ),
        ),
      );
    });

    test('CLAUDE_CONFIG_DIR usa o arquivo antes do Keychain', () async {
      if (!Platform.isMacOS) return;
      final customDir = Directory('${temp.path}/claude-custom');
      await customDir.create();
      await File('${customDir.path}/.credentials.json').writeAsString(
        jsonEncode({
          'claudeAiOauth': {
            'accessToken': 'token-custom-dir',
            'expiresAt': 1795000000000,
            'subscriptionType': 'team',
          },
        }),
      );

      final fixture = File('test/fixtures/claude-oauth-usage.example.json')
          .readAsStringSync();
      final snapshot = await const ClaudeProvider().read(
        ProviderContext(
          paths: AppPaths(temp),
          http: MockClient(
            (_) async => http.Response(
              fixture,
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
          process: FakeProcessRunner(
            results: const {
              keychainQuery: ProcessResultData(
                exitCode: 44,
                stdout: '',
                stderr:
                    'The specified item could not be found in the keychain.',
              ),
            },
          ),
          env: {'HOME': temp.path, 'CLAUDE_CONFIG_DIR': customDir.path},
          now: () => DateTime.utc(2026, 11, 8, 12),
          log: (_) {},
        ),
      );
      expect(snapshot.account.plan, 'team');
    });
  });
}
