import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fake_api.dart';

import 'package:quota_deck/src/app.dart';
import 'package:quota_deck/src/state/app_state.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

Future<AppState> _pumpApp(
  WidgetTester tester, {
  required bool compact,
  required Size size,
  bool empty = false,
  bool onboarded = true,
  bool failRefresh = false,
  Set<ProviderId>? installed,
  FakeScenario? scenario,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = AppState(
    FakeQuotaApi(
      empty: empty,
      installedProviders: installed,
      scenario: scenario,
      failRefresh: failRefresh,
      config: AppConfig.defaults().copyWith(
        theme: 'dark',
        refreshSeconds: 0,
        onboardingCompleted: onboarded,
      ),
    ),
  );
  addTearDown(state.dispose);
  await state.initialize();
  await state.detectProviders();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: QuotaDeckApp(compactOverride: compact),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  Future<void> openHeaderMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('header-menu')));
    await tester.pumpAndSettle();
  }

  test('detecta compact por query string e rota', () {
    expect(isCompactUri(Uri.parse('http://localhost/?compact=1')), isTrue);
    expect(isCompactUri(Uri.parse('http://localhost/compact')), isTrue);
    expect(isCompactUri(Uri.parse('http://localhost/')), isFalse);
  });

  testWidgets('layout compacto empilha cards em ~420px', (tester) async {
    await _pumpApp(tester, compact: true, size: const Size(420, 900));

    expect(find.byKey(const Key('quota-deck-compact')), findsOneWidget);
    expect(find.byKey(const Key('header-refresh')), findsOneWidget);
    expect(find.byKey(const Key('header-menu')), findsOneWidget);
    expect(find.byKey(const Key('header-customize')), findsOneWidget);
    expect(find.byKey(const Key('provider-card-opencode')), findsOneWidget);
    expect(find.byKey(const Key('provider-card-claude')), findsOneWidget);
    expect(find.text('FOLGA'), findsOneWidget);
    expect(find.text('PRÓXIMO RESET'), findsOneWidget);

    final claudeBottom = tester
        .getBottomLeft(find.byKey(const Key('provider-card-claude')))
        .dy;
    final resetsTop = tester.getTopLeft(find.text('Próximos resets')).dy;
    expect(resetsTop, greaterThan(claudeBottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout completo usa duas colunas em 1200px', (tester) async {
    await _pumpApp(tester, compact: false, size: const Size(1200, 900));

    expect(find.byKey(const Key('quota-deck-full')), findsOneWidget);
    expect(find.byKey(const Key('provider-card-opencode')), findsOneWidget);
    expect(find.byKey(const Key('provider-card-antigravity')), findsOneWidget);
    expect(find.byKey(const Key('provider-card-codex')), findsOneWidget);
    expect(find.byKey(const Key('provider-card-claude')), findsOneWidget);
    expect(
      find.text('fonte: sessão do Claude Desktop (ao vivo)'),
      findsNothing,
    );
    expect(find.text('Próximos resets'), findsOneWidget);
    expect(find.text('Tendência'), findsOneWidget);
    expect(find.text('FOLGA DA JANELA MAIS APERTADA'), findsOneWidget);
    expect(find.text('PRÓXIMO RESET'), findsOneWidget);
    expect(find.text('Melhor agora'), findsNothing);
    expect(find.text('100% local · sem telemetria'), findsNothing);

    final cardLeft = tester
        .getTopLeft(find.byKey(const Key('provider-card-opencode')))
        .dx;
    final resetsLeft = tester.getTopLeft(find.text('Próximos resets')).dx;
    expect(resetsLeft, greaterThan(cardLeft));
    expect(tester.takeException(), isNull);
  });

  testWidgets('layout compacto suporta textScale 1.5', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpApp(tester, compact: true, size: const Size(420, 900));

    expect(find.byKey(const Key('quota-deck-compact')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('janela de 320px com fonte 1.5 não estoura', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpApp(tester, compact: true, size: const Size(320, 400));

    expect(find.byKey(const Key('quota-deck-compact')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini avisa quando o dado está velho/após falha', (tester) async {
    final state = await _pumpApp(
      tester,
      compact: true,
      size: const Size(380, 500),
      failRefresh: true,
    );
    await state.refresh();
    state.setMiniMode(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mini-stale-strip')), findsOneWidget);
    expect(find.text('Tentar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header compacto mostra a idade do dado', (tester) async {
    await _pumpApp(tester, compact: true, size: const Size(420, 900));

    expect(find.byKey(const Key('header-age')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KPI empilha em 320px com fonte ampliada', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpApp(tester, compact: true, size: const Size(320, 520));

    final folgaBottom = tester.getBottomLeft(find.text('FOLGA')).dy;
    final resetTop = tester.getTopLeft(find.text('PRÓXIMO RESET')).dy;
    expect(
      resetTop,
      greaterThan(folgaBottom),
      reason: 'os KPIs devem empilhar para não truncar',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('botões do header cabem em 420', (tester) async {
    await _pumpApp(tester, compact: true, size: const Size(420, 900));

    for (final key in const [
      'header-refresh',
      'header-menu',
      'header-customize',
    ]) {
      final finder = find.byKey(Key(key));
      expect(finder, findsOneWidget);
      expect(tester.getTopLeft(finder).dx, lessThan(420));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('modo mini lista as janelas e abre o dashboard', (tester) async {
    final state = await _pumpApp(
      tester,
      compact: true,
      size: const Size(380, 500),
    );

    state.setMiniMode(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quota-deck-mini')), findsOneWidget);
    expect(find.byKey(const Key('mini-open-dashboard')), findsOneWidget);
    expect(find.text('5 horas'), findsWidgets);
    expect(find.text('Semanal (7d)'), findsWidgets);
    expect(find.text('DISPONÍVEL'), findsNothing);
    expect(find.textContaining('v0.5'), findsNothing);
    expect(find.byKey(const Key('provider-card-opencode')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('estados extremos renderizam todos os cards', (tester) async {
    await _pumpApp(
      tester,
      compact: false,
      size: const Size(1200, 1600),
      scenario: FakeScenario.edgeCases,
    );

    expect(find.byKey(const Key('provider-card-claude')), findsWidgets);
    expect(find.byKey(const Key('provider-card-opencode')), findsWidgets);
    expect(find.text('Credencial ausente'), findsWidgets);
    expect(find.text('Não instalado'), findsWidgets);
    expect(find.textContaining('Créditos'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding mostra comandos quando não há provedores', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      compact: false,
      size: const Size(1200, 900),
      empty: true,
    );

    expect(find.byKey(const Key('onboarding-card')), findsOneWidget);
    expect(find.text('Nenhum provedor detectado'), findsOneWidget);
    expect(find.text('opencode'), findsOneWidget);
    expect(find.text('codex'), findsOneWidget);
    expect(find.textContaining('sessão do app'), findsOneWidget);
    expect(find.text('Verificar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings abre a bottom sheet pelo header', (tester) async {
    await _pumpApp(tester, compact: true, size: const Size(420, 900));

    await openHeaderMenu(tester);
    await tester.tap(find.byKey(const Key('header-settings')));
    await tester.pumpAndSettle();

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.byKey(const Key('settings-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primeira execução com tudo conectado abre o resumo', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      compact: true,
      size: const Size(420, 900),
      onboarded: false,
    );

    expect(find.byKey(const Key('provider-wizard')), findsOneWidget);
    expect(find.text('Configurar provedores'), findsOneWidget);
    expect(find.text('Tudo pronto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('erro de carga não abre o assistente por cima do erro', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      compact: true,
      size: const Size(420, 900),
      onboarded: false,
      scenario: FakeScenario.error,
    );

    expect(find.byKey(const Key('provider-wizard')), findsNothing);
    expect(
      find.textContaining('Falha simulada ao carregar o resumo'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fechar o assistente marca o onboarding como concluído', (
    tester,
  ) async {
    final state = await _pumpApp(
      tester,
      compact: true,
      size: const Size(420, 900),
      onboarded: false,
    );

    expect(find.byKey(const Key('provider-wizard')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wizard-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('provider-wizard')), findsNothing);
    expect(state.config.onboardingCompleted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primeira execução sem nada instalado cai no resumo', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      compact: true,
      size: const Size(420, 900),
      empty: true,
      onboarded: false,
      installed: const {},
    );

    expect(find.byKey(const Key('provider-wizard')), findsOneWidget);
    expect(find.text('Nenhuma ferramenta detectada'), findsOneWidget);
    expect(find.byKey(const Key('wizard-redetect')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistente lista só provedores detectados', (tester) async {
    await _pumpApp(
      tester,
      compact: true,
      size: const Size(420, 900),
      onboarded: false,
      installed: {ProviderId.opencode, ProviderId.claude},
      scenario: FakeScenario.edgeCases,
    );

    expect(find.byKey(const Key('provider-wizard')), findsOneWidget);
    final wizard = find.byKey(const Key('provider-wizard'));
    expect(
      find.descendant(of: wizard, matching: find.text('OpenCode')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: wizard, matching: find.text('Claude')),
      findsNothing,
    );
    expect(
      find.descendant(of: wizard, matching: find.text('Antigravity')),
      findsNothing,
    );

    // opencode -> claude -> resumo
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: wizard, matching: find.text('Claude')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wizard-show-all')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistente percorre provedores e desativa um do painel', (
    tester,
  ) async {
    await _pumpApp(tester, compact: false, size: const Size(1200, 900));

    await openHeaderMenu(tester);
    await tester.tap(find.byKey(const Key('header-wizard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('provider-wizard')), findsOneWidget);

    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wizard-toggle-codex')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wizard-toggle-codex')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('provider-card-codex')), findsNothing);
    expect(find.byKey(const Key('provider-card-opencode')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resets com o mesmo rótulo mostram o grupo', (tester) async {
    await _pumpApp(
      tester,
      compact: false,
      size: const Size(1200, 900),
      scenario: FakeScenario.edgeCases,
    );

    expect(
      find.textContaining('GEMINI MODELS'),
      findsWidgets,
      reason: 'grupo precisa aparecer para desambiguar "5 horas"',
    );
    expect(tester.takeException(), isNull);
  });
}
