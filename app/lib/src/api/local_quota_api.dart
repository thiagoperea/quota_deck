import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import 'quota_api.dart';

/// Implementação desktop: o core roda no mesmo processo do app.
///
/// Não há daemon, porta, cookie ou token. O app lê credenciais e SQLite
/// diretamente, como a CLI.
class LocalQuotaApi implements QuotaApi {
  LocalQuotaApi({this.paths, this.serviceFactory});

  final AppPaths? paths;
  final Future<QuotaService> Function(AppPaths paths)? serviceFactory;

  Future<QuotaService>? _serviceFuture;
  AppPaths? _resolvedPaths;

  Future<QuotaService> _service() {
    final existing = _serviceFuture;
    if (existing != null) return existing;

    final resolved = paths ?? AppPaths.forPlatform();
    _resolvedPaths = resolved;
    final future =
        serviceFactory?.call(resolved) ??
        DefaultQuotaService.create(paths: resolved);
    _serviceFuture = future;
    return future;
  }

  @override
  Future<SummaryPayload> fetchSummary() async {
    final service = await _service();
    final envelope = await service.snapshot();
    final config = await service.getConfig();
    final paths = _resolvedPaths!;
    return SummaryPayload(
      envelope: envelope,
      config: config,
      meta: ApiMeta(
        version: '0.1.0',
        dataDir: paths.maskedDataDir,
        providers: [
          for (final provider in ProviderId.values)
            ApiProviderInfo(id: provider, name: provider.displayName),
        ],
      ),
    );
  }

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) async {
    final service = await _service();
    return service.refresh(provider: provider);
  }

  @override
  Future<List<DoctorCheck>> fetchDoctor() async {
    final service = await _service();
    return service.doctor();
  }

  @override
  Future<HistorySummary> fetchHistory({
    required ProviderId provider,
    required String windowId,
    int hours = 24,
  }) async {
    final service = await _service();
    return service.history(
      provider: provider,
      windowId: windowId,
      window: Duration(hours: hours),
    );
  }

  @override
  Future<AppConfig> fetchSettings() async {
    final service = await _service();
    return service.getConfig();
  }

  @override
  Future<AppConfig> saveSettings(AppConfig config) async {
    final service = await _service();
    return service.updateConfig(config);
  }

  @override
  void close() {
    final future = _serviceFuture;
    if (future != null) {
      future.then((service) => service.dispose()).catchError((_) {});
    }
  }
}
