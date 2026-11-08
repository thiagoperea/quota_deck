import 'dart:convert';
import 'dart:io';

import 'package:quota_deck_models/quota_deck_models.dart';

class CacheEntry {
  final ProviderSnapshot snapshot;
  final DateTime cachedAt;

  const CacheEntry({required this.snapshot, required this.cachedAt});
}

class SnapshotCache {
  final File? file;
  final Duration ttl;
  final Map<ProviderId, CacheEntry> _entries = {};

  SnapshotCache({this.file, this.ttl = const Duration(seconds: 60)});

  Future<void> load() async {
    final f = file;
    if (f == null || !await f.exists()) return;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map<String, dynamic>) return;
      final entries = raw['entries'];
      if (entries is! Map) return;
      for (final entry in entries.entries) {
        final id = ProviderId.tryParse(entry.key.toString());
        if (id == null || entry.value is! Map) continue;
        final item = entry.value as Map;
        final snapshot = item['snapshot'];
        final cachedAt = parseDate(item['cachedAt']);
        if (snapshot is Map<String, dynamic> && cachedAt != null) {
          _entries[id] = CacheEntry(
            snapshot: ProviderSnapshot.fromJson(snapshot),
            cachedAt: cachedAt,
          );
        }
      }
    } catch (_) {
      // cache corrompido é descartável
    }
  }

  ProviderSnapshot? get(ProviderId id, {Duration? maxAge}) {
    final entry = _entries[id];
    if (entry == null) return null;
    final age = DateTime.now().toUtc().difference(entry.cachedAt);
    final limit = maxAge ?? ttl;
    if (age > limit) return null;
    return entry.snapshot;
  }

  ProviderSnapshot? getStale(
    ProviderId id, {
    Duration maxAge = const Duration(hours: 24),
  }) {
    final entry = _entries[id];
    if (entry == null) return null;
    final age = DateTime.now().toUtc().difference(entry.cachedAt);
    if (age > maxAge) return null;
    return entry.snapshot.copyWith(stale: true);
  }

  void put(ProviderSnapshot snapshot) {
    _entries[snapshot.provider] = CacheEntry(
      snapshot: snapshot.copyWith(stale: false),
      cachedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> save() async {
    final f = file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final payload = {
        'schemaVersion': 1,
        'entries': {
          for (final entry in _entries.entries)
            entry.key.wireName: {
              'cachedAt': formatDate(entry.value.cachedAt),
              'snapshot': entry.value.snapshot.toJson(),
            },
        },
      };
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      if (await f.exists()) await f.delete();
      await tmp.rename(f.path);
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['600', f.path]);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> clear() async {
    _entries.clear();
    final f = file;
    if (f != null && await f.exists()) {
      await f.delete();
    }
  }
}
