import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'process_runner.dart';

/// Sondas locais baratas (sem rede) para descobrir o que está instalado.
class SystemDiscovery {
  SystemDiscovery(this.process, {this.env, this.now});

  final ProcessRunner process;
  final Map<String, String>? env;
  final DateTime Function()? now;

  Future<Set<String>>? _running;
  DateTime? _runningAt;
  final Map<String, Future<String?>> _which = {};

  /// Esquece tudo que foi descoberto: usado pelo "Verificar agora", que
  /// precisa ver binários instalados depois da abertura do app.
  void invalidate() {
    _running = null;
    _runningAt = null;
    _which.clear();
  }

  Future<Set<String>> runningProcesses({
    Duration ttl = const Duration(minutes: 5),
  }) {
    final clock = now?.call() ?? DateTime.now();
    final current = _running;
    if (current != null &&
        _runningAt != null &&
        clock.difference(_runningAt!) <= ttl) {
      return current;
    }
    _runningAt = clock;
    return _running = _listRunning().catchError((_) => <String>{});
  }

  Future<Set<String>> _listRunning() async {
    try {
      if (Platform.isWindows) {
        final result = await process.run('tasklist', [
          '/FO',
          'CSV',
          '/NH',
        ], timeout: const Duration(seconds: 5));
        if (!result.ok) return <String>{};
        final names = <String>{};
        for (final line in result.stdout.split(RegExp(r'\r?\n'))) {
          final match = RegExp(r'^"([^"]+)"').firstMatch(line.trim());
          if (match == null) continue;
          var name = match.group(1)!.toLowerCase();
          if (name.endsWith('.exe')) {
            name = name.substring(0, name.length - 4);
          }
          names.add(name);
        }
        return names;
      }
      final result = await process.run('ps', [
        '-A',
        '-o',
        'comm=',
      ], timeout: const Duration(seconds: 5));
      if (!result.ok) return <String>{};
      return result.stdout
          .split(RegExp(r'\r?\n'))
          .map((line) => p.basename(line.trim()).toLowerCase())
          .where((line) => line.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<bool> isRunning(Iterable<String> names) async {
    final running = await runningProcesses();
    for (final name in names) {
      final needle = name.toLowerCase();
      for (final proc in running) {
        if (proc == needle || proc.startsWith('$needle.')) return true;
      }
    }
    return false;
  }

  /// Procura `Nome.app` em /Applications e ~/Applications.
  ///
  /// Diretório de configuração do app **não** conta como instalação: sobra de
  /// uma instalação antiga fazia o app aparecer como "instalado".
  Future<bool> hasAppBundle(Iterable<String> names) async {
    final home = env?['HOME'] ?? Platform.environment['HOME'] ?? '';
    final roots = <Directory>[
      Directory('/Applications'),
      if (home.isNotEmpty) Directory(p.join(home, 'Applications')),
    ];
    for (final root in roots) {
      for (final name in names) {
        final bundle = Directory(p.join(root.path, '$name.app'));
        if (bundle.existsSync()) return true;
      }
    }
    return false;
  }

  Future<String?> which(String name) => _which[name] ??= _whichImpl(name);

  Future<String?> _whichImpl(String name) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await process.run(cmd, [
        name,
      ], timeout: const Duration(seconds: 5));
      if (!result.ok) return null;
      for (final line in result.stdout.split(RegExp(r'\r?\n'))) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> firstBinary(Iterable<String> names) async {
    for (final name in names) {
      final path = await which(name);
      if (path != null) return path;
    }
    return null;
  }

  static String? readJsonVersion(File file) {
    try {
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map && decoded['version'] is String) {
        return decoded['version'] as String;
      }
    } catch (_) {}
    return null;
  }

  static String? versionInAppDir(Directory dir) {
    if (!dir.existsSync()) return null;
    for (final candidate in [
      p.join(dir.path, 'package.json'),
      p.join(dir.path, 'resources', 'app', 'package.json'),
      p.join(dir.path, 'app', 'package.json'),
    ]) {
      final version = readJsonVersion(File(candidate));
      if (version != null) return version;
    }
    return null;
  }
}
