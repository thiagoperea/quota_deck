import 'dart:io';
import 'dart:math' as math;

import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:sqlite3/sqlite3.dart';

class HistoryStore {
  final Database db;

  HistoryStore._(this.db) {
    _init();
  }

  factory HistoryStore.open(File file) {
    file.parent.createSync(recursive: true);
    final db = sqlite3.open(file.path);
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', ['600', file.path]);
      } catch (_) {}
    }
    return HistoryStore._(db);
  }

  factory HistoryStore.inMemory() {
    final db = sqlite3.openInMemory();
    return HistoryStore._(db);
  }

  void _init() {
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA busy_timeout = 4000;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        provider TEXT NOT NULL,
        window_id TEXT NOT NULL,
        used_percent REAL NOT NULL,
        fetched_at TEXT NOT NULL,
        stale INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_snapshots_provider_time
      ON snapshots(provider, fetched_at);
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_snapshots_window_time
      ON snapshots(provider, window_id, fetched_at);
    ''');
  }

  void appendSnapshot(
    ProviderSnapshot snapshot, {
    Duration minInterval = const Duration(minutes: 5),
    double minDelta = 1.0,
  }) {
    if (snapshot.stale) return;
    db.execute('BEGIN;');
    try {
      for (final window in snapshot.windows) {
        final last = db.select(
          '''
          SELECT used_percent, fetched_at FROM snapshots
          WHERE provider = ? AND window_id = ?
          ORDER BY fetched_at DESC LIMIT 1
          ''',
          [snapshot.provider.wireName, window.id],
        );
        if (last.isNotEmpty) {
          final lastUsed = (last.first['used_percent'] as num).toDouble();
          final lastAt = DateTime.tryParse(last.first['fetched_at'].toString());
          if (lastAt != null) {
            final age = snapshot.fetchedAt.difference(lastAt).abs();
            if (age < minInterval &&
                (window.usedPercent - lastUsed).abs() < minDelta) {
              continue;
            }
          }
        }
        db.execute(
          '''
          INSERT INTO snapshots(provider, window_id, used_percent, fetched_at, stale)
          VALUES (?, ?, ?, ?, ?)
          ''',
          [
            snapshot.provider.wireName,
            window.id,
            window.usedPercent,
            formatDate(snapshot.fetchedAt),
            snapshot.stale ? 1 : 0,
          ],
        );
      }
      db.execute('COMMIT;');
    } catch (_) {
      try {
        db.execute('ROLLBACK;');
      } catch (_) {}
      rethrow;
    }
  }

  List<HistorySample> samples(
    ProviderId provider,
    String windowId, {
    Duration window = const Duration(hours: 24),
  }) {
    final since = DateTime.now().toUtc().subtract(window);
    final rows = db.select(
      '''
      SELECT provider, window_id, used_percent, fetched_at, stale
      FROM snapshots
      WHERE provider = ? AND window_id = ? AND fetched_at >= ?
      ORDER BY fetched_at ASC
      ''',
      [provider.wireName, windowId, formatDate(since)],
    );
    return rows
        .map(
          (row) => HistorySample(
            provider: provider,
            windowId: row['window_id'].toString(),
            usedPercent: (row['used_percent'] as num).toDouble(),
            fetchedAt: DateTime.parse(row['fetched_at'].toString()).toUtc(),
            stale: (row['stale'] as int) == 1,
          ),
        )
        .toList(growable: false);
  }

  HistorySummary summary(
    ProviderId provider,
    String windowId, {
    Duration window = const Duration(hours: 6),
  }) {
    final samples = this.samples(provider, windowId, window: window);
    final burn = burnRatePerHour(samples);
    final lastUsed = samples.isEmpty ? 0.0 : samples.last.usedPercent;
    final eta = burn <= 0.01 ? null : (100.0 - lastUsed) / burn;
    return HistorySummary(
      provider: provider,
      windowId: windowId,
      samples: samples,
      burnRatePerHour: burn,
      etaHours: eta != null && eta.isFinite && eta >= 0 ? eta : null,
    );
  }

  void prune({int retentionDays = 30}) {
    final cutoff = DateTime.now().toUtc().subtract(
      Duration(days: retentionDays),
    );
    db.execute('DELETE FROM snapshots WHERE fetched_at < ?', [
      formatDate(cutoff),
    ]);
  }

  void close() {
    db.close();
  }

  static double burnRatePerHour(List<HistorySample> samples) {
    if (samples.length < 3) return 0;
    final pts = samples
        .where((s) => !s.stale)
        .map(
          (s) => (
            x: s.fetchedAt.millisecondsSinceEpoch / 3600000.0,
            y: s.usedPercent,
          ),
        )
        .toList(growable: false);
    if (pts.length < 3) return 0;

    final n = pts.length.toDouble();
    final sx = pts.fold<double>(0, (a, p) => a + p.x);
    final sy = pts.fold<double>(0, (a, p) => a + p.y);
    final sxx = pts.fold<double>(0, (a, p) => a + p.x * p.x);
    final sxy = pts.fold<double>(0, (a, p) => a + p.x * p.y);
    final denom = n * sxx - sx * sx;
    if (denom.abs() < 1e-9) return 0;
    final slope = (n * sxy - sx * sy) / denom;
    if (slope.isNaN || slope.isInfinite) return 0;
    return math.max(0.0, slope).toDouble();
  }
}
