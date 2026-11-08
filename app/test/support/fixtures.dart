import 'package:quota_deck_models/quota_deck_models.dart';

QuotaWindow testWindow({
  String id = 'weekly',
  String label = 'Semanal (7d)',
  WindowKind kind = WindowKind.weekly,
  String? group,
  double used = 21,
  DateTime? resetsAt,
  QuotaStatus? status,
  SourceKind source = SourceKind.api,
}) {
  final usedPercent = clampPercent(used);
  return QuotaWindow(
    id: id,
    label: label,
    kind: kind,
    group: group,
    usedPercent: usedPercent,
    remainingPercent: clampPercent(100 - usedPercent),
    resetsAt: resetsAt ?? DateTime.now().toUtc().add(const Duration(hours: 5)),
    status: status ?? statusForUsed(usedPercent),
    source: source,
  );
}

ProviderSnapshot testSnapshot({
  ProviderId provider = ProviderId.opencode,
  String? plan = 'Go',
  List<QuotaWindow>? windows,
  List<QdeckErrorInfo> errors = const [],
  CreditsInfo? credits,
  String source = 'test-source',
  DateTime? fetchedAt,
  bool stale = false,
  Confidence confidence = Confidence.high,
}) {
  return ProviderSnapshot(
    provider: provider,
    account: AccountInfo(
      label: provider.displayName,
      plan: plan,
      maskedEmail: 'us***@example.com',
    ),
    windows:
        windows ??
        [
          testWindow(id: 'rolling-5h', label: 'Rolling 5h', used: 4),
          testWindow(id: 'weekly', label: 'Semanal (7d)', used: 21),
        ],
    credits: credits,
    source: source,
    fetchedAt: fetchedAt ?? DateTime.now().toUtc(),
    stale: stale,
    confidence: confidence,
    errors: errors,
  );
}
