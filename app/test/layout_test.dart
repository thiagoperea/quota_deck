import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck/src/api/mock_api.dart';
import 'package:quota_deck/src/app.dart';
import 'package:quota_deck/src/state/app_state.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

Future<AppState> _pumpApp(
  WidgetTester tester, {
  required bool compact,
  required Size size,
  bool empty = false,
  bool onboarded = true,
  Set<ProviderId>? installed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = AppState(
    MockApi(
      empty: empty,
      installedProviders: installed,
      config: AppConfig.defaults().copyWith(
        theme: 'dark',
        refreshSeconds: 0,
        onboardingCompleted: onboarded,
      ),
    ),
  );
  addTearDown(state.dispose);
  await state.initialize();

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
  test('detecta compact por query string e rota', () {
    expect(isCompactUri(Uri.parse('http://localhost/?compact=1')), isTrue);
    expect(isCompactUri(Uri.parse('http://localhost/compact')), isTrue);
    expect(isCompactUri(Uri.parse('http://localhost/')), isFalse);
  });

  testWidgets('layout compacto empilha cards em ~420px', (tester) async {
    await _pumpApp(tester, compact: true, size: const Size(420, 900));

    expect(find.byKey(const Key('quota-deck-compact')), findsOneWidget);
    expect(find.byKey(const Key('header-refresh')), findsOneWidget);
    expect(find.byKey(const Key('header-settings')), findsOneWidget);
    expect(find.byKey(const Key('provider-card-opencode')), findsOneWidget);
    expect(find.byKey(const Key('provider-card-claude')), findsOneWidget);
    expect(find.text('QuotaDeck'), findsOneWidget);

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
    expect(find.text('Abrir Claude Code'), findsOneWidget);
    expect(find.text('Próximos resets'), findsOneWidget);
    expect(find.text('Tendência'), findsOneWidget);
    expect(find.text('PROVEDOR MAIS USADO'), findsOneWidget);
    expect(find.text('PRÓXIMO RESET'), findsOneWidget);
    expect(find.text('USO DISPONÍVEL ESTIMADO'), findsOneWidget);
    expect(find.text('Melhor agora'), findsNothing);
    expect(find.text('100% local · sem telemetria'), findsNothing);

    final cardLeft = tester
        .getTopLeft(find.byKey(const Key('provider-card-opencode')))
        .dx;
    final resetsLeft = tester.getTopLeft(find.text('Próximos resets')).dx;
    expect(resetsLeft, greaterThan(cardLeft));
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
    expect(find.text('claude'), findsOneWidget);
    expect(find.text('Verificar novamente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings abre a bottom sheet pelo header', (tester) async {
    await _pumpApp(tester, compact: true, size: const Size(420, 900));

    await tester.tap(find.byKey(const Key('header-settings')));
    await tester.pumpAndSettle();

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.byKey(const Key('settings-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primeira execução abre o assistente de provedores', (
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
    expect(find.byKey(const Key('wizard-toggle-opencode')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistente lista só provedores detectados', (tester) async {
    await _pumpApp(
      tester,
      compact: true,
      size: const Size(420, 900),
      onboarded: false,
      installed: {ProviderId.opencode, ProviderId.codex},
    );

    expect(find.byKey(const Key('provider-wizard')), findsOneWidget);
    expect(find.text('OpenCode'), findsOneWidget);
    expect(find.text('Claude'), findsNothing);
    expect(find.text('Antigravity'), findsNothing);

    // opencode -> codex -> resumo
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();
    expect(find.text('Codex'), findsOneWidget);
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wizard-show-all')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistente percorre provedores e desativa um do painel', (
    tester,
  ) async {
    await _pumpApp(tester, compact: false, size: const Size(1200, 900));

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
}
