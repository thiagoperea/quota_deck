import 'package:quota_deck_models/quota_deck_models.dart';

ProviderSnapshot sampleSnapshot({
  ProviderId provider = ProviderId.opencode,
  double used = 10,
  DateTime? fetchedAt,
  bool stale = false,
}) {
  return ProviderSnapshot(
    provider: provider,
    account: AccountInfo(label: provider.displayName),
    windows: [
      QuotaWindow(
        id: 'rolling',
        label: 'Rolling 5h',
        kind: WindowKind.rolling,
        usedPercent: used,
        remainingPercent: 100 - used,
        status: statusForUsed(used),
        source: SourceKind.api,
      ),
    ],
    source: 'test',
    fetchedAt: fetchedAt ?? DateTime.now().toUtc(),
    stale: stale,
    confidence: Confidence.high,
  );
}
