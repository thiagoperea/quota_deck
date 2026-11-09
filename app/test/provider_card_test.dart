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
    expect(find.text('Abrir Claude Code'), findsOneWidget);
    expect(find.byKey(const Key('auth-panel-claude')), findsOneWidget);
    expect(find.text('cache'), findsOneWidget);

    await tester.tap(find.text('Abrir Claude Code'));
    await tester.pump();
    expect(tapped, isTrue);
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
}
