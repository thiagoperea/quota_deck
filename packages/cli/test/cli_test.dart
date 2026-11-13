import 'dart:convert';
import 'dart:io';

import 'package:quota_deck_cli/quota_deck_cli.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

class FakeQuotaService implements QuotaService {
  AppConfig config = AppConfig.defaults();
  SnapshotEnvelope envelope = sampleEnvelope();
  List<DoctorCheck> doctorChecks = const [
    DoctorCheck(
      provider: ProviderId.opencode,
      id: 'db',
      label: 'Banco do OpenCode',
      status: DoctorStatus.ok,
      message: 'Encontrado',
    ),
  ];

  int snapshotCalls = 0;
  bool lastIncludeDisabled = false;

  /// Simula provedores desligados na config: somem do envelope e respeitam
  /// `includeDisabled`.
  Set<ProviderId> disabledProviders = {};

  /// Faz o snapshot lançar na N-ésima chamada (para encerrar o `watch`).
  int throwOnSnapshotCall = 0;
  int refreshCalls = 0;
  int doctorCalls = 0;
  int historyCalls = 0;
  bool disposed = false;

  Set<ProviderId>? lastProviders;
  bool? lastNoCache;
  ProviderId? lastHistoryProvider;
  String? lastHistoryWindow;
  Duration? lastHistoryDuration;

  @override
  Future<SnapshotEnvelope> snapshot({
    Set<ProviderId>? providers,
    bool noCache = false,
    bool includeDisabled = false,
  }) async {
    snapshotCalls++;
    if (throwOnSnapshotCall > 0 && snapshotCalls >= throwOnSnapshotCall) {
      throw const QdeckException(
        code: QdeckErrorCode.network,
        provider: ProviderId.opencode,
        message: 'offline',
      );
    }
    lastProviders = providers;
    lastNoCache = noCache;
    lastIncludeDisabled = includeDisabled;
    if (includeDisabled || disabledProviders.isEmpty) return envelope;
    final selected = (providers ?? ProviderId.values.toSet()).difference(
      disabledProviders,
    );
    return SnapshotEnvelope(
      results: [
        for (final result in envelope.results)
          if (selected.contains(result.provider)) result,
      ],
      errors: envelope.errors,
      generatedAt: envelope.generatedAt,
    );
  }

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) async {
    refreshCalls++;
    return envelope;
  }

  @override
  Future<List<DetectionResult>> detect() async => const [];

  @override
  Future<List<DoctorCheck>> doctor() async {
    doctorCalls++;
    return doctorChecks;
  }

  @override
  Future<AppConfig> getConfig() async => config;

  @override
  Future<AppConfig> updateConfig(AppConfig value) async {
    config = value;
    return config;
  }

  @override
  Future<HistorySummary> history({
    required ProviderId provider,
    required String windowId,
    Duration window = const Duration(hours: 24),
  }) async {
    historyCalls++;
    lastHistoryProvider = provider;
    lastHistoryWindow = windowId;
    lastHistoryDuration = window;
    return HistorySummary(
      provider: provider,
      windowId: windowId,
      samples: [
        HistorySample(
          provider: provider,
          windowId: windowId,
          usedPercent: 10,
          fetchedAt: DateTime.utc(2026, 11, 8, 13),
        ),
        HistorySample(
          provider: provider,
          windowId: windowId,
          usedPercent: 20,
          fetchedAt: DateTime.utc(2026, 11, 8, 14),
        ),
      ],
      burnRatePerHour: 10,
      etaHours: 8,
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class RecordingFactory {
  final FakeQuotaService service;
  int calls = 0;
  AppPaths? lastPaths;
  bool? lastVerbose;
  int? lastTtl;

  RecordingFactory(this.service);

  Future<QuotaService> call({
    required AppPaths paths,
    required bool verbose,
    int? ttlSeconds,
  }) async {
    calls++;
    lastPaths = paths;
    lastVerbose = verbose;
    lastTtl = ttlSeconds;
    return service;
  }
}

SnapshotEnvelope sampleEnvelope({List<QdeckErrorInfo> errors = const []}) {
  return SnapshotEnvelope(
    generatedAt: DateTime.utc(2026, 11, 8, 15),
    results: [
      ProviderSnapshot(
        provider: ProviderId.opencode,
        account: const AccountInfo(label: 'OpenCode Go', plan: 'Go'),
        windows: [
          QuotaWindow(
            id: 'rolling-5h',
            label: 'Rolling 5h',
            kind: WindowKind.rolling,
            usedPercent: 12,
            remainingPercent: 88,
            resetsAt: DateTime.utc(2026, 11, 8, 18),
            status: QuotaStatus.ok,
            source: SourceKind.api,
          ),
        ],
        source: 'opencode-usage-api',
        fetchedAt: DateTime.utc(2026, 11, 8, 15),
        confidence: Confidence.high,
      ),
    ],
    errors: errors,
  );
}

SnapshotEnvelope errorEnvelope(String code, {bool withSuccess = false}) {
  return SnapshotEnvelope(
    generatedAt: DateTime.utc(2026, 11, 8, 15),
    results: [
      if (withSuccess) ...sampleEnvelope().results,
      ProviderSnapshot(
        provider: ProviderId.codex,
        account: const AccountInfo(label: 'Codex'),
        windows: const [],
        source: 'error',
        fetchedAt: DateTime.utc(2026, 11, 8, 15),
        errors: [QdeckErrorInfo(code: code, message: 'falha')],
      ),
    ],
  );
}

void main() {
  late Directory temp;
  late FakeQuotaService service;
  late RecordingFactory factory;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_cli_test_');
    service = FakeQuotaService();
    factory = RecordingFactory(service);
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  QdeckCli cli({bool terminal = false, Map<String, String>? env}) {
    return QdeckCli(
      out: out,
      err: err,
      env: env ?? const {},
      stdoutHasTerminal: terminal,
      serviceFactory: factory.call,
    );
  }

  test('version imprime a versão', () async {
    final code = await cli().run(['version']);
    expect(code, QdeckExitCode.ok);
    expect(out.toString(), contains('qdeck $cliVersion'));
    expect(err.toString(), isEmpty);
  });

  test('help global e help de comando', () async {
    expect(await cli().run(['--help']), QdeckExitCode.ok);
    expect(out.toString(), contains('show'));
    expect(out.toString(), contains('watch'));
    expect(out.toString(), contains('statusline'));

    out.clear();
    expect(await cli().run(['show', '--help']), QdeckExitCode.ok);
    expect(out.toString(), contains('--provider'));
    expect(out.toString(), contains('--no-cache'));
  });

  test('statusline imprime linha compacta', () async {
    final code = await cli().run(['statusline']);
    expect(code, isNot(QdeckExitCode.usage));
    expect(out.toString(), contains('OC'));
  });

  test('sem comando mostra a ajuda', () async {
    final code = await cli().run([]);
    expect(code, QdeckExitCode.ok);
    expect(out.toString(), contains('Uso: qdeck'));
  });

  test('comando desconhecido retorna 64', () async {
    final code = await cli().run(['nope']);
    expect(code, QdeckExitCode.usage);
    expect(err.toString(), contains('Comando desconhecido'));
  });

  test('provider inválido retorna 64 sem criar serviço', () async {
    final code = await cli().run(['show', '--provider', 'nope']);
    expect(code, QdeckExitCode.usage);
    expect(err.toString(), contains('Provedor inválido'));
    expect(factory.calls, 0);
  });

  test('ttl inválido retorna 64 sem criar serviço', () async {
    final code = await cli().run(['show', '--ttl', 'abc']);
    expect(code, QdeckExitCode.usage);
    expect(err.toString(), contains('--ttl'));
    expect(factory.calls, 0);
  });

  test('show --json imprime JSON e usa --data-dir', () async {
    final code = await cli().run(['show', '--json', '--data-dir', temp.path]);
    expect(code, QdeckExitCode.ok);

    final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
    expect(decoded['results'], hasLength(1));
    expect(decoded['results'][0]['provider'], 'opencode');
    expect(factory.calls, 1);
    expect(factory.lastPaths!.dataDir.path, temp.path);
  });

  test('json é alias de show --json', () async {
    final code = await cli().run(['json']);
    expect(code, QdeckExitCode.ok);
    final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
    expect(decoded['schemaVersion'], 1);
  });

  test('show humano usa tabela e respeita --no-color', () async {
    final code = await cli(terminal: true).run(['show', '--no-color']);
    expect(code, QdeckExitCode.ok);
    final text = out.toString();
    expect(text, contains('OpenCode Go'));
    expect(text, contains('Rolling 5h'));
    expect(text, contains('12%'));
    expect(text, isNot(contains('\x1b[')));
  });

  test('show colorido em TTY usa ANSI e NO_COLOR desabilita', () async {
    await cli(terminal: true).run(['show']);
    expect(out.toString(), contains('\x1b['));

    out.clear();
    await cli(terminal: true, env: const {'NO_COLOR': ''}).run(['show']);
    expect(out.toString(), isNot(contains('\x1b[')));
  });

  test(
    'provider desabilitado avisa e retorna 5; include-disabled força',
    () async {
      service.disabledProviders.add(ProviderId.codex);
      service.config = service.config.copyWith(
        providers: {...service.config.providers, 'codex': false},
      );

      expect(
        await cli().run(['show', '--provider', 'codex', '--no-color']),
        QdeckExitCode.partial,
      );
      expect(err.toString(), contains('desabilitado'));
      expect(err.toString(), contains('--include-disabled'));
      expect(service.lastIncludeDisabled, isFalse);

      err.clear();
      out.clear();
      expect(
        await cli().run([
          'show',
          '--provider',
          'codex',
          '--include-disabled',
          '--no-color',
        ]),
        QdeckExitCode.ok,
      );
      expect(service.lastIncludeDisabled, isTrue);
      expect(err.toString(), isNot(contains('desabilitado')));
    },
  );

  test('watch em pipe não escreve sequência de limpeza ANSI', () async {
    service.throwOnSnapshotCall = 2;
    final code = await cli().run(['watch', '--interval', '5']);

    expect(code, QdeckExitCode.network);
    expect(service.snapshotCalls, 2);
    expect(out.toString(), isNot(contains('\x1b[2J')));
    expect(out.toString(), contains('Atualiza a cada 5s'));
  });

  test('watch --no-clear não limpa a tela nem em terminal', () async {
    service.throwOnSnapshotCall = 2;
    final code = await cli(terminal: true)
        .run(['watch', '--interval', '5', '--no-clear']);

    expect(code, QdeckExitCode.network);
    expect(out.toString(), isNot(contains('\x1b[2J')));
  });

  test('watch em terminal limpa a tela entre ciclos', () async {
    service.throwOnSnapshotCall = 2;
    // O clear sai antes do snapshot; a falha encerra o laço no 2º ciclo.
    await cli(terminal: true).run(['watch', '--interval', '5']);
    expect(out.toString(), contains('\x1b[2J'));
  });

  test(
    'provider aceita vírgula e repetição; no-cache e ttl são repassados',
    () async {
      var code = await cli().run([
        'show',
        '--provider',
        'opencode,codex',
        '--no-cache',
        '--ttl',
        '0',
      ]);
      expect(code, QdeckExitCode.ok);
      expect(service.lastProviders, {ProviderId.opencode, ProviderId.codex});
      expect(service.lastNoCache, isTrue);
      expect(factory.lastTtl, 0);

      code = await cli().run([
        'show',
        '--provider',
        'opencode',
        '--provider',
        'claude',
      ]);
      expect(code, QdeckExitCode.ok);
      expect(service.lastProviders, {ProviderId.opencode, ProviderId.claude});
    },
  );

  test('opções globais funcionam antes e depois do comando', () async {
    await cli().run(['--data-dir', temp.path, '--verbose', 'show']);
    expect(factory.lastPaths!.dataDir.path, temp.path);
    expect(factory.lastVerbose, isTrue);

    factory.calls = 0;
    await cli().run(['show', '--data-dir', temp.path, '--verbose']);
    expect(factory.calls, 1);
    expect(factory.lastPaths!.dataDir.path, temp.path);
    expect(factory.lastVerbose, isTrue);
  });

  test('settings --json e humano', () async {
    var code = await cli().run(['settings', '--json']);
    expect(code, QdeckExitCode.ok);
    final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
    expect(decoded['providers']['opencode'], isTrue);

    out.clear();
    code = await cli().run(['settings']);
    expect(code, QdeckExitCode.ok);
    expect(out.toString(), contains('Provedores:'));
    expect(out.toString(), contains('Atualização: 60s'));
  });

  test('doctor retorna 0 com checks ok e 5 com fail', () async {
    var code = await cli().run(['doctor']);
    expect(code, QdeckExitCode.ok);
    expect(out.toString(), contains('Banco do OpenCode'));

    service.doctorChecks = const [
      DoctorCheck(
        provider: ProviderId.codex,
        id: 'auth',
        label: 'Credencial',
        status: DoctorStatus.fail,
        message: 'Ausente',
      ),
    ];
    out.clear();
    code = await cli().run(['doctor']);
    expect(code, QdeckExitCode.partial);
  });

  test('doctor --json serializa checks e respeita desabilitados', () async {
    service.config = service.config.copyWith(
      providers: {...service.config.providers, 'codex': false},
    );
    service.doctorChecks = [
      const DoctorCheck(
        provider: ProviderId.opencode,
        id: 'db',
        label: 'Banco',
        status: DoctorStatus.ok,
        message: 'ok',
      ),
      const DoctorCheck(
        provider: ProviderId.codex,
        id: 'auth',
        label: 'auth.json',
        status: DoctorStatus.fail,
        message: 'quebrado',
      ),
    ];

    final code = await cli().run(['doctor', '--json']);
    expect(code, QdeckExitCode.ok);
    final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
    final checks = decoded['checks'] as List<dynamic>;
    expect(checks, hasLength(1));
    expect((checks.single as Map)['provider'], 'opencode');
    expect(decoded['ok'], isTrue);
  });

  test('doctor aceita --no-color e --data-dir', () async {
    service.doctorChecks = const [
      DoctorCheck(
        provider: ProviderId.opencode,
        id: 'db',
        label: 'Banco',
        status: DoctorStatus.ok,
        message: 'ok',
      ),
    ];
    final code = await cli(terminal: true)
        .run(['doctor', '--no-color', '--data-dir', temp.path]);
    expect(code, QdeckExitCode.ok);
    expect(out.toString(), isNot(contains('\x1b[')));
  });

  test('history valida opções e imprime resumo', () async {
    var code = await cli().run(['history', '--provider', 'opencode']);
    expect(code, QdeckExitCode.usage);
    expect(err.toString(), contains('--window'));

    err.clear();
    code = await cli().run([
      'history',
      '--provider',
      'opencode',
      '--window',
      'rolling',
      '--hours',
      '6',
    ]);
    expect(code, QdeckExitCode.ok);
    expect(out.toString(), contains('Histórico'));
    expect(out.toString(), contains('Burn rate'));
    expect(service.lastHistoryProvider, ProviderId.opencode);
    expect(service.lastHistoryWindow, 'rolling');
    expect(service.lastHistoryDuration, const Duration(hours: 6));
  });

  test('exit codes mapeiam auth, rede, rate limit e parcial', () {
    expect(exitCodeForEnvelope(errorEnvelope('AUTH_MISSING')), 2);
    expect(exitCodeForEnvelope(errorEnvelope('AUTH_EXPIRED')), 2);
    expect(exitCodeForEnvelope(errorEnvelope('NETWORK')), 3);
    expect(exitCodeForEnvelope(errorEnvelope('RATE_LIMITED')), 4);
    expect(exitCodeForEnvelope(errorEnvelope('UNKNOWN')), 5);
    expect(exitCodeForEnvelope(errorEnvelope('NETWORK', withSuccess: true)), 5);
    expect(exitCodeForEnvelope(sampleEnvelope()), 0);
  });

  test('formatação redige segredos e nunca mostra ANSI com no-color', () {
    final envelope = sampleEnvelope(
      errors: const [
        QdeckErrorInfo(
          code: 'AUTH_MISSING',
          message: 'token=super-secreto-nao-pode-vazar',
        ),
      ],
    );
    final text = formatSnapshot(envelope, color: false);
    expect(text, contains('AUTH_MISSING'));
    expect(text, isNot(contains('super-secreto-nao-pode-vazar')));
    expect(text, contains('<redacted>'));
    expect(text, isNot(contains('\x1b[')));
  });

  test('formatação colorida aplica ANSI', () {
    final text = formatSnapshot(sampleEnvelope(), color: true);
    expect(text, contains('\x1b['));
    expect(text, contains('Rolling 5h'));
  });
}
