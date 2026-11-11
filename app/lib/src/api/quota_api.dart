import 'package:quota_deck_models/quota_deck_models.dart';

/// Erro amigável para falhas do core.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiProviderInfo {
  const ApiProviderInfo({required this.id, required this.name});

  final ProviderId? id;
  final String name;
}

class ApiMeta {
  const ApiMeta({
    required this.version,
    this.schemaVersion = 1,
    this.dataDir,
    this.providers = const [],
  });

  final String version;
  final int schemaVersion;
  final String? dataDir;
  final List<ApiProviderInfo> providers;
}

class SummaryPayload {
  const SummaryPayload({
    required this.envelope,
    required this.config,
    required this.meta,
  });

  final SnapshotEnvelope envelope;
  final AppConfig config;
  final ApiMeta meta;
}

/// Contrato consumido pela UI. No desktop, [LocalQuotaApi] chama o core
/// em um isolate próprio; nos testes, um fake devolve dados sintéticos.
abstract class QuotaApi {
  Future<SummaryPayload> fetchSummary();

  Future<SnapshotEnvelope> refresh({ProviderId? provider});

  /// Descobre apps/binários instalados e credenciais legíveis, sem rede.
  Future<List<DetectionResult>> detect();

  Future<List<DoctorCheck>> fetchDoctor();

  Future<HistorySummary> fetchHistory({
    required ProviderId provider,
    required String windowId,
    int hours = 24,
  });

  Future<AppConfig> fetchSettings();

  Future<AppConfig> saveSettings(AppConfig config);

  Future<void> close() async {}
}
