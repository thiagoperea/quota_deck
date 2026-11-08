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
  late File hub;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_antigravity_');
    final daemon = Directory('${temp.path}/.gemini/antigravity/daemon');
    await daemon.create(recursive: true);
    hub = File('${daemon.path}/hub_49195.json');
    await hub.writeAsString(
      jsonEncode({
        'pid': 1234,
        'httpPort': 49195,
        'httpsPort': 0,
        'lsVersion': '2.29.0',
        'csrfToken': 'csrf-test',
      }),
    );
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  ProviderContext context(http.Client client, {int killExit = 0}) =>
      ProviderContext(
        paths: AppPaths(temp),
        http: client,
        process: FakeProcessRunner(
          results: {
            'kill -0 1234': ProcessResultData(
              exitCode: killExit,
              stdout: '',
              stderr: '',
            ),
            'tasklist /FI PID eq 1234 /NH': ProcessResultData(
              exitCode: killExit,
              stdout: killExit == 0 ? '1234' : '',
              stderr: '',
            ),
          },
        ),
        env: {'HOME': temp.path},
        now: () => DateTime.utc(2026, 11, 8, 12),
        log: (_) {},
      );

  test('reads grouped quota via local RPC', () async {
    final fixture = File('test/fixtures/antigravity-quota-summary.json')
        .readAsStringSync();
    final snapshot = await const AntigravityProvider().read(
      context(MockClient((_) async => http.Response(fixture, 200))),
    );

    expect(snapshot.provider, ProviderId.antigravity);
    expect(snapshot.windows, hasLength(5));
    expect(snapshot.windows.first.group, 'Gemini Models');
    expect(snapshot.windows.first.usedPercent, closeTo(4.2, 0.1));
    expect(snapshot.confidence, Confidence.high);
  });

  test('accepts nested/oneof remaining and ignores disabled buckets', () async {
    final body = jsonEncode({
      'response': {
        'groups': [
          {
            'displayName': 'Gemini Models',
            'buckets': [
              {
                'bucketId': 'a',
                'window': '5h',
                'remaining': {'case': 'remainingFraction', 'value': 0.5},
                'resetTime': 1794163949,
              },
              {
                'bucketId': 'b',
                'window': 'weekly',
                'remaining': {'remainingFraction': 0.25},
                'resetTime': '2026-11-15T12:00:00Z',
              },
              {
                'bucketId': 'c',
                'window': 'weekly',
                'remainingFraction': 1,
                'disabled': true,
              },
            ],
          },
        ],
      },
    });
    final snapshot = await const AntigravityProvider().read(
      context(MockClient((_) async => http.Response(body, 200))),
    );
    expect(snapshot.windows, hasLength(2));
    expect(snapshot.windows[0].usedPercent, 50);
    expect(snapshot.windows[1].usedPercent, 75);
    expect(snapshot.windows[0].resetsAt, isNotNull);
  });

  test('reports provider not running when pid is dead', () async {
    expect(
      () => const AntigravityProvider().read(
        context(MockClient((_) async => http.Response('{}', 200)), killExit: 1),
      ),
      throwsA(
        isA<QdeckException>().having(
          (e) => e.code,
          'code',
          QdeckErrorCode.providerNotRunning,
        ),
      ),
    );
  });
}
