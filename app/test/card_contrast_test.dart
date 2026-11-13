import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/theme.dart';
import 'package:quota_deck/src/widgets/provider_card.dart';

import 'support/fixtures.dart';

/// Regressão do "card cinza no tema claro": gradiente com alfa baixo virava um
/// véu cinza no Impeller e o texto secundário ficava em ~2,7:1 de contraste.
void main() {
  testWidgets('card do provedor é claro e opaco no tema claro', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          backgroundColor: const Color(0xFFE9EEF5),
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 380,
                child: ProviderCard(
                  snapshot: testSnapshot(
                    windows: [
                      testWindow(
                        id: 'rolling-5h',
                        label: 'Rolling 5h',
                        used: 4,
                      ),
                    ],
                  ),
                  onRetry: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    var r = 0, g = 0, b = 0, alpha = 0;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(bytes, isNotNull);

      // Canto inferior esquerdo: dentro do padding, longe de texto e barras.
      final x = 7;
      final y = image.height - 7;
      final offset = (y * image.width + x) * 4;
      r = bytes!.getUint8(offset);
      g = bytes.getUint8(offset + 1);
      b = bytes.getUint8(offset + 2);
      alpha = bytes.getUint8(offset + 3);
    });

    final luma = (0.2126 * r + 0.7152 * g + 0.0722 * b);
    expect(alpha, 255, reason: 'fundo do card precisa ser opaco');
    expect(
      luma,
      greaterThan(245),
      reason:
          'card lavado (rgb $r,$g,$b): volte para cor sólida/opaca, sem '
          'gradiente de alfa baixo',
    );
  });
}
