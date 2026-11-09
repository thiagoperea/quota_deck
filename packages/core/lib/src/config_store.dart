import 'dart:convert';
import 'dart:io';

import 'package:quota_deck_models/quota_deck_models.dart';

class ConfigStore {
  final File file;
  AppConfig? _config;

  ConfigStore(this.file);

  AppConfig get current => _config ?? AppConfig.defaults();

  File get _backup => File('${file.path}.bak');

  Future<AppConfig> load({bool force = false}) async {
    if (_config != null && !force) return _config!;
    if (!await file.exists()) {
      _config = AppConfig.defaults();
      return _config!;
    }
    try {
      _config = _decode(await file.readAsString());
    } catch (_) {
      // Arquivo principal corrompido: tenta o backup antes de cair no default.
      try {
        if (await _backup.exists()) {
          _config = _decode(await _backup.readAsString());
        }
      } catch (_) {
        _config = null;
      }
      _config ??= AppConfig.defaults();
    }
    return _config!;
  }

  AppConfig _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return AppConfig.fromJson(decoded);
    }
    if (decoded is Map) {
      return AppConfig.fromJson(decoded.cast<String, dynamic>());
    }
    throw const FormatException('config.json sem objeto');
  }

  /// Escrita atômica (tmp -> fsync -> rename) com backup `.bak`.
  /// Só atualiza o estado em memória depois do rename dar certo; falhas
  /// propagam para a UI em vez de serem engolidas.
  Future<AppConfig> save(AppConfig config) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', tmp.path]);
      } catch (_) {}
    }
    if (await file.exists()) {
      try {
        if (await _backup.exists()) await _backup.delete();
        await file.copy(_backup.path);
      } catch (_) {
        // Backup é best-effort; não impede salvar o principal.
      }
      await file.delete();
    }
    await tmp.rename(file.path);
    _config = config;
    return config;
  }
}
