import 'dart:io';

import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

import 'support/sample.dart';

void main() {
  late Directory temp;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_cache_');
    file = File('${temp.path}/cache.json');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('put/get/save/load', () async {
    final cache = SnapshotCache(file: file);
    cache.put(sampleSnapshot(used: 12));
    expect(cache.get(ProviderId.opencode)?.windows.first.usedPercent, 12);

    await cache.save();
    expect(await file.exists(), isTrue);

    final loaded = SnapshotCache(file: file);
    await loaded.load();
    expect(loaded.get(ProviderId.opencode)?.windows.first.usedPercent, 12);
  });

  test('stale fallback marks stale', () async {
    final cache = SnapshotCache(file: file);
    cache.put(sampleSnapshot(used: 42));
    final stale = cache.getStale(ProviderId.opencode);
    expect(stale, isNotNull);
    expect(stale!.stale, isTrue);
    expect(stale.windows.first.usedPercent, 42);
  });

  test('returns null for unknown provider', () {
    final cache = SnapshotCache(file: file);
    expect(cache.get(ProviderId.codex), isNull);
  });
}
