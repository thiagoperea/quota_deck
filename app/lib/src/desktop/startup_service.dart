import 'dart:io';

/// Registra/remove o QuotaDeck da inicialização automática do sistema.
///
/// Windows: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
/// macOS: LaunchAgent em `~/Library/LaunchAgents`
/// Linux: `.desktop` em `~/.config/autostart`
///
/// O app é iniciado com `--startup` para abrir só na bandeja.
class StartupService {
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'QuotaDeck';
  static const _launchAgent = 'com.quotaDeck.app.plist';
  static const _linuxDesktop = 'quota-deck.desktop';

  static Future<bool> setEnabled(bool enabled) async {
    try {
      if (Platform.isWindows) return await _setWindows(enabled);
      if (Platform.isMacOS) return await _setMacOs(enabled);
      if (Platform.isLinux) return await _setLinux(enabled);
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('reg', [
          'query',
          _runKey,
          '/v',
          _valueName,
        ]);
        return result.exitCode == 0;
      }
      if (Platform.isMacOS) {
        return _macPlist.existsSync();
      }
      if (Platform.isLinux) {
        return _linuxAutostart.existsSync();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _setWindows(bool enabled) async {
    if (!enabled) {
      await Process.run('reg', ['delete', _runKey, '/v', _valueName, '/f']);
      return true;
    }
    final command = '"${Platform.resolvedExecutable}" --startup';
    final result = await Process.run('reg', [
      'add',
      _runKey,
      '/v',
      _valueName,
      '/t',
      'REG_SZ',
      '/d',
      command,
      '/f',
    ]);
    return result.exitCode == 0;
  }

  static File get _macPlist {
    final home = Platform.environment['HOME'] ?? '';
    return File('$home/Library/LaunchAgents/$_launchAgent');
  }

  static Future<bool> _setMacOs(bool enabled) async {
    final file = _macPlist;
    if (!enabled) {
      await Process.run('launchctl', ['unload', '-w', file.path]);
      if (await file.exists()) await file.delete();
      return true;
    }
    await file.parent.create(recursive: true);
    final exe = _xmlEscape(Platform.resolvedExecutable);
    await file.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.quotaDeck.app</string>
  <key>ProgramArguments</key>
  <array>
    <string>$exe</string>
    <string>--startup</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''');
    await Process.run('launchctl', ['load', '-w', file.path]);
    return true;
  }

  static File get _linuxAutostart {
    final home = Platform.environment['HOME'] ?? '';
    return File('$home/.config/autostart/$_linuxDesktop');
  }

  static Future<bool> _setLinux(bool enabled) async {
    final file = _linuxAutostart;
    if (!enabled) {
      if (await file.exists()) await file.delete();
      return true;
    }
    await file.parent.create(recursive: true);
    final exe = Platform.resolvedExecutable.replaceAll('"', r'\"');
    await file.writeAsString('''[Desktop Entry]
Type=Application
Name=QuotaDeck
Comment=Painel local de quotas dos provedores de IA
Exec="$exe" --startup
Terminal=false
X-GNOME-Autostart-enabled=true
''');
    return true;
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
