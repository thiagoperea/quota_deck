import 'dart:convert';

import 'package:quota_deck_core/quota_deck_core.dart';

Future<void> main(List<String> args) async {
  final service = await DefaultQuotaService.create(enableHistory: false);
  try {
    final envelope = await service.snapshot(noCache: true);
    print(const JsonEncoder.withIndent('  ').convert(envelope.toJson()));
  } finally {
    await service.dispose();
  }
}
