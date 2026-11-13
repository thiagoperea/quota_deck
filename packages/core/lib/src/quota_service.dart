import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:quota_deck_models/quota_deck_models.dart';

import 'cache.dart';
import 'config_store.dart';
import 'discovery.dart';
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
    bool includeDisabled = false,
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
    discovery: _discovery,
  );

  SystemDiscovery? _discoveryInstance;
  SystemDiscovery get _discovery =>
      _discoveryInstance ??= SystemDiscovery(processRunner, env: env, now: now);

  List<DetectionResult>? _detections;
  DateTime? _detectionsAt;

  Future<List<DetectionResult>> _detectAll({bool force = false}) async {
    final clock = now();
    final cached = _detections;
    if (!force &&
        cached != null &&
        _detectionsAt != null &&
        clock.difference(_detectionsAt!) < const Duration(minutes: 5)) {
      return cached;
    }
    if (force) {
      // Sem isso, binário instalado depois do start continua "ausente".
      _discovery.invalidate();
    }
    final ctx = _ctx;
    final results = await Future.wait(
      adapters.map((adapter) async {
        try {
          return await adapter.detect(ctx);
        } catch (_) {
          return DetectionResult(
            provider: adapter.id,
            detected: false,
            reason: 'Falha na detecção',
          );
        }
      }),
    );
    _detections = results;
    _detectionsAt = clock;
    return results;
  }

  @override
  Future<SnapshotEnvelope> snapshot({
    Set<ProviderId>? providers,
    bool noCache = false,
    bool includeDisabled = false,
  }) async {
    final config = await configStore.load();
    final selected = adapters
        .where((adapter) {
          if (providers != null && !providers.contains(adapter.id)) {
            return false;
          }
          return includeDisabled || config.isEnabled(adapter.id);
        })
        .toList(growable: false);

    final detections = await _detectAll();
    final byProvider = {
      for (final detection in detections) detection.provider: detection,
    };
    final ctx = _ctx;
    final results = await Future.wait(
      selected.map(
        (adapter) => _readOne(
          adapter,
          config,
          noCache: noCache,
          ctx: ctx,
          detection: byProvider[adapter.id],
        ),
      ),
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
    required ProviderContext ctx,
    DetectionResult? detection,
  }) async {
    if (detection != null && !detection.detected) {
      return _notInstalled(
        adapter.id,
        detection.reason ?? 'Não encontrado nesta máquina.',
      );
    }
    final blockedUntil = cache.backoffUntil(adapter.id, now: now());
    if (blockedUntil != null) {
      return _backedOff(adapter.id, blockedUntil);
    }
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
      snapshot = await adapter.read(ctx).timeout(const Duration(seconds: 12));
    } on QdeckException catch (e) {
      if (e.code == QdeckErrorCode.rateLimited) {
        final seconds = _retryAfterSeconds(e) ?? 300;
        if (seconds > 0) {
          final until = now().add(Duration(seconds: seconds));
          cache.setBackoff(adapter.id, until);
          return _fallbackOrError(
            adapter.id,
            QdeckException(
              code: e.code,
              provider: e.provider,
              message: e.message,
              details: {
                ...?e.details,
                'retryAt': formatDate(until),
                'retryAfterSeconds': seconds,
              },
            ),
          );
        }
      }
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
    } on SocketException {
      return _fallbackOrError(
        adapter.id,
        QdeckException(
          code: QdeckErrorCode.network,
          provider: adapter.id,
          message:
              'Sem conexão ao consultar ${adapter.id.displayName}. '
              'Verifique a rede ou o proxy.',
        ),
      );
    } on http.ClientException {
      return _fallbackOrError(
        adapter.id,
        QdeckException(
          code: QdeckErrorCode.network,
          provider: adapter.id,
          message:
              'Sem conexão ao consultar ${adapter.id.displayName}. '
              'Verifique a rede ou o proxy.',
        ),
      );
    } on HandshakeException {
      return _fallbackOrError(
        adapter.id,
        QdeckException(
          code: QdeckErrorCode.network,
          provider: adapter.id,
          message:
              'Falha de TLS ao consultar ${adapter.id.displayName}. '
              'Verifique proxy, certificado ou relógio do sistema.',
        ),
      );
    } on TlsException {
      return _fallbackOrError(
        adapter.id,
        QdeckException(
          code: QdeckErrorCode.network,
          provider: adapter.id,
          message:
              'Falha de TLS ao consultar ${adapter.id.displayName}. '
              'Verifique proxy, certificado ou relógio do sistema.',
        ),
      );
    } on FormatException {
      return _fallbackOrError(
        adapter.id,
        QdeckException(
          code: QdeckErrorCode.schemaChanged,
          provider: adapter.id,
          message:
              'Resposta inesperada de ${adapter.id.displayName} '
              '(formato mudou?).',
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
    cache.clearBackoff(adapter.id);
    try {
      historyStore?.appendSnapshot(snapshot);
    } catch (e) {
      // Histórico é complementar: falha no SQLite não pode derrubar a leitura.
      log('Histórico indisponível (${e.runtimeType}); leitura preservada.');
    }
    return snapshot;
  }

  ProviderSnapshot _notInstalled(ProviderId id, String reason) =>
      ProviderSnapshot(
        provider: id,
        account: AccountInfo(label: id.displayName),
        windows: const [],
        source: 'detection',
        fetchedAt: now(),
        confidence: Confidence.none,
        errors: [
          QdeckException(
            code: QdeckErrorCode.notInstalled,
            provider: id,
            message: reason,
          ).toInfo(),
        ],
      );

  ProviderSnapshot _fallbackOrError(ProviderId id, QdeckException error) {
    final stale = cache.getStale(id);
    if (stale != null) {
      return stale.copyWith(
        stale: true,
        errors: _mergeError(stale.errors, error.toInfo()),
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

  /// Devolve o último snapshot bom sem chamar a rede enquanto o backoff durar.
  ProviderSnapshot _backedOff(ProviderId id, DateTime until) {
    final remaining = until.difference(now());
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    final info = QdeckException(
      code: QdeckErrorCode.rateLimited,
      provider: id,
      message: 'Rate limit: nova tentativa em ${_humanEta(remaining)}.',
      details: {'retryAt': formatDate(until), 'retrySeconds': seconds},
    ).toInfo();
    final stale = cache.getStale(id);
    if (stale != null) {
      return stale.copyWith(
        stale: true,
        errors: _mergeError(stale.errors, info),
      );
    }
    return ProviderSnapshot(
      provider: id,
      account: AccountInfo(label: id.displayName),
      windows: const [],
      source: 'backoff',
      fetchedAt: now(),
      confidence: Confidence.none,
      errors: [info],
    );
  }

  /// Mantém no máximo um erro por código, para não crescer a cada polling.
  static List<QdeckErrorInfo> _mergeError(
    List<QdeckErrorInfo> errors,
    QdeckErrorInfo info,
  ) => [...errors.where((error) => error.code != info.code), info];

  static int? _retryAfterSeconds(QdeckException error) {
    final details = error.details;
    if (details == null) return null;
    for (final key in const [
      'retryAfterSeconds',
      'retry_after_seconds',
      'retryAfter',
      'retry_after',
    ]) {
      final value = details[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    final retryAt = parseDate(details['retryAt']);
    if (retryAt != null) {
      return retryAt.difference(DateTime.now().toUtc()).inSeconds;
    }
    return null;
  }

  static String _humanEta(Duration remaining) {
    final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest min';
  }

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) =>
      snapshot(providers: provider == null ? null : {provider}, noCache: true);

  @override
  Future<List<DetectionResult>> detect() => _detectAll(force: true);

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
