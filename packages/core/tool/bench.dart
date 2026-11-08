import 'dart:io';

import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

Future<void> main() async {
  final service = await DefaultQuotaService.create(enableHistory: false);
  try {
    for (final id in ProviderId.values) {
      final sw = Stopwatch()..start();
      final envelope = await service.snapshot(providers: {id}, noCache: true);
      sw.stop();
      final result = envelope.results.first;
      stdout.writeln(
        '${id.name.padRight(12)} ${sw.elapsedMilliseconds.toString().padLeft(5)} ms  '
        'windows=${result.windows.length}  errors=${result.errors.length}  '
        'source=${result.source}',
      );
    }
  } finally {
    await service.dispose();
  }
}
