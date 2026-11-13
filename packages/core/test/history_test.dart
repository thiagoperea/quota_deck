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

  test('burn rate ignora amostras da janela anterior ao reset', () {
    final now = DateTime.utc(2026, 11, 8, 12);
    HistorySample sample(double used, int minutesAgo) => HistorySample(
      provider: ProviderId.opencode,
      windowId: 'rolling',
      usedPercent: used,
      fetchedAt: now.subtract(Duration(minutes: minutesAgo)),
    );

    // Subiu até 90 e resetou; depois disso subiu 2 pontos em 60 min.
    final samples = [
      sample(60, 240),
      sample(80, 180),
      sample(90, 120),
      sample(2, 60),
      sample(4, 30),
      sample(6, 0),
    ];

    final burn = HistoryStore.burnRatePerHour(samples);
    // 4 pontos em 1 h = ~4 %/h (antes a regressão daria ~0 por causa da queda).
    expect(burn, closeTo(4, 0.5));
    expect(HistoryStore.currentWindow(samples), hasLength(3));
  });

  test('burn rate ignores insufficient samples', () {
    final store = HistoryStore.inMemory();
    expect(HistoryStore.burnRatePerHour([]), 0);
    store.close();
  });
}
