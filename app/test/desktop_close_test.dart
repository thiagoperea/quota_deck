import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressão do bug "fechar para a bandeja encerra o app".
///
/// O runner do macOS era o ÚNICO lugar que matava o processo ao fechar a
/// janela, e nenhum teste de widget via isso. Como é código Swift, a garantia
/// fica no fonte do runner.
void main() {
  test('runner macOS não encerra o app ao fechar a última janela', () {
    final file = File('macos/Runner/AppDelegate.swift');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'rode o teste a partir de app/ (make test-app / flutter test)',
    );

    final source = file.readAsStringSync();
    final match = RegExp(
      r'applicationShouldTerminateAfterLastWindowClosed[\s\S]*?return\s+(true|false)',
    ).firstMatch(source);

    expect(match, isNotNull, reason: 'override não encontrado no AppDelegate');
    expect(
      match!.group(1),
      'false',
      reason:
          'app de bandeja: fechar a janela deve esconder, não encerrar. '
          'Quem encerra é o item "Sair" da bandeja.',
    );
  });
}
