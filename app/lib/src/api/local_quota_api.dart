import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../version.dart';
import 'quota_api.dart';

/// Implementação desktop: o core roda em um isolate próprio.
///
/// O `QuotaService` abre SQLite, dispara processos (`tasklist`, `where`) e
/// espera HTTP. Manter isso no isolate da UI fazia o refresh pendurar e
/// engasgar frames. O worker é persistente para preservar o cache de
/// detecção (5 min) e o cache de quota entre chamadas.
class LocalQuotaApi implements QuotaApi {
  LocalQuotaApi({this.paths, this.serviceFactory});

  final AppPaths? paths;

  /// Injetado em testes: roda no mesmo isolate, sem worker.
  final Future<QuotaService> Function(AppPaths paths)? serviceFactory;

  Future<QuotaService>? _serviceFuture;
  AppPaths? _resolvedPaths;

  _CoreClient? _client;

  AppPaths get _paths => _resolvedPaths ??= paths ?? AppPaths.forPlatform();

  Future<QuotaService> _service() {
    final existing = _serviceFuture;
    if (existing != null) return existing;
    final future =
        serviceFactory?.call(_paths) ??
        DefaultQuotaService.create(paths: _paths);
    _serviceFuture = future;
    return future;
  }

  Future<_CoreClient> _core() async {
    final existing = _client;
    if (existing != null) return existing;
    final client = await _CoreClient.spawn(_paths.dataDir.path);
    _client = client;
    return client;
  }

  Future<Map<String, dynamic>> _call(
    String op, [
    Map<String, dynamic>? args,
  ]) async {
    _CoreClient? client;
    try {
      client = await _core();
      return await client.call(op, args);
    } on ApiException {
      // Worker travado: descarta para que a próxima chamada respawne.
      if (client?.isDead ?? false) _client = null;
      rethrow;
    } catch (error) {
      _client = null;
      throw ApiException('O core de quotas falhou: $error');
    }
  }

  @override
  Future<SummaryPayload> fetchSummary() async {
    final paths = _paths;
    if (serviceFactory != null) {
      final service = await _service();
      return SummaryPayload(
        envelope: await service.snapshot(),
        config: await service.getConfig(),
        meta: _meta(paths),
      );
    }
    final data = await _call('summary');
    return SummaryPayload(
      envelope: SnapshotEnvelope.fromJson(
        (data['envelope'] as Map).cast<String, dynamic>(),
      ),
      config: AppConfig.fromJson(
        (data['config'] as Map).cast<String, dynamic>(),
      ),
      meta: _meta(paths),
    );
  }

  ApiMeta _meta(AppPaths paths) => ApiMeta(
    version: appVersion,
    dataDir: paths.maskedDataDir,
    providers: [
      for (final provider in ProviderId.values)
        ApiProviderInfo(id: provider, name: provider.displayName),
    ],
  );

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) async {
    if (serviceFactory != null) {
      final service = await _service();
      return service.refresh(provider: provider);
    }
    final data = await _call('refresh', {
      if (provider != null) 'provider': provider.wireName,
    });
    return SnapshotEnvelope.fromJson(
      (data['envelope'] as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<List<DetectionResult>> detect() async {
    if (serviceFactory != null) {
      final service = await _service();
      return service.detect();
    }
    final data = await _call('detect');
    final items = (data['detections'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((item) => DetectionResult.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  Future<List<DoctorCheck>> fetchDoctor() async {
    if (serviceFactory != null) {
      final service = await _service();
      return service.doctor();
    }
    final data = await _call('doctor');
    final items = (data['checks'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((item) => DoctorCheck.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  Future<HistorySummary> fetchHistory({
    required ProviderId provider,
    required String windowId,
    int hours = 24,
  }) async {
    if (serviceFactory != null) {
      final service = await _service();
      return service.history(
        provider: provider,
        windowId: windowId,
        window: Duration(hours: hours),
      );
    }
    final data = await _call('history', {
      'provider': provider.wireName,
      'windowId': windowId,
      'hours': hours,
    });
    return HistorySummary.fromJson(
      (data['history'] as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<AppConfig> fetchSettings() async {
    if (serviceFactory != null) {
      final service = await _service();
      return service.getConfig();
    }
    final data = await _call('settings');
    return AppConfig.fromJson((data['config'] as Map).cast<String, dynamic>());
  }

  @override
  Future<AppConfig> saveSettings(AppConfig config) async {
    if (serviceFactory != null) {
      final service = await _service();
      return service.updateConfig(config);
    }
    final data = await _call('saveSettings', {'config': config.toJson()});
    return AppConfig.fromJson((data['config'] as Map).cast<String, dynamic>());
  }

  @override
  Future<void> close() async {
    final client = _client;
    _client = null;
    await client?.close();
    final future = _serviceFuture;
    if (future != null) {
      try {
        final service = await future;
        await service.dispose();
      } catch (_) {}
    }
  }
}

/// Cliente RPC do isolate do core. Serializa modelos com `toJson`/`fromJson`.
class _CoreClient {
  _CoreClient._(this._isolate, this._toWorker, this._fromWorker, this._pending);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  final Map<int, Completer<Map<String, dynamic>>> _pending;
  int _nextId = 0;
  bool _closed = false;
  bool _dead = false;

  /// Worker travou ou foi encerrado: o chamador deve descartar este cliente.
  bool get isDead => _closed || _dead;

  static Future<_CoreClient> spawn(String dataDir) async {
    final fromWorker = ReceivePort();
    final pending = <int, Completer<Map<String, dynamic>>>{};
    final ready = Completer<SendPort>();

    fromWorker.listen((message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is! Map) return;
      final requestId = message['id'];
      if (requestId is! int) return;
      final completer = pending.remove(requestId);
      if (completer == null) return;
      if (message['ok'] == true) {
        final data = message['data'];
        completer.complete(
          data is Map ? data.cast<String, dynamic>() : <String, dynamic>{},
        );
      } else {
        completer.completeError(
          ApiException(message['error']?.toString() ?? 'Falha no core.'),
        );
      }
    });

    final isolate = await Isolate.spawn(
      _coreWorkerMain,
      [dataDir, fromWorker.sendPort],
      debugName: 'quota-deck-core',
      onError: fromWorker.sendPort,
      onExit: fromWorker.sendPort,
    );

    final SendPort toWorker;
    try {
      toWorker = await ready.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      fromWorker.close();
      throw const ApiException('Não foi possível iniciar o core de quotas.');
    }
    return _CoreClient._(isolate, toWorker, fromWorker, pending);
  }

  Future<Map<String, dynamic>> call(
    String op, [
    Map<String, dynamic>? args,
  ]) async {
    if (_closed) {
      throw const ApiException('O core de quotas foi encerrado.');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _toWorker.send({'id': id, 'op': op, 'args': args});
    try {
      return await completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          _pending.remove(id);
          _dead = true;
          throw const ApiException(
            'O core demorou demais para responder. Tente novamente.',
          );
        },
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      _toWorker.send({'id': -1, 'op': 'shutdown'});
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 40));
    _isolate.kill(priority: Isolate.immediate);
    _fromWorker.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const ApiException('O core de quotas foi encerrado.'),
        );
      }
    }
    _pending.clear();
  }
}

/// Entrada do isolate do core. Cria o serviço sob demanda e responde por
/// mensagens `{id, op, args}` com `{id, ok, data|error}`.
Future<void> _coreWorkerMain(List<Object?> args) async {
  final dataDir = args[0] as String;
  final host = args[1] as SendPort;
  final requests = ReceivePort();
  host.send(requests.sendPort);

  QuotaService? service;
  Future<QuotaService> resolve() async => service ??=
      await DefaultQuotaService.create(paths: AppPaths(Directory(dataDir)));

  await for (final message in requests) {
    if (message is! Map) continue;
    final id = message['id'];
    final op = message['op']?.toString() ?? '';
    if (op == 'shutdown') {
      await service?.dispose();
      requests.close();
      return;
    }
    final rawArgs = message['args'];
    final callArgs = rawArgs is Map
        ? rawArgs.cast<String, Object?>()
        : const <String, Object?>{};
    try {
      final core = await resolve();
      final data = await _dispatch(core, op, callArgs);
      host.send({'id': id, 'ok': true, 'data': data});
    } catch (error) {
      host.send({'id': id, 'ok': false, 'error': _friendlyError(error)});
    }
  }
}

Future<Map<String, dynamic>> _dispatch(
  QuotaService core,
  String op,
  Map<String, Object?> args,
) async {
  switch (op) {
    case 'summary':
      return {
        'envelope': (await core.snapshot()).toJson(),
        'config': (await core.getConfig()).toJson(),
      };
    case 'refresh':
      final provider = ProviderId.tryParse(args['provider']?.toString());
      return {'envelope': (await core.refresh(provider: provider)).toJson()};
    case 'detect':
      final detections = await core.detect();
      return {
        'detections': [for (final detection in detections) detection.toJson()],
      };
    case 'doctor':
      final checks = await core.doctor();
      return {
        'checks': [for (final check in checks) check.toJson()],
      };
    case 'history':
      final provider =
          ProviderId.tryParse(args['provider']?.toString()) ??
          ProviderId.opencode;
      final windowId = args['windowId']?.toString() ?? '';
      final hours = switch (args['hours']) {
        final int value => value,
        final num value => value.toInt(),
        _ => 24,
      };
      final summary = await core.history(
        provider: provider,
        windowId: windowId,
        window: Duration(hours: hours),
      );
      return {'history': summary.toJson()};
    case 'settings':
      return {'config': (await core.getConfig()).toJson()};
    case 'saveSettings':
      final raw = args['config'];
      if (raw is! Map) {
        throw const ApiException('Configuração inválida.');
      }
      final saved = await core.updateConfig(
        AppConfig.fromJson(raw.cast<String, dynamic>()),
      );
      return {'config': saved.toJson()};
    default:
      throw ApiException('Operação desconhecida: $op');
  }
}

String _friendlyError(Object error) {
  if (error is QdeckException) return error.message;
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}
