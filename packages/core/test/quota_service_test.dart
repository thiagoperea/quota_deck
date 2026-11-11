import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/sample.dart';

class _FakeAdapter implements ProviderAdapter {
  int calls = 0;
  bool fail = false;
  bool rateLimit = false;

  @override
  ProviderId get id => ProviderId.opencode;

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async =>
      const DetectionResult(provider: ProviderId.opencode, detected: true);

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    calls++;
    if (rateLimit) {
      throw const QdeckException(
        code: QdeckErrorCode.rateLimited,
        provider: ProviderId.opencode,
        message: 'slow down',
        details: {'retryAfterSeconds': 120},
      );
    }
    if (fail) {
      throw const QdeckException(
        code: QdeckErrorCode.network,
        provider: ProviderId.opencode,
        message: 'offline',
      );
    }
    return sampleSnapshot(used: calls * 10.0);
  }

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async => const [];
}

void main() {
  late Directory temp;
  late _FakeAdapter adapter;
  late DefaultQuotaService service;
  late SnapshotCache cache;
  late DateTime clock;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_service_');
    final paths = AppPaths(temp);
    final configStore = ConfigStore(paths.configFile);
    await configStore.save(AppConfig.defaults());
    adapter = _FakeAdapter();
    clock = DateTime.utc(2026, 11, 8, 12);
    cache = SnapshotCache();
    service = DefaultQuotaService(
      paths: paths,
      cache: cache,
      configStore: configStore,
      historyStore: null,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      processRunner: FakeProcessRunner(),
      env: const {},
      now: () => clock,
      log: (_) {},
      adapters: [adapter],
    );
  });

  tearDown(() async {
    await service.dispose();
    await temp.delete(recursive: true);
  });

  test('uses cache within ttl and refresh bypasses it', () async {
    final first = await service.snapshot();
    expect(first.results, hasLength(1));
    expect(adapter.calls, 1);

    final cached = await service.snapshot();
    expect(cached.results.first.windows.first.usedPercent, 10);
    expect(adapter.calls, 1);

    final refreshed = await service.refresh();
    expect(refreshed.results.first.windows.first.usedPercent, 20);
    expect(adapter.calls, 2);
  });

  test('falls back to stale cache on error', () async {
    await service.snapshot();
    adapter.fail = true;
    final result = await service.snapshot(noCache: true);
    final snapshot = result.results.first;
    expect(snapshot.stale, isTrue);
    expect(snapshot.errors, isNotEmpty);
    expect(snapshot.windows.first.usedPercent, 10);
  });

  test('429 aplica backoff e não chama o adapter durante o bloqueio', () async {
    adapter.rateLimit = true;
    final first = await service.snapshot();
    expect(adapter.calls, 1);
    expect(first.results.first.errors.first.code, 'RATE_LIMITED');
    final retryAt = parseDate(
      first.results.first.errors.first.details?['retryAt'],
    );
    expect(retryAt, isNotNull);
    expect(retryAt!.isAfter(DateTime.utc(2026, 11, 8, 12)), isTrue);

    // Refresh manual também respeita o bloqueio (Retry-After de 120 s).
    final second = await service.refresh();
    expect(adapter.calls, 1);
    expect(second.results.first.errors.first.code, 'RATE_LIMITED');
  });

  test('backoff expira e o próximo fetch volta a funcionar', () async {
    adapter.rateLimit = true;
    await service.snapshot();
    expect(adapter.calls, 1);
    await service.refresh();
    expect(adapter.calls, 1);

    clock = clock.add(const Duration(minutes: 3));
    adapter.rateLimit = false;
    final after = await service.refresh();
    expect(adapter.calls, 2);
    expect(after.results.first.errors, isEmpty);
    expect(cache.backoffUntil(ProviderId.opencode, now: clock), isNull);
  });
}
