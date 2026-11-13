import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/theme.dart';

double _luminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('ação do snackbar tem contraste AA nos dois temas', () {
    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      final snack = theme.snackBarTheme;
      final action = snack.actionTextColor;
      final background = snack.backgroundColor ?? theme.colorScheme.surface;
      expect(action, isNotNull, reason: 'actionTextColor não definido');
      expect(
        _contrast(action!, background),
        greaterThanOrEqualTo(4.5),
        reason: 'ação do snackbar ilegível (AA)',
      );
    }
  });

  test('painéis do tema claro são opacos', () {
    expect(QdPalette.light.panel.a, 1.0);
    expect(QdPalette.light.panel2.a, 1.0);
  });
}
