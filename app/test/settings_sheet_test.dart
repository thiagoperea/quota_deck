import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck/src/api/mock_api.dart';
import 'package:quota_deck/src/state/app_state.dart';
import 'package:quota_deck/src/theme.dart';
import 'package:quota_deck/src/widgets/settings_sheet.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

Future<AppState> _state({bool failSettings = false}) async {
  final state = AppState(
    MockApi(
      failSettings: failSettings,
      config: AppConfig.defaults().copyWith(theme: 'dark', refreshSeconds: 0),
    ),
  );
  await state.initialize();
  return state;
}

Future<void> _pumpSheet(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                key: const Key('open-settings'),
                onPressed: () => showSettingsSheet(context),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-settings')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('SettingsSheet alterna provedor, refresh e salva', (
    tester,
  ) async {
    final state = await _state();
    await _pumpSheet(tester, state);

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('OpenCode'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-provider-opencode')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('settings-refresh-120')));
    await tester.tap(find.byKey(const Key('settings-refresh-120')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('settings-theme-light')));
    await tester.tap(find.byKey(const Key('settings-theme-light')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(find.text('Descartar alterações?'), findsNothing);
    expect(find.byKey(const Key('settings-save')), findsNothing);
    expect(state.config.refreshSeconds, 120);
    expect(state.config.theme, 'light');
    expect(state.config.isEnabled(ProviderId.opencode), isFalse);
    expect(state.error, isNull);

    // Evita timer periódico pendente no fim do teste.
    state.dispose();
  });

  testWidgets('SettingsSheet descarta mudanças ao fechar', (tester) async {
    final state = await _state();
    await _pumpSheet(tester, state);

    await tester.tap(find.byKey(const Key('settings-provider-opencode')));
    await tester.pump();
    expect(state.config.isEnabled(ProviderId.opencode), isTrue);

    await tester.tap(find.byKey(const Key('settings-close')));
    await tester.pumpAndSettle();
    expect(find.text('Descartar alterações?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-discard')));
    await tester.pumpAndSettle();

    expect(state.config.isEnabled(ProviderId.opencode), isTrue);
    state.dispose();
  });

  testWidgets('SettingsSheet mostra erro ao falhar o salvamento', (
    tester,
  ) async {
    final state = await _state(failSettings: true);
    await _pumpSheet(tester, state);

    await tester.tap(find.byKey(const Key('settings-provider-opencode')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Falha simulada ao salvar'), findsOneWidget);
    expect(find.byKey(const Key('settings-save')), findsOneWidget);

    state.dispose();
  });
}
