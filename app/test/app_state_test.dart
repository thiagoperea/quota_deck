import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'support/fake_api.dart';
import 'package:quota_deck/src/api/quota_api.dart';
import 'package:quota_deck/src/state/app_state.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

/// API controlada para provar que refreshes concorrentes não são descartados.
class _GatedApi implements QuotaApi {
  int refreshCalls = 0;
  final List<Completer<void>> gates = [];

  SnapshotEnvelope _envelope() => SnapshotEnvelope(
    generatedAt: DateTime.utc(2026, 11, 10, 12),
    results: [
      ProviderSnapshot(
        provider: ProviderId.opencode,
        account: const AccountInfo(label: 'OpenCode'),
        windows: [
          QuotaWindow(
            id: 'weekly',
            label: 'Semanal (7d)',
            kind: WindowKind.weekly,
            usedPercent: 20,
            remainingPercent: 80,
            status: QuotaStatus.ok,
            source: SourceKind.api,
          ),
        ],
        source: 'test',
        fetchedAt: DateTime.utc(2026, 11, 10, 12),
      ),
    ],
  );

  @override
  Future<SummaryPayload> fetchSummary() async => SummaryPayload(
    envelope: _envelope(),
    config: AppConfig.defaults().copyWith(onboardingCompleted: true),
    meta: const ApiMeta(version: 'test'),
  );

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) async {
    refreshCalls += 1;
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return _envelope();
  }

  @override
  Future<List<DetectionResult>> detect() async => const [];

  @override
  Future<List<DoctorCheck>> fetchDoctor() async => const [];

  @override
  Future<HistorySummary> fetchHistory({
    required ProviderId provider,
    required String windowId,
    int hours = 24,
  }) async => HistorySummary(
    provider: provider,
    windowId: windowId,
    samples: const [],
    burnRatePerHour: 0,
  );

  @override
  Future<AppConfig> fetchSettings() async => AppConfig.defaults();

  @override
  Future<AppConfig> saveSettings(AppConfig config) async => config;

  @override
  Future<void> close() async {}
}

void main() {
  test('initialize carrega summary, configurações e histórico', () async {
    final api = FakeQuotaApi();
    final state = AppState(api);
    addTearDown(state.dispose);

    await state.initialize();

    expect(state.loading, isFalse);
    expect(state.error, isNull);
    expect(state.hasData, isTrue);
    expect(state.visibleSnapshots, hasLength(4));
    expect(state.config.theme, 'dark');
    expect(state.tightest?.snapshot.provider, ProviderId.opencode);
    expect(state.tightest?.window.id, 'weekly');
    expect(state.nextReset, isNotNull);
    expect(state.nextReset!.snapshot.provider, isNot(ProviderId.codex));
    expect(state.featuredHistory, isNotNull);
    expect(state.featuredHistory!.samples, isNotEmpty);
    expect(state.upcomingResets(), isNotEmpty);
    expect(state.estimatedAvailablePercent, isNotNull);
    expect(state.enabledProviderCount, 4);
    expect(state.config.onboardingCompleted, isFalse);

    await state.detectProviders();
    expect(state.detections, hasLength(4));
    expect(state.installedProviders, hasLength(4));
    final claude = state.detectionFor(ProviderId.claude);
    expect(claude, isNotNull);
    expect(claude!.installedSurfaces, isNotEmpty);
  });

  test('primeira execução habilita só provedores detectados', () async {
    final state = AppState(
      FakeQuotaApi(
        installedProviders: {ProviderId.opencode, ProviderId.codex},
        config: AppConfig.defaults().copyWith(
          onboardingCompleted: false,
          refreshSeconds: 0,
        ),
      ),
    );
    addTearDown(state.dispose);

    await state.initialize();
    await state.detectProviders();

    expect(state.config.isEnabled(ProviderId.opencode), isTrue);
    expect(state.config.isEnabled(ProviderId.codex), isTrue);
    expect(state.config.isEnabled(ProviderId.antigravity), isFalse);
    expect(state.config.isEnabled(ProviderId.claude), isFalse);
  });

  test('refresh atualiza o envelope sem perder os cards', () async {
    final api = FakeQuotaApi();
    final state = AppState(api);
    addTearDown(state.dispose);
    await state.initialize();
    final before = state.envelope!.generatedAt;

    await state.refresh();

    expect(state.error, isNull);
    expect(state.envelope!.generatedAt.isAfter(before), isTrue);
    expect(state.visibleSnapshots, hasLength(4));
    expect(state.refreshing, isFalse);
  });

  test('falha inicial vira erro amigável e permite retry', () async {
    final state = AppState(FakeQuotaApi(failSummary: true));
    addTearDown(state.dispose);

    await state.initialize();

    expect(state.loading, isFalse);
    expect(state.hasData, isFalse);
    expect(state.error, contains('Falha simulada'));
    expect(state.visibleSnapshots, isEmpty);
  });

  test('falha no refresh mantém o snapshot anterior', () async {
    final state = AppState(FakeQuotaApi(failRefresh: true));
    addTearDown(state.dispose);
    await state.initialize();
    final before = state.envelope!.generatedAt;

    await state.refresh();

    expect(state.error, contains('Falha simulada'));
    expect(state.envelope!.generatedAt, before);
    expect(state.refreshing, isFalse);
  });

  test('saveSettings persiste no core e reflete no estado', () async {
    final api = FakeQuotaApi();
    final state = AppState(api);
    addTearDown(state.dispose);
    await state.initialize();

    final next = state.config.copyWith(
      refreshSeconds: 120,
      providers: {...state.config.providers, 'opencode': false},
    );
    final saved = await state.saveSettings(next);

    expect(saved, isTrue);
    expect(state.config.refreshSeconds, 120);
    expect(state.config.isEnabled(ProviderId.opencode), isFalse);
    expect(
      state.visibleSnapshots.any(
        (snapshot) => snapshot.provider == ProviderId.opencode,
      ),
      isFalse,
    );
    expect((await api.fetchSettings()).refreshSeconds, 120);
  });

  test('falha ao salvar configurações retorna false e mensagem', () async {
    final state = AppState(FakeQuotaApi(failSettings: true));
    addTearDown(state.dispose);
    await state.initialize();

    final saved = await state.saveSettings(state.config);

    expect(saved, isFalse);
    expect(state.error, contains('Falha simulada'));
    expect(state.saving, isFalse);
  });

  test('loadHistory busca amostras para uma janela', () async {
    final state = AppState(FakeQuotaApi());
    addTearDown(state.dispose);
    await state.initialize();

    final history = await state.loadHistory(
      ProviderId.opencode,
      'rolling-5h',
      hours: 12,
    );

    expect(history, isNotNull);
    expect(history!.samples, hasLength(12));
    expect(history.burnRatePerHour, greaterThan(0));
  });

  test('saveSettings aplica a inicialização automática no sistema', () async {
    bool? applied;
    final state = AppState(
      FakeQuotaApi(),
      onLaunchAtLoginChanged: (enabled) async {
        applied = enabled;
        return true;
      },
    );
    addTearDown(state.dispose);
    await state.initialize();

    await state.saveSettings(state.config.copyWith(launchAtLogin: true));

    expect(applied, isTrue);
    expect(state.config.launchAtLogin, isTrue);
    expect(state.error, isNull);
  });

  test('detecção explícita liga o detectado sem desligar os demais', () async {
    final state = AppState(
      FakeQuotaApi(
        installedProviders: {ProviderId.opencode, ProviderId.codex},
        config: AppConfig.defaults().copyWith(
          onboardingCompleted: true,
          refreshSeconds: 0,
          providers: const {
            'opencode': false,
            'codex': false,
            'antigravity': true,
            'claude': false,
          },
        ),
      ),
    );
    addTearDown(state.dispose);
    await state.initialize();

    expect(state.config.isEnabled(ProviderId.opencode), isFalse);

    await state.redetect();

    expect(state.config.isEnabled(ProviderId.opencode), isTrue);
    expect(state.config.isEnabled(ProviderId.codex), isTrue);
    expect(state.config.isEnabled(ProviderId.antigravity), isTrue);
  });

  test('ordem e visibilidade personalizadas afetam o painel', () async {
    final state = AppState(FakeQuotaApi());
    addTearDown(state.dispose);
    await state.initialize();

    await state.saveSettings(
      state.config.copyWith(providerOrder: const ['claude', 'opencode']),
    );
    expect(state.visibleSnapshots.first.provider, ProviderId.claude);

    final claude = state.visibleSnapshots.first;
    final windowId = claude.windows.first.id;
    await state.saveSettings(
      state.config.withWindowVisibility(
        ProviderId.claude,
        windowId,
        WindowVisibility.hidden,
      ),
    );

    expect(
      state.windowsFor(claude).any((window) => window.id == windowId),
      isFalse,
    );
  });

  test('refresh concorrente espera e dispara uma segunda rodada', () async {
    final api = _GatedApi();
    final state = AppState(api);
    addTearDown(state.dispose);
    await state.initialize();

    final first = state.refresh();
    await Future<void>.delayed(Duration.zero);
    expect(api.refreshCalls, 1);

    // Chega durante a primeira rodada: não pode ser descartado.
    final concurrent = state.refresh();
    api.gates.first.complete();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      api.refreshCalls,
      2,
      reason: 'o pedido concorrente deve gerar uma nova rodada',
    );

    api.gates.last.complete();
    await Future.wait([first, concurrent]);
    expect(state.refreshing, isFalse);
    expect(state.error, isNull);
  });
}
