import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressão do crash "clique na bandeja derruba o app".
///
/// Com Impeller no macOS 27 + Flutter 3.47.9, o resize programático da janela
/// (abrir o mini pela bandeja) faz o raster thread receber um render target com
/// tamanho divergente do drawable. O engine imprime
/// "The texture and its descriptor disagree about its size" e o processo morre
/// com SIGSEGV em `impeller::Canvas::SetupRenderPass`.
///
/// O opt-out fica no Info.plist do runner — código Swift/plist não é coberto
/// por teste de widget, então a garantia fica aqui.
void main() {
  test('runner macOS desliga Impeller (crash ao abrir o mini)', () {
    final file = File('macos/Runner/Info.plist');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'rode o teste a partir de app/ (make test-app / flutter test)',
    );

    final source = file.readAsStringSync();
    final match = RegExp(r'<key>FLTEnableImpeller</key>\s*<(true|false)\s*/>')
        .firstMatch(source);

    expect(match, isNotNull, reason: 'chave FLTEnableImpeller ausente');
    expect(
      match!.group(1),
      'false',
      reason:
          'ligar o Impeller de volta só depois de atualizar o Flutter: no '
          '3.47.9 o resize da janela na bandeja derruba o app no raster thread',
    );
  });
}
