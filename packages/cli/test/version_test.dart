import 'dart:io';

import 'package:quota_deck_cli/quota_deck_cli.dart';
import 'package:test/test.dart';

/// Impede que `qdeck version` volte a mentir: a versão publicada no pubspec e
/// a constante usada pelo CLI precisam ser a mesma.
void main() {
  test('cliVersion bate com o pubspec', () {
    final pubspec = File('pubspec.yaml');
    expect(
      pubspec.existsSync(),
      isTrue,
      reason: 'rode o teste a partir de packages/cli',
    );

    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec.readAsStringSync());

    expect(match, isNotNull, reason: 'pubspec sem version legível');
    expect(cliVersion, match!.group(1));
  });
}
