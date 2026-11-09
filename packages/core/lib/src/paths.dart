import 'dart:io';

import 'package:path/path.dart' as p;

class AppPaths {
  final Directory dataDir;

  const AppPaths(this.dataDir);

  File get cacheFile => File(p.join(dataDir.path, 'cache.json'));
  File get historyDb => File(p.join(dataDir.path, 'history.db'));
  File get configFile => File(p.join(dataDir.path, 'config.json'));
  File get sessionFile => File(p.join(dataDir.path, 'session.json'));
  File get logFile => File(p.join(dataDir.path, 'quota-deck.log'));

  static AppPaths forPlatform({
    Map<String, String>? env,
    String? overrideDataDir,
  }) {
    final e = env ?? Platform.environment;
    final home = e['HOME'] ?? e['USERPROFILE'] ?? Directory.current.path;

    String dir;
    if (overrideDataDir != null && overrideDataDir.trim().isNotEmpty) {
      dir = overrideDataDir;
    } else if ((e['QDECK_DATA_DIR'] ?? '').trim().isNotEmpty) {
      dir = e['QDECK_DATA_DIR']!;
    } else if (Platform.isMacOS) {
      dir = p.join(home, 'Library', 'Application Support', 'QuotaDeck');
    } else if (Platform.isWindows) {
      final appData = e['APPDATA'];
      dir = appData != null && appData.isNotEmpty
          ? p.join(appData, 'QuotaDeck')
          : p.join(home, 'AppData', 'Roaming', 'QuotaDeck');
    } else if (Platform.isLinux) {
      final xdg = e['XDG_DATA_HOME'];
      dir = xdg != null && xdg.isNotEmpty
          ? p.join(xdg, 'quota-deck')
          : p.join(home, '.local', 'share', 'quota-deck');
    } else {
      dir = p.join(home, '.quota-deck');
    }
    return AppPaths(Directory(p.normalize(dir)));
  }

  Future<void> ensure() async {
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['700', dataDir.path]);
      } catch (_) {}
    }
  }

  String get maskedDataDir => maskPath(dataDir.path);

  static String maskPath(String path, {Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    if (home.isNotEmpty && path.startsWith(home)) {
      return path.replaceFirst(home, '~');
    }
    return path;
  }

  static File openCodeDb({Map<String, String>? env}) {
    final candidates = openCodeDbs(env: env);
    for (final candidate in candidates) {
      if (candidate.existsSync()) return candidate;
    }
    return candidates.first;
  }

  /// O OpenCode 2.x grava em XDG (`~/.local/share/opencode`) mesmo no Windows;
  /// builds antigos usavam `%LOCALAPPDATA%`. Ordem: override, XDG, legado.
  static List<File> openCodeDbs({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    final files = <File>[];

    final override = e['QDECK_OPENCODE_DB'];
    if (override != null && override.isNotEmpty) files.add(File(override));

    final xdg = e['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) {
      files.add(File(p.join(xdg, 'opencode', 'opencode.db')));
    }
    files.add(File(p.join(home, '.local', 'share', 'opencode', 'opencode.db')));

    final localAppData = e['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      files.add(File(p.join(localAppData, 'opencode', 'opencode.db')));
    }
    files.add(
      File(p.join(home, 'AppData', 'Local', 'opencode', 'opencode.db')),
    );

    final appData = e['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      files.add(File(p.join(appData, 'opencode', 'opencode.db')));
    }
    files.add(
      File(p.join(home, 'AppData', 'Roaming', 'opencode', 'opencode.db')),
    );

    final seen = <String>{};
    return files.where((f) => seen.add(f.path)).toList(growable: false);
  }

  static File codexAuth({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final override = e['QDECK_CODEX_AUTH'];
    if (override != null && override.isNotEmpty) return File(override);
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    final codexHome = e['CODEX_HOME'];
    final base = codexHome != null && codexHome.isNotEmpty
        ? codexHome
        : p.join(home, '.codex');
    return File(p.join(base, 'auth.json'));
  }

  static File claudeCredentials({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final override = e['QDECK_CLAUDE_CREDS'];
    if (override != null && override.isNotEmpty) return File(override);
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    final configDir = e['CLAUDE_CONFIG_DIR'];
    final base = configDir != null && configDir.isNotEmpty
        ? configDir
        : p.join(home, '.claude');
    return File(p.join(base, '.credentials.json'));
  }

  static Directory antigravityDaemonDir({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    return Directory(p.join(home, '.gemini', 'antigravity', 'daemon'));
  }

  static File antigravityToken({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    return File(p.join(home, '.gemini', 'jetski-standalone-oauth-token'));
  }

  /// Diretórios de dados do Claude Desktop (Electron/MSIX).
  static List<Directory> claudeDesktopDirs({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    final dirs = <Directory>[];

    final localAppData = e['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      final dataRoot = Directory(p.join(localAppData, 'Claude-Data'));
      if (dataRoot.existsSync()) {
        for (final entry in dataRoot.listSync(followLinks: false)) {
          if (entry is Directory &&
              p.basename(entry.path).startsWith('claude_')) {
            dirs.add(entry);
          }
        }
      }
      if (dirs.isEmpty) dirs.add(dataRoot);
    }
    dirs.add(Directory(p.join(home, 'AppData', 'Local', 'Claude-Data')));

    if (Platform.isMacOS) {
      dirs.add(
        Directory(p.join(home, 'Library', 'Application Support', 'Claude')),
      );
    } else if (Platform.isLinux) {
      dirs.add(Directory(p.join(home, '.config', 'Claude')));
    }

    final seen = <String>{};
    return dirs.where((d) => seen.add(d.path)).toList(growable: false);
  }

  /// Histórico de uso que o Claude Desktop grava localmente.
  static List<File> claudeDesktopUsageFiles({Map<String, String>? env}) {
    final files = <File>[];
    for (final dir in claudeDesktopDirs(env: env)) {
      files.add(File(p.join(dir.path, 'plan-usage-history.json')));
      files.add(File(p.join(dir.path, 'config.json')));
    }
    return files;
  }

  /// Binário do Claude Code empacotado dentro do Claude Desktop.
  static List<File> bundledClaudeBinaries({Map<String, String>? env}) {
    final e = env ?? Platform.environment;
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    final files = <File>[];
    final exe = Platform.isWindows ? 'claude.exe' : 'claude';
    for (final dir in claudeDesktopDirs(env: env)) {
      final cliRoot = Directory(p.join(dir.path, 'claude-code'));
      if (!cliRoot.existsSync()) continue;
      for (final version in cliRoot.listSync(followLinks: false)) {
        if (version is! Directory) continue;
        for (final hash in version.listSync(followLinks: false)) {
          if (hash is! Directory) continue;
          files.add(File(p.join(hash.path, exe)));
        }
      }
    }
    files.add(File(p.join(home, '.local', 'bin', exe)));
    return files;
  }
}
