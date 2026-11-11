import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'support/fake_api.dart';
import 'package:quota_deck/src/screens/customize_page.dart';
import 'package:quota_deck/src/state/app_state.dart';
import 'package:quota_deck/src/theme.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

void main() {
  testWidgets('CustomizePage altera a visibilidade de uma janela', (
    tester,
  ) async {
    final state = AppState(
      FakeQuotaApi(config: AppConfig.defaults().copyWith(refreshSeconds: 0)),
    );
    addTearDown(state.dispose);
    await state.initialize();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: CustomizePage(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Personalizar painel'), findsOneWidget);
    expect(find.text('OpenCode'), findsOneWidget);

    final provider = state.visibleSnapshots.first;
    final windowId = provider.windows.first.id;

    await tester.tap(find.byTooltip('Editar janelas').first);
    await tester.pumpAndSettle();

    expect(find.text('GEMINI MODELS'), findsOneWidget);
    expect(find.text('CLAUDE AND GPT MODELS'), findsOneWidget);

    final selector = find.byKey(Key('window-visibility-$windowId'));
    expect(selector, findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oculta').last);
    await tester.pumpAndSettle();

    expect(
      state.config.visibilityFor(provider.provider, windowId),
      WindowVisibility.hidden,
    );
    expect(tester.takeException(), isNull);
  });
}
