import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:quota_deck_models/quota_deck_models.dart';

import 'cache.dart';
import 'config_store.dart';
import 'errors.dart';
import 'history.dart';
import 'paths.dart';
import 'process_runner.dart';
import 'provider.dart';
import 'providers/antigravity.dart';
import 'providers/claude.dart';
import 'providers/codex.dart';
import 'providers/opencode.dart';

abstract class QuotaService {
  Future<SnapshotEnvelope> snapshot({
    Set<ProviderId>? providers,
    bool noCache = false,
  });

  Future<SnapshotEnvelope> refresh({ProviderId? provider});

  Future<List<DetectionResult>> detect();

  Future<List<DoctorCheck>> doctor();

  Future<AppConfig> getConfig();

  Future<AppConfig> updateConfig(AppConfig config);

  Future<HistorySummary> history({
    required ProviderId provider,
    required String windowId,
    Duration window = const Duration(hours: 24),
  });

  Future<void> dispose();
}

class DefaultQuotaService implements QuotaService {
  final AppPaths paths;
  final SnapshotCache cache;
  final ConfigStore configStore;
  final HistoryStore? historyStore;
  final http.Client httpClient;
  final ProcessRunner processRunner;
  final Map<String, String> env;
  final DateTime Function() now;
  final void Function(String message) log;
  final List<ProviderAdapter> adapters;

  DefaultQuotaService({
    required this.paths,
    required this.cache,
    required this.configStore,
    required this.historyStore,
    required this.httpClient,
    required this.processRunner,
    required this.env,
    required this.now,
    required this.log,
    required this.adapters,
  });

  static Future<DefaultQuotaService> create({
    AppPaths? paths,
    AppConfig? config,
    http.Client? httpClient,
    ProcessRunner? processRunner,
    Map<String, String>? env,
    bool enableHistory = true,
    void Function(String message)? log,
  }) async {
    final e = env ?? Platform.environment;
    final resolvedPaths = paths ?? AppPaths.forPlatform(env: e);
    await resolvedPaths.ensure();

    final configStore = ConfigStore(resolvedPaths.configFile);
    if (config != null) {
      await configStore.save(config);
    }
    final loadedConfig = await configStore.load();

    final cache = SnapshotCache(file: resolvedPaths.cacheFile);
    await cache.load();

    HistoryStore? history;
    if (enableHistory && loadedConfig.historyEnabled) {
      try {
        history = HistoryStore.open(resolvedPaths.historyDb);
        history.prune(retentionDays: loadedConfig.retentionDays);
      } catch (err) {
        history = null;
      }
    }

    return DefaultQuotaService(
      paths: resolvedPaths,
      cache: cache,
      configStore: configStore,
      historyStore: history,
      httpClient: httpClient ?? http.Client(),
      processRunner: processRunner ?? const DartProcessRunner(),
      env: e,
      now: () => DateTime.now().toUtc(),
      log: log ?? (_) {},
      adapters: const [
        OpenCodeProvider(),
        AntigravityProvider(),
        CodexProvider(),
        ClaudeProvider(),
      ],
    );
  }

  ProviderContext get _ctx => ProviderContext(
    paths: paths,
    http: httpClient,
    process: processRunner,
    env: env,
    now: now,
    log: log,
  );

  @override
  Future<SnapshotEnvelope> snapshot({
    Set<ProviderId>? providers,
    bool noCache = false,
  }) async {
    final config = await configStore.load();
    final selected = adapters
        .where((adapter) {
          if (providers != null && !providers.contains(adapter.id)) {
            return false;
          }
          return config.isEnabled(adapter.id);
        })
        .toList(growable: false);

    final results = await Future.wait(
      selected.map((adapter) => _readOne(adapter, config, noCache: noCache)),
    );

    await cache.save();

    return SnapshotEnvelope(
      generatedAt: now(),
      results: results,
      errors: results.expand((r) => r.errors).toList(growable: false),
    );
  }

  Future<ProviderSnapshot> _readOne(
    ProviderAdapter adapter,
    AppConfig config, {
    required bool noCache,
  }) async {
    if (!noCache) {
      final cached = cache.get(
        adapter.id,
        maxAge: Duration(seconds: config.cacheTtlSeconds),
      );
      if (cached != null) {
        return cached;
      }
    }

    final ProviderSnapshot snapshot;
    try {
      snapshot = await adapter.read(_ctx).timeout(const Duration(seconds: 40));
    } on QdeckException catch (e) {
      return _fallbackOrError(adapter.id, e);
    } on TimeoutException {
      return _fallbackOrError(
        adapter.id,
        QdeckException(
          code: QdeckErrorCode.network,
          provider: adapter.id,
          message: 'Tempo esgotado ao consultar ${adapter.id.displayName}.',
        ),
      );
    } catch (e) {
      return _fallbackOrError(
        adapter.id,
        QdeckException(
          code: QdeckErrorCode.unknown,
          provider: adapter.id,
          message: 'Erro inesperado: ${e.runtimeType}',
        ),
      );
    }

    cache.put(snapshot);
    try {
      historyStore?.appendSnapshot(snapshot);
    } catch (e) {
      // Histórico é complementar: falha no SQLite não pode derrubar a leitura.
      log('Histórico indisponível (${e.runtimeType}); leitura preservada.');
    }
    return snapshot;
  }

  ProviderSnapshot _fallbackOrError(ProviderId id, QdeckException error) {
    final stale = cache.getStale(id);
    if (stale != null) {
      return stale.copyWith(
        stale: true,
        errors: [...stale.errors, error.toInfo()],
      );
    }
    return ProviderSnapshot(
      provider: id,
      account: AccountInfo(label: id.displayName),
      windows: const [],
      source: 'error',
      fetchedAt: now(),
      confidence: Confidence.none,
      errors: [error.toInfo()],
    );
  }

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) =>
      snapshot(providers: provider == null ? null : {provider}, noCache: true);

  @override
  Future<List<DetectionResult>> detect() async {
    final results = <DetectionResult>[];
    for (final adapter in adapters) {
      try {
        results.add(await adapter.detect(_ctx));
      } catch (_) {
        results.add(
          DetectionResult(
            provider: adapter.id,
            detected: false,
            reason: 'Falha na detecção',
          ),
        );
      }
    }
    return results;
  }

  @override
  Future<List<DoctorCheck>> doctor() async {
    var writable = false;
    try {
      final probe = File(
        '${paths.dataDir.path}${Platform.pathSeparator}.doctor-write-probe',
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      writable = true;
    } catch (_) {
      writable = false;
    }
    final checks = <DoctorCheck>[
      DoctorCheck(
        provider: ProviderId.opencode,
        id: 'data-dir',
        label: 'Diretório de dados',
        status: writable ? DoctorStatus.ok : DoctorStatus.fail,
        message: writable
            ? 'Dados locais em ${paths.maskedDataDir} (gravável)'
            : 'Sem permissão de escrita em ${paths.maskedDataDir}',
      ),
    ];
    for (final adapter in adapters) {
      try {
        checks.addAll(await adapter.doctor(_ctx));
      } catch (e) {
        checks.add(
          DoctorCheck(
            provider: adapter.id,
            id: 'doctor-error',
            label: 'Diagnóstico',
            status: DoctorStatus.fail,
            message: 'Falha ao diagnosticar: ${e.runtimeType}',
          ),
        );
      }
    }
    return checks;
  }

  @override
  Future<AppConfig> getConfig() => configStore.load();

  @override
  Future<AppConfig> updateConfig(AppConfig config) async {
    await configStore.save(config);
    return config;
  }

  @override
  Future<HistorySummary> history({
    required ProviderId provider,
    required String windowId,
    Duration window = const Duration(hours: 24),
  }) async {
    final store = historyStore;
    if (store == null) {
      return HistorySummary(
        provider: provider,
        windowId: windowId,
        samples: const [],
        burnRatePerHour: 0,
      );
    }
    return store.summary(provider, windowId, window: window);
  }

  @override
  Future<void> dispose() async {
    httpClient.close();
    historyStore?.close();
  }
}
