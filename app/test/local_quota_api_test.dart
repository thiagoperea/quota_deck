import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/api/local_quota_api.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

class _FakeQuotaService implements QuotaService {
  AppConfig config = AppConfig.defaults();
  int refreshCalls = 0;

  SnapshotEnvelope _envelope() => SnapshotEnvelope(
    generatedAt: DateTime.utc(2026, 11, 8, 12),
    results: [
      ProviderSnapshot(
        provider: ProviderId.opencode,
        account: const AccountInfo(label: 'OpenCode Go', plan: 'Go'),
        windows: [
          QuotaWindow(
            id: 'rolling',
            label: 'Rolling 5h',
            kind: WindowKind.rolling,
            usedPercent: 4,
            remainingPercent: 96,
            resetsAt: DateTime.utc(2026, 11, 8, 18),
            status: QuotaStatus.ok,
            source: SourceKind.api,
          ),
        ],
        source: 'test',
        fetchedAt: DateTime.utc(2026, 11, 8, 12),
        confidence: Confidence.high,
      ),
    ],
  );

  @override
  Future<SnapshotEnvelope> snapshot({
    Set<ProviderId>? providers,
    bool noCache = false,
  }) async => _envelope();

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) async {
    refreshCalls++;
    return _envelope();
  }

  @override
  Future<List<DetectionResult>> detect() async => const [];

  @override
  Future<List<DoctorCheck>> doctor() async => const [];

  @override
  Future<AppConfig> getConfig() async => config;

  @override
  Future<AppConfig> updateConfig(AppConfig next) async {
    config = next;
    return config;
  }

  @override
  Future<HistorySummary> history({
    required ProviderId provider,
    required String windowId,
    Duration window = const Duration(hours: 24),
  }) async => HistorySummary(
    provider: provider,
    windowId: windowId,
    samples: const [],
    burnRatePerHour: 0,
  );

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory temp;
  late _FakeQuotaService fake;
  late LocalQuotaApi api;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_local_api_');
    fake = _FakeQuotaService();
    api = LocalQuotaApi(
      paths: AppPaths(temp),
      serviceFactory: (_) async => fake,
    );
  });

  tearDown(() async {
    api.close();
    await temp.delete(recursive: true);
  });

  test('fetchSummary usa o core local e monta meta', () async {
    final summary = await api.fetchSummary();
    expect(summary.envelope.results.single.provider, ProviderId.opencode);
    expect(summary.envelope.results.single.windows.single.usedPercent, 4);
    expect(summary.config.refreshSeconds, 60);
    expect(summary.meta.dataDir, isNotNull);
    expect(summary.meta.providers, hasLength(4));
  });

  test('refresh, settings e history delegam ao serviço', () async {
    await api.refresh(provider: ProviderId.opencode);
    expect(fake.refreshCalls, 1);

    final saved = await api.saveSettings(
      fake.config.copyWith(theme: 'light', refreshSeconds: 120),
    );
    expect(saved.theme, 'light');
    expect(saved.refreshSeconds, 120);

    final history = await api.fetchHistory(
      provider: ProviderId.opencode,
      windowId: 'rolling',
    );
    expect(history.windowId, 'rolling');
  });

  test('worker em isolate próprio responde e persiste configuração', () async {
    final dir = await Directory.systemTemp.createTemp('qdeck-worker');
    final worker = LocalQuotaApi(paths: AppPaths(dir));
    try {
      final config = await worker.fetchSettings();
      expect(config.refreshSeconds, greaterThan(0));

      final saved = await worker.saveSettings(
        config.copyWith(refreshSeconds: 90),
      );
      expect(saved.refreshSeconds, 90);

      final again = await worker.fetchSettings();
      expect(again.refreshSeconds, 90);
    } finally {
      await worker.close();
      await dir.delete(recursive: true);
    }
  });
}
