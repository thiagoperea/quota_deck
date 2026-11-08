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
    final e = env ?? Platform.environment;
    final override = e['QDECK_OPENCODE_DB'];
    if (override != null && override.isNotEmpty) return File(override);
    final home = e['HOME'] ?? e['USERPROFILE'] ?? '';
    if (Platform.isWindows) {
      final localAppData = e['LOCALAPPDATA'];
      final base = localAppData != null && localAppData.isNotEmpty
          ? p.join(localAppData, 'opencode')
          : p.join(home, 'AppData', 'Local', 'opencode');
      return File(p.join(base, 'opencode.db'));
    }
    final xdg = e['XDG_DATA_HOME'];
    final base = xdg != null && xdg.isNotEmpty
        ? p.join(xdg, 'opencode')
        : p.join(home, '.local', 'share', 'opencode');
    return File(p.join(base, 'opencode.db'));
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
}
