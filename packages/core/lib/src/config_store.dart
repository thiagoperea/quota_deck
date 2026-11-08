import 'dart:convert';
import 'dart:io';

import 'package:quota_deck_models/quota_deck_models.dart';

class ConfigStore {
  final File file;
  AppConfig? _config;

  ConfigStore(this.file);

  AppConfig get current => _config ?? AppConfig.defaults();

  Future<AppConfig> load({bool force = false}) async {
    if (_config != null && !force) return _config!;
    if (!await file.exists()) {
      _config = AppConfig.defaults();
      return _config!;
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      _config = raw is Map<String, dynamic>
          ? AppConfig.fromJson(raw)
          : AppConfig.defaults();
    } catch (_) {
      _config = AppConfig.defaults();
    }
    return _config!;
  }

  Future<void> save(AppConfig config) async {
    _config = config;
    try {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config.toJson()),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['600', file.path]);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
