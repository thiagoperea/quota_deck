import 'dart:io';

const _packages = ['packages/models', 'packages/core', 'packages/cli'];

/// Diretórios gerados que o `clean` pode apagar sem medo.
const _artifacts = [
  'app/.dart_tool',
  'app/build',
  'app/.flutter-plugins',
  'app/.flutter-plugins-dependencies',
  'app/macos/Flutter/ephemeral',
  'app/macos/Pods',
  'app/macos/.symlinks',
  'app/windows/flutter/ephemeral',
  'app/linux/flutter/ephemeral',
  'packages/models/.dart_tool',
  'packages/models/build',
  'packages/core/.dart_tool',
  'packages/core/build',
  'packages/cli/.dart_tool',
  'packages/cli/build',
  '.dart_tool',
];

const _usage = '''
qdeck tasks:
  setup | format | analyze | test
  build-windows | build-macos | build-linux
  run-windows | run-macos | run-linux
  cli -- <args>
  bump <versão> [build]   (atualiza app, pacotes, versões de código)
  clean       (apaga apenas artefatos do projeto; não mexe no pub cache)
  installer   (Windows, Inno Setup no PATH)
''';

Future<void> main(List<String> args) async {
  final task = args.isEmpty ? 'help' : args.first;
  final rest = args.skip(1).toList(growable: false);
  switch (task) {
    case 'setup':
      await _preflight();
      for (final pkg in _packages) {
        await _run(_dart, ['pub', 'get'], cwd: pkg);
      }
      await _run(_flutter, ['pub', 'get'], cwd: 'app');
    case 'format':
      for (final pkg in _packages) {
        await _run(_dart, ['format', 'lib', 'test'], cwd: pkg);
      }
      await _run(_dart, ['format', 'tool'], cwd: 'packages/core');
      await _run(_dart, ['format', 'tool'], cwd: '.');
      await _run(_dart, ['format', 'lib', 'test'], cwd: 'app');
    case 'analyze':
      for (final pkg in _packages) {
        await _run(_dart, ['analyze'], cwd: pkg);
      }
      await _run(_dart, ['analyze', 'lib', 'test'], cwd: 'app');
    case 'test':
      for (final pkg in _packages) {
        await _run(_dart, ['test'], cwd: pkg);
      }
      await _run(_flutter, ['test'], cwd: 'app');
    case 'build-windows':
      await _run(_flutter, ['build', 'windows', '--release'], cwd: 'app');
    case 'build-macos':
      await _run(_flutter, ['build', 'macos', '--release'], cwd: 'app');
    case 'build-linux':
      await _run(_flutter, ['build', 'linux', '--release'], cwd: 'app');
    case 'run-windows':
      await _run(_flutter, ['run', '-d', 'windows'], cwd: 'app');
    case 'run-macos':
      await _run(_flutter, ['run', '-d', 'macos'], cwd: 'app');
    case 'run-linux':
      await _run(_flutter, ['run', '-d', 'linux'], cwd: 'app');
    case 'cli':
      await _run(_dart, [
        'run',
        'bin/qdeck.dart',
        ...rest,
      ], cwd: 'packages/cli');
    case 'bump':
      await _bump(rest);
    case 'clean':
      await _clean();
    case 'installer':
      if (!Platform.isWindows) {
        stderr.writeln(
          'O alvo installer usa Inno Setup no Windows. '
          'Rode em uma máquina Windows ou use o zip de build.',
        );
        exit(64);
      }
      await _run('iscc', [
        '/DMyAppVersion=${await _version()}',
        '/DSourceDir=${Directory.current.path}\\app\\build\\windows\\x64\\runner\\Release',
        'installer\\quota_deck.iss',
      ]);
    case 'help':
      stdout.writeln(_usage);
    default:
      stderr.writeln('Tarefa desconhecida: $task');
      stderr.writeln();
      stderr.writeln(_usage);
      exit(64);
  }
}

String get _dart => Platform.isWindows ? 'dart.exe' : 'dart';
String get _flutter => Platform.isWindows ? 'flutter.bat' : 'flutter';

Future<String> _version() async {
  final content = await File('app/pubspec.yaml').readAsString();
  final match = RegExp(
    r'^version:\s*([0-9.]+)',
    multiLine: true,
  ).firstMatch(content);
  if (match == null) return '0.0.0';
  return match.group(1)!;
}

/// Avisos de pré-requisito: `setup` não deve falhar por causa disso, mas
/// também não deve fingir que o build vai funcionar.
Future<void> _preflight() async {
  if (Platform.isMacOS) {
    final hasXcode = await _succeeds('xcodebuild', ['-version']);
    if (!hasXcode) {
      stderr.writeln(
        'aviso: Xcode completo não encontrado. `dart`/testes funcionam, '
        'mas `build-macos` vai falhar (instale Xcode e rode '
        '`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`).',
      );
    } else {
      final hasPods = await _succeeds('pod', ['--version']);
      if (!hasPods && Directory('app/macos/Pods').existsSync()) {
        stderr.writeln(
          'aviso: CocoaPods não encontrado; o build macOS pode falhar.',
        );
      }
    }
  }
  if (Platform.isLinux) {
    for (final tool in ['cmake', 'ninja', 'pkg-config']) {
      if (!await _succeeds(tool, ['--version'])) {
        stderr.writeln('aviso: $tool não encontrado; build-linux vai falhar.');
      }
    }
  }
}

Future<bool> _succeeds(String executable, List<String> args) async {
  try {
    final result = await Process.run(executable, args);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Atualiza a versão em todos os lugares que a exibem.
///
/// Fonte única de verdade: `app/pubspec.yaml`. Esta tarefa propaga para os
/// pacotes, para as constantes usadas em runtime e para o `pubspec.lock`.
Future<void> _bump(List<String> args) async {
  final version = args.isEmpty ? '' : args.first;
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
    stderr.writeln('uso: dart tool/tasks.dart bump 0.7.1 [build]');
    exit(64);
  }

  final appPubspec = File('app/pubspec.yaml');
  final current = RegExp(
    r'^version:\s*([0-9.]+)\+?(\d+)?',
    multiLine: true,
  ).firstMatch(appPubspec.readAsStringSync());
  final nextBuild = args.length > 1
      ? args[1]
      : '${(int.tryParse(current?.group(2) ?? '0') ?? 0) + 1}';

  void writeVersion(File file, Pattern from, String to) {
    final text = file.readAsStringSync();
    final updated = text.replaceFirst(from, to);
    if (updated == text) {
      stderr.writeln('aviso: nada para trocar em ${file.path}');
    }
    file.writeAsStringSync(updated);
  }

  writeVersion(
    appPubspec,
    RegExp(r'^version:\s*.*$', multiLine: true),
    'version: $version+$nextBuild',
  );
  writeVersion(
    File('app/lib/src/version.dart'),
    RegExp(r"const String appVersion = '[^']*';"),
    "const String appVersion = '$version';",
  );
  for (final pkg in _packages) {
    writeVersion(
      File('$pkg/pubspec.yaml'),
      RegExp(r'^version:\s*.*$', multiLine: true),
      'version: $version',
    );
  }
  writeVersion(
    File('packages/cli/lib/src/version.dart'),
    RegExp(r"const String cliVersion = '[^']*';"),
    "const String cliVersion = '$version';",
  );

  // O lockfile do app carrega a versão dos path deps.
  await _run(_flutter, ['pub', 'get'], cwd: 'app');
  for (final pkg in _packages) {
    await _run(_dart, ['pub', 'get'], cwd: pkg);
  }

  stdout.writeln(
    'versão $version+$nextBuild aplicada em app, models, core e cli.\n'
    'Falta atualizar o CHANGELOG.md.',
  );
}

Future<void> _clean() async {
  for (final path in _artifacts) {
    final directory = Directory(path);
    final file = File(path);
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
      stdout.writeln('removido $path');
    } else if (file.existsSync()) {
      await file.delete();
      stdout.writeln('removido $path');
    }
  }
  stdout.writeln(
    'Artefatos do projeto removidos. O pub cache global foi preservado '
    '(use `dart pub cache clean` se realmente quiser limpá-lo).',
  );
}

Future<void> _run(String executable, List<String> args, {String? cwd}) async {
  final label = cwd == null ? executable : '$cwd> $executable';
  stdout.writeln('> $label ${args.join(' ')}');
  final process = await Process.start(
    executable,
    args,
    workingDirectory: cwd,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) exit(code);
}
