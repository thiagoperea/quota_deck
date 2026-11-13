import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/version.dart';

/// A versão do rodapé/ApiMeta não pode divergir do pubspec: é ela que o
/// updater compara com a tag do GitHub, e uma divergência faz o banner de
/// atualização aparecer para sempre.
void main() {
  test('appVersion bate com o pubspec', () {
    final pubspec = File('pubspec.yaml');
    expect(
      pubspec.existsSync(),
      isTrue,
      reason: 'rode o teste a partir de app/',
    );

    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());

    expect(match, isNotNull, reason: 'pubspec sem version legível');
    expect(appVersion, match!.group(1));
  });
}
