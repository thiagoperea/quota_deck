import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import 'exit_codes.dart';
import 'render.dart';
import 'version.dart';

typedef ServiceFactory = Future<QuotaService> Function({
  required AppPaths paths,
  required bool verbose,
  int? ttlSeconds,
});

/// CLI `qdeck`.
class QdeckCli {
  final StringSink out;
  final StringSink err;
  final Map<String, String> env;
  final bool stdoutHasTerminal;
  final ServiceFactory? serviceFactory;
  final String version;

  QdeckCli({
    StringSink? out,
    StringSink? err,
    Map<String, String>? env,
    bool? stdoutHasTerminal,
    this.serviceFactory,
    this.version = cliVersion,
  }) : out = out ?? stdout,
       err = err ?? stderr,
       env = env ?? Platform.environment,
       stdoutHasTerminal = stdoutHasTerminal ?? stdout.hasTerminal;

  Future<int> run(List<String> arguments) async {
    final parser = _buildParser();
    ArgResults root;
    try {
      root = parser.parse(arguments);
    } on FormatException catch (error) {
      err.writeln(error.message);
      _writeUsage(err, parser);
      return QdeckExitCode.usage;
    }

    if (root['help'] == true) {
      _writeUsage(out, parser);
      return QdeckExitCode.ok;
    }
    if (root['version'] == true) {
      out.writeln('qdeck $version');
      return QdeckExitCode.ok;
    }

    if (root.rest.isNotEmpty) {
      err.writeln('Comando desconhecido: ${root.rest.first}');
      _writeUsage(err, parser);
      return QdeckExitCode.usage;
    }

    final command = root.command;
    if (command == null) {
      _writeUsage(out, parser);
      return QdeckExitCode.ok;
    }

    if (command.rest.isNotEmpty) {
      err.writeln('Argumento desconhecido: ${command.rest.first}');
      _writeUsage(err, parser);
      return QdeckExitCode.usage;
    }

    if (command['help'] == true) {
      out.writeln('Uso: qdeck ${command.name} [opções]');
      final commandParser = parser.commands[command.name];
      if (commandParser != null) out.writeln(commandParser.usage);
      return QdeckExitCode.ok;
    }

    switch (command.name) {
      case 'version':
        out.writeln('qdeck $version');
        return QdeckExitCode.ok;
      case 'show':
        return _runShow(root, command, asJson: command['json'] == true);
      case 'json':
        return _runShow(root, command, asJson: true);
      case 'doctor':
        return _runDoctor(root, command);
      case 'history':
        return _runHistory(root, command);
      case 'settings':
        return _runSettings(root, command);
      case 'watch':
        return _runWatch(root, command);
      case 'statusline':
        return _runStatusline(root, command);
      default:
        err.writeln('Comando desconhecido: ${command.name}');
        _writeUsage(err, parser);
        return QdeckExitCode.usage;
    }
  }

  void _writeUsage(StringSink sink, ArgParser parser) {
    sink.writeln('Uso: qdeck <comando> [opções]');
    sink.writeln(parser.usage);
    sink.writeln('Comandos:');
    for (final name in parser.commands.keys) {
      sink.writeln('  $name');
    }
  }

  // ---------------------------------------------------------------------------
  // Comandos
  // ---------------------------------------------------------------------------

  Future<int> _runShow(
    ArgResults root,
    ArgResults command, {
    required bool asJson,
  }) async {
    try {
      final providers = _parseProviders(command['provider'] as List<String>);
      final ttl = _readTtl(command);
      final noCache = command['no-cache'] == true;
      final includeDisabled = command['include-disabled'] == true;
      final color = _useColor(noColor: command['no-color'] == true);

      return await _withService(
        _paths(root),
        verbose: _globalFlag(root, 'verbose'),
        ttlSeconds: ttl,
        body: (service) async {
          final envelope = await service.snapshot(
            providers: providers,
            noCache: noCache,
            includeDisabled: includeDisabled,
          );
          final config = await service.getConfig();
          final missing = _disabledProviders(providers, config);
          if (missing.isNotEmpty && !includeDisabled) {
            for (final provider in missing) {
              err.writeln(
                '${provider.displayName} está desabilitado nas configurações '
                '(qdeck settings). Use --include-disabled para consultar '
                'mesmo assim.',
              );
            }
          }
          if (asJson) {
            out.writeln(
              const JsonEncoder.withIndent('  ').convert(envelope.toJson()),
            );
          } else {
            out.writeln(formatSnapshot(envelope, color: color));
          }
          final code = exitCodeForEnvelope(envelope);
          if (missing.isNotEmpty && !includeDisabled) {
            return QdeckExitCode.partial;
          }
          return code;
        },
      );
    } on FormatException catch (error) {
      err.writeln(error.message);
      return QdeckExitCode.usage;
    }
  }

  Future<int> _runDoctor(ArgResults root, ArgResults command) async {
    return _withService(
      _paths(root),
      verbose: _globalFlag(root, 'verbose'),
      body: (service) async {
        final config = await service.getConfig();
        // Check de provedor desligado não deve reprovar o diagnóstico.
        final checks = (await service.doctor())
            .where((check) => config.isEnabled(check.provider))
            .toList(growable: false);
        final failures = checks.any(
          (check) => check.status == DoctorStatus.fail,
        );
        if (command['json'] == true) {
          out.writeln(
            const JsonEncoder.withIndent('  ').convert({
              'checks': [for (final check in checks) check.toJson()],
              'ok': !failures,
            }),
          );
        } else {
          out.writeln(
            formatDoctor(
              checks,
              color: _useColor(noColor: command['no-color'] == true),
            ),
          );
        }
        return failures ? QdeckExitCode.partial : QdeckExitCode.ok;
      },
    );
  }

  Future<int> _runHistory(ArgResults root, ArgResults command) async {
    final providerRaw = command['provider'] as String?;
    if (providerRaw == null || providerRaw.trim().isEmpty) {
      err.writeln('--provider é obrigatório.');
      return QdeckExitCode.usage;
    }
    final provider = ProviderId.tryParse(providerRaw);
    if (provider == null) {
      err.writeln('Provedor inválido: $providerRaw');
      return QdeckExitCode.usage;
    }

    final windowRaw = command['window'] as String?;
    if (windowRaw == null || windowRaw.trim().isEmpty) {
      err.writeln('--window é obrigatório.');
      return QdeckExitCode.usage;
    }

    final hoursRaw = command['hours'] as String;
    final hours = int.tryParse(hoursRaw);
    if (hours == null || hours <= 0) {
      err.writeln('--hours deve ser um inteiro maior que zero.');
      return QdeckExitCode.usage;
    }

    return _withService(
      _paths(root),
      verbose: _globalFlag(root, 'verbose'),
      body: (service) async {
        final summary = await service.history(
          provider: provider,
          windowId: windowRaw.trim(),
          window: Duration(hours: hours),
        );
        out.writeln(formatHistory(summary, color: _useColor()));
        return QdeckExitCode.ok;
      },
    );
  }

  Future<int> _runSettings(ArgResults root, ArgResults command) async {
    return _withService(
      _paths(root),
      verbose: _globalFlag(root, 'verbose'),
      body: (service) async {
        final config = await service.getConfig();
        if (command['json'] == true) {
          out.writeln(
            const JsonEncoder.withIndent('  ').convert(config.toJson()),
          );
        } else {
          out.writeln(formatSettings(config));
        }
        return QdeckExitCode.ok;
      },
    );
  }

  Future<int> _runWatch(ArgResults root, ArgResults command) async {
    final intervalRaw = command['interval'] as String;
    final interval = int.tryParse(intervalRaw);
    if (interval == null || interval < 5) {
      err.writeln('--interval deve ser um inteiro >= 5 (segundos).');
      return QdeckExitCode.usage;
    }

    try {
      final providers = _parseProviders(command['provider'] as List<String>);
      final color = _useColor(noColor: command['no-color'] == true);
      // Limpar a tela só faz sentido num terminal; em pipe isso injeta ANSI no
      // log e quebra `qdeck watch | grep`.
      final clearScreen = stdoutHasTerminal && command['no-clear'] != true;

      return await _withService(
        _paths(root),
        verbose: _globalFlag(root, 'verbose'),
        body: (service) async {
          var first = true;
          while (true) {
            final envelope = await service.snapshot(
              providers: providers,
              noCache: true,
            );
            if (clearScreen) {
              out.writeln('\x1b[2J\x1b[H');
            } else if (!first) {
              out.writeln();
            }
            first = false;
            out.writeln(formatSnapshot(envelope, color: color));
            out.writeln('\nAtualiza a cada ${interval}s · Ctrl+C para sair');
            await Future<void>.delayed(Duration(seconds: interval));
          }
        },
      );
    } on FormatException catch (error) {
      err.writeln(error.message);
      return QdeckExitCode.usage;
    }
  }

  Future<int> _runStatusline(ArgResults root, ArgResults command) async {
    return _withService(
      _paths(root),
      verbose: _globalFlag(root, 'verbose'),
      body: (service) async {
        final envelope = await service.snapshot();
        out.writeln(formatStatusline(envelope));
        return exitCodeForEnvelope(envelope);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Infraestrutura
  // ---------------------------------------------------------------------------

  Future<int> _withService(
    AppPaths paths, {
    required bool verbose,
    int? ttlSeconds,
    required Future<int> Function(QuotaService service) body,
  }) async {
    QuotaService? service;
    try {
      service = await (serviceFactory ?? _createDefaultService)(
        paths: paths,
        verbose: verbose,
        ttlSeconds: ttlSeconds,
      );
      return await body(service);
    } on QdeckException catch (error) {
      err.writeln('Erro: ${redact(error.message)}');
      return exitCodeForErrorCode(error.code.wireName);
    } catch (error) {
      err.writeln('Erro: falha inesperada (${error.runtimeType})');
      return QdeckExitCode.partial;
    } finally {
      try {
        await service?.dispose();
      } catch (_) {
        // Ignora falha ao descartar recursos após o comando.
      }
    }
  }

  Future<QuotaService> _createDefaultService({
    required AppPaths paths,
    required bool verbose,
    int? ttlSeconds,
  }) async {
    final log = verbose
        ? (String message) => err.writeln('[qdeck] ${redact(message)}')
        : null;

    if (ttlSeconds == null) {
      return DefaultQuotaService.create(paths: paths, env: env, log: log);
    }

    await paths.ensure();
    final config = (await ConfigStore(
      paths.configFile,
    ).load()).copyWith(cacheTtlSeconds: ttlSeconds);
    final configStore = _InMemoryConfigStore(paths.configFile, config);
    final cache = SnapshotCache(file: paths.cacheFile);
    await cache.load();

    HistoryStore? history;
    if (config.historyEnabled) {
      try {
        history = HistoryStore.open(paths.historyDb);
        history.prune(retentionDays: config.retentionDays);
      } catch (_) {
        history = null;
      }
    }

    return DefaultQuotaService(
      paths: paths,
      cache: cache,
      configStore: configStore,
      historyStore: history,
      httpClient: http.Client(),
      processRunner: const DartProcessRunner(),
      env: env,
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

  AppPaths _paths(ArgResults root) => AppPaths.forPlatform(
    env: env,
    overrideDataDir: _globalString(root, 'data-dir'),
  );

  String? _globalString(ArgResults root, String name) {
    final command = root.command;
    if (command != null && command.wasParsed(name)) {
      return command[name] as String?;
    }
    if (root.wasParsed(name)) return root[name] as String?;
    return root[name] as String?;
  }

  bool _globalFlag(ArgResults root, String name) {
    final command = root.command;
    if (command != null && command.wasParsed(name)) {
      return command[name] == true;
    }
    return root[name] == true;
  }

  /// Provedores pedidos explicitamente que estão desligados na configuração.
  List<ProviderId> _disabledProviders(
    Set<ProviderId>? requested,
    AppConfig config,
  ) {
    if (requested == null || requested.isEmpty) return const [];
    return [
      for (final provider in requested)
        if (!config.isEnabled(provider)) provider,
    ];
  }

  Set<ProviderId>? _parseProviders(List<String> values) {
    if (values.isEmpty) return null;
    final providers = <ProviderId>{};
    for (final value in values) {
      for (final part in value.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        final provider = ProviderId.tryParse(trimmed);
        if (provider == null) {
          throw FormatException('Provedor inválido: $trimmed');
        }
        providers.add(provider);
      }
    }
    return providers.isEmpty ? null : providers;
  }

  int? _readTtl(ArgResults command) {
    if (!command.wasParsed('ttl')) return null;
    final raw = command['ttl'] as String;
    final ttl = int.tryParse(raw);
    if (ttl == null || ttl < 0) {
      throw const FormatException(
        '--ttl deve ser um inteiro maior ou igual a 0.',
      );
    }
    return ttl;
  }

  bool _useColor({bool noColor = false}) {
    if (noColor) return false;
    if (env.containsKey('NO_COLOR')) return false;
    return stdoutHasTerminal;
  }

  // ---------------------------------------------------------------------------
  // Parser
  // ---------------------------------------------------------------------------

  ArgParser _buildParser() {
    final parser = ArgParser()
      ..addOption('data-dir', help: 'Diretório de dados do QuotaDeck.')
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Logs detalhados em stderr.',
      )
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Mostra ajuda.')
      ..addFlag('version', negatable: false, help: 'Mostra a versão.');

    _addShowCommand(parser, 'show', alias: false);
    _addShowCommand(parser, 'json', alias: true);
    _addDoctorCommand(parser);
    _addHistoryCommand(parser);
    _addSettingsCommand(parser);
    _addWatchCommand(parser);
    _addStatuslineCommand(parser);
    _addVersionCommand(parser);
    return parser;
  }

  void _addGlobalOptions(ArgParser parser) {
    parser
      ..addOption('data-dir', help: 'Diretório de dados do QuotaDeck.')
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Logs detalhados em stderr.',
      );
  }

  void _addShowCommand(ArgParser root, String name, {required bool alias}) {
    final command = root.addCommand(name);
    _addGlobalOptions(command);
    command
      ..addMultiOption(
        'provider',
        splitCommas: true,
        valueHelp: 'id',
        help: 'Provedores (ex.: opencode,codex).',
      )
      ..addFlag(
        'no-cache',
        negatable: false,
        help: 'Ignora o cache de snapshots.',
      )
      ..addOption(
        'ttl',
        valueHelp: 'segundos',
        help: 'TTL do cache somente nesta execução.',
      )
      ..addFlag(
        'include-disabled',
        negatable: false,
        help: 'Consulta também provedores desligados nas configurações.',
      )
      ..addFlag('no-color', negatable: false, help: 'Desabilita cores ANSI.')
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Mostra ajuda.');
    if (!alias) {
      command.addFlag('json', negatable: false, help: 'Saída JSON.');
    }
  }

  void _addDoctorCommand(ArgParser root) {
    final command = root.addCommand('doctor');
    _addGlobalOptions(command);
    command
      ..addFlag('json', negatable: false, help: 'Saída JSON.')
      ..addFlag('no-color', negatable: false, help: 'Desabilita cores ANSI.')
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Mostra ajuda.');
  }

  void _addHistoryCommand(ArgParser root) {
    final command = root.addCommand('history');
    _addGlobalOptions(command);
    command
      ..addOption('provider', valueHelp: 'id', help: 'Provedor (obrigatório).')
      ..addOption('window', valueHelp: 'id', help: 'Janela (obrigatório).')
      ..addOption(
        'hours',
        defaultsTo: '24',
        valueHelp: 'N',
        help: 'Período em horas.',
      )
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Mostra ajuda.');
  }

  void _addSettingsCommand(ArgParser root) {
    final command = root.addCommand('settings');
    _addGlobalOptions(command);
    command
      ..addFlag('json', negatable: false, help: 'Saída JSON.')
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Mostra ajuda.');
  }

  void _addWatchCommand(ArgParser root) {
    final command = root.addCommand('watch');
    _addGlobalOptions(command);
    command
      ..addMultiOption(
        'provider',
        splitCommas: true,
        valueHelp: 'id',
        help: 'Provedores (ex.: opencode,codex).',
      )
      ..addOption(
        'interval',
        defaultsTo: '60',
        valueHelp: 'segundos',
        help: 'Intervalo entre atualizações (>= 5).',
      )
      ..addFlag('no-color', negatable: false, help: 'Desabilita cores ANSI.')
      ..addFlag(
        'no-clear',
        negatable: false,
        help: 'Não limpa a tela entre atualizações.',
      )
      ..addFlag('help', abbr: 'h', negatable: false, help: 'Mostra ajuda.');
  }

  void _addStatuslineCommand(ArgParser root) {
    final command = root.addCommand('statusline');
    _addGlobalOptions(command);
    command.addFlag('help', abbr: 'h', negatable: false, help: 'Mostra ajuda.');
  }

  void _addVersionCommand(ArgParser root) {
    final command = root.addCommand('version');
    _addGlobalOptions(command);
    command.addFlag('help', abbr: 'h', negatable: false, help: 'Mostra ajuda.');
  }
}

class _InMemoryConfigStore extends ConfigStore {
  AppConfig _value;

  _InMemoryConfigStore(super.file, this._value);

  @override
  AppConfig get current => _value;

  @override
  Future<AppConfig> load({bool force = false}) async => _value;

  @override
  Future<AppConfig> save(AppConfig config) async {
    _value = config;
    return _value;
  }
}
