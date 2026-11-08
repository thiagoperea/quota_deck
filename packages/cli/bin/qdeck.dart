import 'dart:io';

import 'package:quota_deck_cli/quota_deck_cli.dart';

Future<void> main(List<String> arguments) async {
  final cli = QdeckCli(
    out: stdout,
    err: stderr,
    env: Platform.environment,
    stdoutHasTerminal: stdout.hasTerminal,
  );
  exitCode = await cli.run(arguments);
}
