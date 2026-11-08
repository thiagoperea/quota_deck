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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = AppState(
    MockApi(
      empty: empty,
      config: AppConfig.defaults().copyWith(theme: 'dark', refreshSeconds: 0),
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
}
