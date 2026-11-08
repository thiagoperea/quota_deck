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

  @override
  ProviderId get id => ProviderId.opencode;

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async =>
      const DetectionResult(provider: ProviderId.opencode, detected: true);

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    calls++;
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

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_service_');
    final paths = AppPaths(temp);
    final configStore = ConfigStore(paths.configFile);
    await configStore.save(AppConfig.defaults());
    adapter = _FakeAdapter();
    service = DefaultQuotaService(
      paths: paths,
      cache: SnapshotCache(),
      configStore: configStore,
      historyStore: null,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      processRunner: FakeProcessRunner(),
      env: const {},
      now: () => DateTime.utc(2026, 11, 8, 12),
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
}
