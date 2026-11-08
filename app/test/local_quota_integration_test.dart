import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/api/local_quota_api.dart';

void main() {
  final enabled = Platform.environment['QDECK_INTEGRATION'] == '1';

  test(
    'LocalQuotaApi lê os 4 provedores sem daemon',
    () async {
      final api = LocalQuotaApi();
      try {
        final summary = await api.fetchSummary();
        expect(summary.envelope.results, hasLength(4));
        expect(summary.meta.providers, hasLength(4));
        expect(summary.config.refreshSeconds, greaterThan(0));
      } finally {
        api.close();
      }
    },
    skip: enabled
        ? false
        : 'defina QDECK_INTEGRATION=1 para rodar com credenciais reais',
  );
}
