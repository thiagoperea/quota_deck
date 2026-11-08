import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/api/mock_api.dart';
import 'package:quota_deck/src/state/app_state.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

void main() {
  test('initialize carrega summary, configurações e histórico', () async {
    final api = MockApi();
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
    expect(state.nextReset?.snapshot.provider, ProviderId.antigravity);
    expect(state.featuredHistory, isNotNull);
    expect(state.featuredHistory!.samples, isNotEmpty);
    expect(state.upcomingResets(), isNotEmpty);
  });

  test('refresh atualiza o envelope sem perder os cards', () async {
    final api = MockApi();
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
    final state = AppState(MockApi(failSummary: true));
    addTearDown(state.dispose);

    await state.initialize();

    expect(state.loading, isFalse);
    expect(state.hasData, isFalse);
    expect(state.error, contains('Falha simulada'));
    expect(state.visibleSnapshots, isEmpty);
  });

  test('falha no refresh mantém o snapshot anterior', () async {
    final state = AppState(MockApi(failRefresh: true));
    addTearDown(state.dispose);
    await state.initialize();
    final before = state.envelope!.generatedAt;

    await state.refresh();

    expect(state.error, contains('Falha simulada'));
    expect(state.envelope!.generatedAt, before);
    expect(state.refreshing, isFalse);
  });

  test('saveSettings persiste no core e reflete no estado', () async {
    final api = MockApi();
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
    final state = AppState(MockApi(failSettings: true));
    addTearDown(state.dispose);
    await state.initialize();

    final saved = await state.saveSettings(state.config);

    expect(saved, isFalse);
    expect(state.error, contains('Falha simulada'));
    expect(state.saving, isFalse);
  });

  test('loadHistory busca amostras para uma janela', () async {
    final state = AppState(MockApi());
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
}
