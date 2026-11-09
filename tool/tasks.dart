import 'dart:io';

const _packages = ['packages/models', 'packages/core', 'packages/cli'];

Future<void> main(List<String> args) async {
  final task = args.isEmpty ? 'help' : args.first;
  final rest = args.skip(1).toList(growable: false);
  switch (task) {
    case 'setup':
      for (final pkg in _packages) {
        await _run(_dart, ['pub', 'get'], cwd: pkg);
      }
      await _run(_flutter, ['pub', 'get'], cwd: 'app');
    case 'format':
      for (final pkg in _packages) {
        await _run(_dart, ['format', 'lib', 'test'], cwd: pkg);
      }
      await _run(_dart, ['format', 'tool'], cwd: 'packages/core');
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
    case 'installer':
      await _run('iscc', [
        '/DMyAppVersion=${await _version()}',
        '/DSourceDir=${Directory.current.path}\\app\\build\\windows\\x64\\runner\\Release',
        'installer\\quota_deck.iss',
      ]);
    case 'help':
    default:
      stdout.writeln('''
qdeck tasks:
  setup | format | analyze | test
  build-windows | build-macos | build-linux
  run-windows | run-macos | run-linux
  cli -- <args>
  installer   (Windows, Inno Setup no PATH)
''');
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
