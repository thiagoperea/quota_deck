import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

import 'support/sample.dart';

void main() {
  test('appends samples and computes burn rate/eta', () {
    final store = HistoryStore.inMemory();
    final now = DateTime.now().toUtc();
    final snapshots = [
      sampleSnapshot(
        used: 10,
        fetchedAt: now.subtract(const Duration(minutes: 10)),
      ),
      sampleSnapshot(
        used: 20,
        fetchedAt: now.subtract(const Duration(minutes: 5)),
      ),
      sampleSnapshot(used: 30, fetchedAt: now),
    ];
    for (final s in snapshots) {
      store.appendSnapshot(s, minInterval: Duration.zero, minDelta: 0);
    }

    final samples = store.samples(
      ProviderId.opencode,
      'rolling',
      window: const Duration(hours: 1),
    );
    expect(samples, hasLength(3));

    final summary = store.summary(
      ProviderId.opencode,
      'rolling',
      window: const Duration(hours: 1),
    );
    expect(summary.burnRatePerHour, greaterThan(0));
    expect(summary.etaHours, isNotNull);
    expect(summary.etaHours!, greaterThan(0));
    store.close();
  });

  test('burn rate ignores insufficient samples', () {
    final store = HistoryStore.inMemory();
    expect(HistoryStore.burnRatePerHour([]), 0);
    store.close();
  });
}
