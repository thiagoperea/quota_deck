import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/theme.dart';
import 'package:quota_deck/src/widgets/quota_bar.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required double used,
  QuotaStatus? status,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            child: QuotaBar(usedPercent: used, status: status),
          ),
        ),
      ),
    ),
  );
}

Color _fillColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const Key('quota-bar-fill')),
  );
  final decoration = container.decoration! as BoxDecoration;
  return decoration.color!;
}

void main() {
  testWidgets('QuotaBar fica verde abaixo de 80%', (tester) async {
    await _pumpBar(tester, used: 42);
    expect(_fillColor(tester), QdPalette.dark.green);
  });

  testWidgets('QuotaBar fica amarela em warning', (tester) async {
    await _pumpBar(tester, used: 85);
    expect(_fillColor(tester), QdPalette.dark.yellow);
  });

  testWidgets('QuotaBar fica vermelha em crítico', (tester) async {
    await _pumpBar(tester, used: 96);
    expect(_fillColor(tester), QdPalette.dark.red);
  });

  testWidgets('QuotaBar respeita status limited explícito', (tester) async {
    await _pumpBar(tester, used: 10, status: QuotaStatus.limited);
    expect(_fillColor(tester), QdPalette.dark.red);
  });

  testWidgets('QuotaBar limita valores acima de 100%', (tester) async {
    await _pumpBar(tester, used: 150);
    final fraction = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fraction.widthFactor, 1);
  });
}
