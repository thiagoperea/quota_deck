import 'package:http/http.dart' as http_lib;
import 'package:quota_deck_models/quota_deck_models.dart';

import 'discovery.dart';
import 'errors.dart';
import 'paths.dart';
import 'process_runner.dart';

class ProviderContext {
  final AppPaths paths;
  final http_lib.Client http;
  final ProcessRunner process;
  final Map<String, String> env;
  final DateTime Function() now;
  final void Function(String message) log;
  final SystemDiscovery discovery;

  ProviderContext({
    required this.paths,
    required this.http,
    required this.process,
    required this.env,
    required this.now,
    required this.log,
    SystemDiscovery? discovery,
  }) : discovery = discovery ?? SystemDiscovery(process, env: env);
}

abstract class ProviderAdapter {
  ProviderId get id;

  /// Nunca faz rede e nunca lança.
  Future<DetectionResult> detect(ProviderContext ctx);

  /// Lê a quota; lança [QdeckException] em erro.
  Future<ProviderSnapshot> read(ProviderContext ctx);

  /// Diagnóstico sem expor segredos.
  Future<List<DoctorCheck>> doctor(ProviderContext ctx);
}
