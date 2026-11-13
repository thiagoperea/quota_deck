import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';
import 'support/sample.dart';

/// `which` que passa a responder depois — simula instalar o binário com o app
/// aberto.
class _FlakyWhichRunner implements ProcessRunner {
  bool installed = false;

  @override
  Future<ProcessResultData> run(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (executable == 'which' || executable == 'where') {
      if (!installed) {
        return const ProcessResultData(exitCode: 1, stdout: '', stderr: '');
      }
      return ProcessResultData(
        exitCode: 0,
        stdout: '/usr/local/bin/${args.isEmpty ? 'x' : args.first}\n',
        stderr: '',
      );
    }
    if (executable == 'ps') {
      return const ProcessResultData(exitCode: 0, stdout: '', stderr: '');
    }
    return const ProcessResultData(exitCode: 1, stdout: '', stderr: '');
  }

  @override
  Future<ProcessSession> start(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
  }) async => throw UnimplementedError();
}

class _DiscoveryAdapter implements ProviderAdapter {
  @override
  ProviderId get id => ProviderId.opencode;

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async {
    final path = await ctx.discovery.firstBinary(['codex']);
    return DetectionResult(
      provider: id,
      detected: path != null,
      surfaces: [
        SurfaceState(
          surface: ProviderSurface.cli,
          installed: path != null,
          location: path,
        ),
      ],
    );
  }

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async =>
      sampleSnapshot(used: 1);

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async => const [];
}

class _FakeAdapter implements ProviderAdapter {
  int calls = 0;
  bool fail = false;
  bool rateLimit = false;
  Object? throwable;

  @override
  ProviderId get id => ProviderId.opencode;

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async =>
      const DetectionResult(provider: ProviderId.opencode, detected: true);

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    calls++;
    if (throwable != null) throw throwable!;
    if (rateLimit) {
      throw const QdeckException(
        code: QdeckErrorCode.rateLimited,
        provider: ProviderId.opencode,
        message: 'slow down',
        details: {'retryAfterSeconds': 120},
      );
    }
    if (fail) {
      throw const QdeckException(
        code: QdeckErrorCode.network,
        provider: ProviderId.opencode,
        message: 'offline',
      );
    }
    return sampleSnapshot(used: calls * 10.0);
  }

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async => const [];
}

void main() {
  late Directory temp;
  late _FakeAdapter adapter;
  late DefaultQuotaService service;
  late SnapshotCache cache;
  late DateTime clock;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_service_');
    final paths = AppPaths(temp);
    final configStore = ConfigStore(paths.configFile);
    await configStore.save(AppConfig.defaults());
    adapter = _FakeAdapter();
    clock = DateTime.utc(2026, 11, 8, 12);
    cache = SnapshotCache();
    service = DefaultQuotaService(
      paths: paths,
      cache: cache,
      configStore: configStore,
      historyStore: null,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      processRunner: FakeProcessRunner(),
      env: const {},
      now: () => clock,
      log: (_) {},
      adapters: [adapter],
    );
  });

  tearDown(() async {
    await service.dispose();
    await temp.delete(recursive: true);
  });

  test('uses cache within ttl and refresh bypasses it', () async {
    final first = await service.snapshot();
    expect(first.results, hasLength(1));
    expect(adapter.calls, 1);

    final cached = await service.snapshot();
    expect(cached.results.first.windows.first.usedPercent, 10);
    expect(adapter.calls, 1);

    final refreshed = await service.refresh();
    expect(refreshed.results.first.windows.first.usedPercent, 20);
    expect(adapter.calls, 2);
  });

  test('falls back to stale cache on error', () async {
    await service.snapshot();
    adapter.fail = true;
    final result = await service.snapshot(noCache: true);
    final snapshot = result.results.first;
    expect(snapshot.stale, isTrue);
    expect(snapshot.errors, isNotEmpty);
    expect(snapshot.windows.first.usedPercent, 10);
  });

  test('falha de transporte vira NETWORK', () async {
    adapter.throwable = const SocketException('sem rota');
    final result = await service.snapshot();
    expect(result.results.first.errors.first.code, 'NETWORK');

    adapter.throwable = http.ClientException('proxy fechou');
    final again = await service.snapshot(noCache: true);
    expect(again.results.first.errors.first.code, 'NETWORK');
  });

  test('JSON inválido vira SCHEMA_CHANGED', () async {
    adapter.throwable = const FormatException('Unexpected character');
    final result = await service.snapshot();
    expect(result.results.first.errors.first.code, 'SCHEMA_CHANGED');
  });

  test('detect(force) revalida binário instalado depois da abertura', () async {
    final runner = _FlakyWhichRunner();
    final refreshable = DefaultQuotaService(
      paths: AppPaths(temp),
      cache: cache,
      configStore: ConfigStore(File('${temp.path}/config.json')),
      historyStore: null,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      processRunner: runner,
      env: const {},
      now: () => clock,
      log: (_) {},
      adapters: [_DiscoveryAdapter()],
    );
    addTearDown(refreshable.dispose);

    final before = await refreshable.detect();
    expect(before.single.detected, isFalse);

    runner.installed = true;
    final after = await refreshable.detect();
    expect(after.single.detected, isTrue);
    expect(after.single.surfaces.single.location, contains('codex'));
  });

  test('429 aplica backoff e não chama o adapter durante o bloqueio', () async {
    adapter.rateLimit = true;
    final first = await service.snapshot();
    expect(adapter.calls, 1);
    expect(first.results.first.errors.first.code, 'RATE_LIMITED');
    final retryAt = parseDate(
      first.results.first.errors.first.details?['retryAt'],
    );
    expect(retryAt, isNotNull);
    expect(retryAt!.isAfter(DateTime.utc(2026, 11, 8, 12)), isTrue);

    // Refresh manual também respeita o bloqueio (Retry-After de 120 s).
    final second = await service.refresh();
    expect(adapter.calls, 1);
    expect(second.results.first.errors.first.code, 'RATE_LIMITED');
  });

  test('backoff expira e o próximo fetch volta a funcionar', () async {
    adapter.rateLimit = true;
    await service.snapshot();
    expect(adapter.calls, 1);
    await service.refresh();
    expect(adapter.calls, 1);

    clock = clock.add(const Duration(minutes: 3));
    adapter.rateLimit = false;
    final after = await service.refresh();
    expect(adapter.calls, 2);
    expect(after.results.first.errors, isEmpty);
    expect(cache.backoffUntil(ProviderId.opencode, now: clock), isNull);
  });
}
