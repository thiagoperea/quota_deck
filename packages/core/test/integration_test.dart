import 'dart:io';

import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

void main() {
  final enabled = Platform.environment['QDECK_INTEGRATION'] == '1';

  test(
    'real snapshot from local credentials',
    () async {
      final service = await DefaultQuotaService.create(enableHistory: false);
      try {
        final envelope = await service.snapshot(noCache: true);
        expect(envelope.results, hasLength(4));

        final opencode = envelope.byProvider(ProviderId.opencode);
        expect(opencode, isNotNull);
        expect(opencode!.windows, isNotEmpty);

        final antigravity = envelope.byProvider(ProviderId.antigravity);
        expect(antigravity, isNotNull);

        final codex = envelope.byProvider(ProviderId.codex);
        expect(codex, isNotNull);

        final claude = envelope.byProvider(ProviderId.claude);
        expect(claude, isNotNull);
      } finally {
        await service.dispose();
      }
    },
    skip: enabled
        ? false
        : 'defina QDECK_INTEGRATION=1 para rodar com credenciais reais',
  );
}
