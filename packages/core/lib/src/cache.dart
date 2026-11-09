import 'dart:convert';
import 'dart:io';

import 'package:quota_deck_models/quota_deck_models.dart';

class CacheEntry {
  final ProviderSnapshot snapshot;
  final DateTime cachedAt;

  const CacheEntry({required this.snapshot, required this.cachedAt});
}

/// Cache em disco com uma entrada por (provider, superfície, fonte).
///
/// Preserva `stale`/`fetchedAt` do snapshot original: dado de histórico não
/// pode ser promovido a "fresco" só por ter passado pelo cache.
class SnapshotCache {
  final File? file;
  final Duration ttl;
  final Map<String, CacheEntry> _entries = {};
  bool _dirty = false;

  SnapshotCache({this.file, this.ttl = const Duration(seconds: 60)});

  File get _backup => File('${file!.path}.bak');

  static String keyOf(ProviderSnapshot snapshot) =>
      '${snapshot.provider.wireName}|'
      '${snapshot.surface?.wireName ?? ''}|'
      '${snapshot.sourceId ?? ''}';

  Future<void> load() async {
    final f = file;
    if (f == null) return;
    for (final candidate in [f, _backup]) {
      if (!await candidate.exists()) continue;
      if (_loadFile(candidate)) return;
    }
  }

  bool _loadFile(File f) {
    try {
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map<String, dynamic>) return false;
      final entries = raw['entries'];
      if (entries is! Map) return false;
      _entries.clear();
      for (final entry in entries.entries) {
        final item = entry.value;
        if (item is! Map) continue;
        final snapshot = item['snapshot'];
        final cachedAt = parseDate(item['cachedAt']);
        if (snapshot is! Map<String, dynamic> || cachedAt == null) continue;
        final decoded = ProviderSnapshot.fromJson(snapshot);
        // Compatibilidade com cache antigo, chaveado só por provider.
        final key = entry.key.toString().contains('|')
            ? entry.key.toString()
            : keyOf(decoded);
        _entries[key] = CacheEntry(snapshot: decoded, cachedAt: cachedAt);
      }
      _dirty = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  CacheEntry? _pick(
    ProviderId id, {
    ProviderSurface? surface,
    String? sourceId,
  }) {
    if (surface != null && sourceId != null) {
      final exact = _entries['${id.wireName}|${surface.wireName}|$sourceId'];
      if (exact != null) return exact;
    }
    if (surface != null) {
      final bySurface = _entries['${id.wireName}|${surface.wireName}|'];
      if (bySurface != null) return bySurface;
    }
    CacheEntry? newest;
    for (final entry in _entries.entries) {
      if (!entry.key.startsWith('${id.wireName}|')) continue;
      if (newest == null || entry.value.cachedAt.isAfter(newest.cachedAt)) {
        newest = entry.value;
      }
    }
    return newest;
  }

  ProviderSnapshot? get(
    ProviderId id, {
    Duration? maxAge,
    ProviderSurface? surface,
    String? sourceId,
  }) {
    final entry = _pick(id, surface: surface, sourceId: sourceId);
    if (entry == null) return null;
    final age = DateTime.now().toUtc().difference(entry.cachedAt);
    if (age > (maxAge ?? ttl)) return null;
    return entry.snapshot;
  }

  ProviderSnapshot? getStale(
    ProviderId id, {
    Duration maxAge = const Duration(hours: 24),
    ProviderSurface? surface,
    String? sourceId,
  }) {
    final entry = _pick(id, surface: surface, sourceId: sourceId);
    if (entry == null) return null;
    final age = DateTime.now().toUtc().difference(entry.cachedAt);
    if (age > maxAge) return null;
    return entry.snapshot.stale
        ? entry.snapshot
        : entry.snapshot.copyWith(stale: true);
  }

  void put(ProviderSnapshot snapshot) {
    _entries[keyOf(snapshot)] = CacheEntry(
      snapshot: snapshot,
      cachedAt: DateTime.now().toUtc(),
    );
    _trim(snapshot.provider);
    _dirty = true;
  }

  /// Mantém no máximo 4 entradas por provedor (2 superfícies × fontes comuns).
  void _trim(ProviderId id) {
    final keys =
        _entries.entries
            .where((entry) => entry.key.startsWith('${id.wireName}|'))
            .toList(growable: false)
          ..sort((a, b) => b.value.cachedAt.compareTo(a.value.cachedAt));
    for (final stale in keys.skip(4)) {
      _entries.remove(stale.key);
    }
  }

  Future<void> save() async {
    final f = file;
    if (f == null || !_dirty) return;
    try {
      await f.parent.create(recursive: true);
      final payload = {
        'schemaVersion': 2,
        'entries': {
          for (final entry in _entries.entries)
            entry.key: {
              'cachedAt': formatDate(entry.value.cachedAt),
              'snapshot': entry.value.snapshot.toJson(),
            },
        },
      };
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(payload), flush: true);
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['600', tmp.path]);
        } catch (_) {}
      }
      if (await f.exists()) {
        try {
          if (await _backup.exists()) await _backup.delete();
          await f.copy(_backup.path);
        } catch (_) {}
        await f.delete();
      }
      await tmp.rename(f.path);
      _dirty = false;
    } catch (_) {
      // Cache é descartável: falha não deve derrubar o painel.
    }
  }

  Future<void> clear() async {
    _entries.clear();
    _dirty = true;
    final f = file;
    if (f != null && await f.exists()) {
      try {
        await f.delete();
      } catch (_) {}
    }
    if (f != null && await _backup.exists()) {
      try {
        await _backup.delete();
      } catch (_) {}
    }
  }
}
