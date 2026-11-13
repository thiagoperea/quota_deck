import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/sample.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_persist_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('config: grava, cria backup e recupera de arquivo corrompido', () async {
    final file = File('${temp.path}/config.json');
    final store = ConfigStore(file);
    final config = AppConfig.defaults().copyWith(theme: 'light');
    await store.save(config);
    expect(await file.exists(), isTrue);

    await store.save(config.copyWith(refreshSeconds: 120));
    expect(await File('${file.path}.bak').exists(), isTrue);

    await file.writeAsString('{ isso nao e json');
    final reloaded = await ConfigStore(file).load();
    expect(reloaded.theme, 'light');
  });

  test('config: arquivo corrompido não destrói o backup bom', () async {
    final file = File('${temp.path}/config.json');
    final store = ConfigStore(file);
    await store.save(AppConfig.defaults().copyWith(theme: 'light'));
    await store.save(AppConfig.defaults().copyWith(theme: 'dark'));

    final backup = File('${file.path}.bak');
    final goodBackup = await backup.readAsString();
    expect(goodBackup, contains('"light"'));

    // Principal corrompido (queda de energia) e recuperação pelo backup.
    await file.writeAsString('{"schemaVersion": 1, "providers":');
    final recovered = await ConfigStore(file).load();
    expect(recovered.theme, 'light');

    // Próximo save não pode sobrescrever o backup bom com o lixo.
    await ConfigStore(file).save(recovered.copyWith(refreshSeconds: 30));
    expect(await backup.readAsString(), goodBackup);
  });

  test('cache: arquivo corrompido não destrói o backup bom', () async {
    final file = File('${temp.path}/cache.json');
    final cache = SnapshotCache(file: file);
    cache.put(sampleSnapshot(used: 10));
    await cache.save();
    cache.put(sampleSnapshot(used: 20));
    await cache.save();

    final backup = File('${file.path}.bak');
    final goodBackup = await backup.readAsString();
    await file.writeAsString('{ corrompido');

    final reloaded = SnapshotCache(file: file);
    await reloaded.load();
    expect(
      reloaded.get(ProviderId.opencode, maxAge: Duration(days: 1)),
      isNotNull,
    );

    reloaded.put(sampleSnapshot(used: 30));
    await reloaded.save();
    expect(await backup.readAsString(), goodBackup);
  });

  test('config: falha de escrita propaga e não altera memória', () async {
    final path = '${temp.path}/config.json';
    await Directory(path).create();
    final store = ConfigStore(File(path));
    expect(() => store.save(AppConfig.defaults()), throwsA(anything));
    expect(store.current.theme, AppConfig.defaults().theme);
  });

  test(
    'cache: preserva stale e indexa por provider/superfície/fonte',
    () async {
      final file = File('${temp.path}/cache.json');
      final cache = SnapshotCache(file: file);
      final desktop = sampleSnapshot(provider: ProviderId.claude, stale: true)
          .copyWith(
            surface: ProviderSurface.desktop,
            sourceId: 'claude-desktop-history',
          );
      final cli = sampleSnapshot(
        provider: ProviderId.claude,
      ).copyWith(surface: ProviderSurface.cli, sourceId: 'claude-oauth-usage');
      cache.put(desktop);
      cache.put(cli);

      expect(
        cache
            .get(
              ProviderId.claude,
              surface: ProviderSurface.desktop,
              sourceId: 'claude-desktop-history',
            )
            ?.stale,
        isTrue,
        reason: 'stale não pode ser apagado pelo cache',
      );
      await cache.save();
      cache.put(cli);
      await cache.save();
      expect(await File('${file.path}.bak').exists(), isTrue);

      final reloaded = SnapshotCache(file: file);
      await reloaded.load();
      expect(
        reloaded
            .get(
              ProviderId.claude,
              surface: ProviderSurface.desktop,
              sourceId: 'claude-desktop-history',
            )
            ?.surface,
        ProviderSurface.desktop,
      );
      expect(reloaded.getStale(ProviderId.claude)?.stale, isTrue);
    },
  );

  test('cache: carrega formato antigo keyado só por provider', () async {
    final file = File('${temp.path}/cache.json');
    await file.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'entries': {
          'opencode': {
            'cachedAt': formatDate(DateTime.utc(2026, 11, 9, 12)),
            'snapshot': sampleSnapshot(fetchedAt: DateTime.utc(2026, 11, 9, 11))
                .toJson(),
          },
        },
      }),
    );
    final cache = SnapshotCache(file: file);
    await cache.load();
    expect(
      cache.get(ProviderId.opencode, maxAge: const Duration(days: 3650)),
      isNotNull,
    );
  });

  test('cache: backoff de 429 persiste e expira com o relógio', () async {
    final file = File('${temp.path}/cache.json');
    final cache = SnapshotCache(file: file);
    final until = DateTime.utc(2026, 11, 8, 12, 5);
    cache.setBackoff(ProviderId.codex, until);
    await cache.save();

    final reloaded = SnapshotCache(file: file);
    await reloaded.load();
    expect(
      reloaded.backoffUntil(
        ProviderId.codex,
        now: DateTime.utc(2026, 11, 8, 12, 1),
      ),
      until,
    );
    expect(
      reloaded.backoffUntil(
        ProviderId.codex,
        now: DateTime.utc(2026, 11, 8, 12, 6),
      ),
      isNull,
    );
  });

  test('doctor expõe checagem de escrita do data dir', () async {
    final paths = AppPaths(temp);
    final service = DefaultQuotaService(
      paths: paths,
      cache: SnapshotCache(),
      configStore: ConfigStore(paths.configFile),
      historyStore: null,
      httpClient: MockClient((_) async => http.Response('{}', 500)),
      processRunner: FakeProcessRunner(),
      env: const {},
      now: () => DateTime.utc(2026, 11, 9, 12),
      log: (_) {},
      adapters: const [],
    );
    addTearDown(service.dispose);
    final checks = await service.doctor();
    final dataDir = checks.firstWhere((c) => c.id == 'data-dir');
    expect(dataDir.status, DoctorStatus.ok);
    expect(dataDir.message, contains('gravável'));
  });
}
