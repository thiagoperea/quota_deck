import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/theme.dart';
import 'package:quota_deck/src/widgets/provider_card.dart';
import 'package:quota_deck/src/widgets/quota_bar.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import 'support/fixtures.dart';

Future<void> _pumpCard(
  WidgetTester tester,
  ProviderSnapshot snapshot, {
  VoidCallback? onAuthAction,
  List<QuotaWindow>? windows,
  List<QuotaWindow> onDemandWindows = const [],
  bool forceStale = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 380,
            child: ProviderCard(
              snapshot: snapshot,
              onRetry: () {},
              onAuthAction: onAuthAction,
              windows: windows,
              onDemandWindows: onDemandWindows,
              forceStale: forceStale,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('ProviderCard renderiza nome, plano, janelas e barras', (
    tester,
  ) async {
    final snapshot = testSnapshot(
      windows: [
        testWindow(id: 'rolling-5h', label: 'Rolling 5h', used: 4),
        testWindow(id: 'weekly', label: 'Semanal (7d)', used: 21),
      ],
    );
    await _pumpCard(tester, snapshot);

    expect(find.text('OpenCode'), findsOneWidget);
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Rolling 5h'), findsOneWidget);
    expect(find.text('Semanal (7d)'), findsOneWidget);
    expect(find.text('21%'), findsOneWidget);
    expect(find.byType(QuotaBar), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProviderCard agrupa janelas do Antigravity', (tester) async {
    final snapshot = testSnapshot(
      provider: ProviderId.antigravity,
      plan: 'Pro',
      windows: [
        testWindow(
          id: 'gemini-5h',
          label: '5 horas',
          group: 'Gemini Models',
          used: 12,
        ),
        testWindow(
          id: 'gemini-weekly',
          label: 'Semanal (7d)',
          group: 'Gemini Models',
          used: 4,
        ),
        testWindow(
          id: '3p-weekly',
          label: 'Semanal (7d)',
          group: 'Claude and GPT models',
          used: 0,
        ),
      ],
    );
    await _pumpCard(tester, snapshot);

    expect(find.text('GEMINI MODELS'), findsOneWidget);
    expect(find.text('CLAUDE AND GPT MODELS'), findsOneWidget);
    expect(find.byType(QuotaBar), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProviderCard mostra painel de auth e botão do Claude', (
    tester,
  ) async {
    var tapped = false;
    final snapshot = testSnapshot(
      provider: ProviderId.claude,
      plan: 'pro',
      windows: const [],
      stale: true,
      confidence: Confidence.low,
      errors: const [
        QdeckErrorInfo(
          code: 'AUTH_EXPIRED',
          message: 'Token do Claude Code expirado.',
          retryable: false,
        ),
      ],
    );
    await _pumpCard(tester, snapshot, onAuthAction: () => tapped = true);

    expect(find.text('Sessão expirada'), findsOneWidget);
    expect(find.text('Como renovar'), findsOneWidget);
    expect(find.byKey(const Key('auth-panel-claude')), findsOneWidget);
    expect(find.text('desatualizado'), findsOneWidget);

    await tester.tap(find.text('Como renovar'));
    await tester.pump();
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProviderCard mostra "não instalado" com CTA do assistente', (
    tester,
  ) async {
    var wizard = false;
    final snapshot = testSnapshot(
      provider: ProviderId.codex,
      windows: const [],
      errors: const [
        QdeckErrorInfo(
          code: 'NOT_INSTALLED',
          message: 'Codex não encontrado nesta máquina.',
          retryable: false,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 380,
              child: ProviderCard(
                snapshot: snapshot,
                onOpenWizard: () => wizard = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Não instalado'), findsOneWidget);
    expect(find.text('Abrir assistente'), findsOneWidget);
    await tester.tap(find.text('Abrir assistente'));
    expect(wizard, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProviderCard mostra erro comum sem quebrar', (tester) async {
    final snapshot = testSnapshot(
      provider: ProviderId.codex,
      windows: const [],
      errors: const [
        QdeckErrorInfo(
          code: 'NETWORK',
          message: 'Falha de rede ao consultar o Codex.',
          retryable: true,
        ),
      ],
    );
    await _pumpCard(tester, snapshot);

    expect(find.text('Falha ao consultar'), findsOneWidget);
    expect(
      find.textContaining('Falha de rede ao consultar o Codex.'),
      findsOneWidget,
    );
    expect(find.byType(QuotaBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProviderCard mostra janelas sob demanda atrás do botão', (
    tester,
  ) async {
    final always = testWindow(id: 'rolling-5h', label: '5 horas', used: 4);
    final onDemand = testWindow(id: 'weekly', label: 'Semanal (7d)', used: 21);
    final snapshot = testSnapshot(windows: [always, onDemand]);
    await _pumpCard(
      tester,
      snapshot,
      windows: [always],
      onDemandWindows: [onDemand],
    );

    expect(find.text('5 horas'), findsOneWidget);
    expect(find.text('Semanal (7d)'), findsNothing);
    expect(find.text('Mostrar mais (1)'), findsOneWidget);

    await tester.tap(find.text('Mostrar mais (1)'));
    await tester.pump();

    expect(find.text('Semanal (7d)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProviderCard avisa quando todas as janelas estão ocultas', (
    tester,
  ) async {
    final snapshot = testSnapshot(
      windows: [testWindow(id: 'rolling-5h', label: '5 horas', used: 4)],
    );
    await _pumpCard(tester, snapshot, windows: const []);

    expect(
      find.textContaining('Todas as janelas estão ocultas'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('falha de atualização marca o card como desatualizado', (
    tester,
  ) async {
    final snapshot = testSnapshot(
      windows: [testWindow(id: 'rolling-5h', label: 'Rolling 5h', used: 4)],
    );
    await _pumpCard(tester, snapshot, forceStale: true);

    expect(find.text('desatualizado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
