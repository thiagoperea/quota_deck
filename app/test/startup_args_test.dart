import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/desktop/startup_args.dart';

void main() {
  test('reconhece --startup nos argumentos do entrypoint', () {
    expect(launchedAtStartup(const ['--startup']), isTrue);
  });
}
