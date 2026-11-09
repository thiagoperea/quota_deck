import 'dart:math' as math;

import 'package:quota_deck_models/quota_deck_models.dart';

import 'quota_api.dart';

/// API simulada com dados realistas dos quatro provedores.
///
/// Ativada por `--dart-define=QDECK_MOCK=1`. Serve para desenvolver e testar a
/// UI sem rede e sem credenciais.
class MockApi implements QuotaApi {
  MockApi({
    this.failSummary = false,
    this.failRefresh = false,
    this.failSettings = false,
    this.empty = false,
    this.installedProviders,
    AppConfig? config,
  }) : _config =
           config ??
           AppConfig.defaults().copyWith(
             theme: 'dark',
             refreshSeconds: 60,
             notificationsEnabled: true,
           ) {
    _envelope = _buildEnvelope(DateTime.now().toUtc());
  }

  final bool failSummary;
  final bool failRefresh;
  final bool failSettings;
  final bool empty;
  final Set<ProviderId>? installedProviders;

  AppConfig _config;
  late SnapshotEnvelope _envelope;
  int _refreshCount = 0;

  static const _version = '0.3.0';
  static const _dataDir = '~/Library/Application Support/QuotaDeck';

  @override
  Future<SummaryPayload> fetchSummary() async {
    if (failSummary) {
      throw const ApiException(
        'Falha simulada ao carregar o resumo. Tente novamente.',
      );
    }
    return SummaryPayload(
      envelope: _envelope,
      config: _config,
      meta: const ApiMeta(
        version: _version,
        dataDir: _dataDir,
        providers: [
          ApiProviderInfo(id: ProviderId.opencode, name: 'OpenCode'),
          ApiProviderInfo(id: ProviderId.antigravity, name: 'Antigravity'),
          ApiProviderInfo(id: ProviderId.codex, name: 'Codex'),
          ApiProviderInfo(id: ProviderId.claude, name: 'Claude'),
        ],
      ),
    );
  }

  @override
  Future<List<DetectionResult>> detect() async {
    if (empty) {
      return [
        for (final id in ProviderId.values)
          DetectionResult.fromSurfaces(
            provider: id,
            surfaces: const [
              SurfaceState(surface: ProviderSurface.desktop, installed: false),
              SurfaceState(surface: ProviderSurface.cli, installed: false),
            ],
          ),
      ];
    }
    return [
      for (final id in ProviderId.values)
        DetectionResult.fromSurfaces(
          provider: id,
          surfaces: [
            SurfaceState(
              surface: ProviderSurface.desktop,
              installed: _isInstalled(id),
              authenticated: _isInstalled(id) && !_hasError(id),
              version: _isInstalled(id) ? 'mock' : null,
              location: _isInstalled(id) ? '~/mock/${id.wireName}' : null,
              reason: _isInstalled(id)
                  ? 'Superfície simulada para testes de UI.'
                  : 'Não instalado (mock).',
            ),
            SurfaceState(
              surface: ProviderSurface.cli,
              installed: _isInstalled(id) && id != ProviderId.antigravity,
              authenticated:
                  _isInstalled(id) &&
                  id != ProviderId.antigravity &&
                  !_hasError(id),
              location: _isInstalled(id) ? 'mock-cli' : null,
              reason: 'CLI simulada.',
            ),
          ],
        ),
    ];
  }

  bool _isInstalled(ProviderId id) => installedProviders?.contains(id) ?? true;

  bool _hasError(ProviderId id) => _envelope.results
      .where((r) => r.provider == id)
      .any((r) => r.errors.isNotEmpty);

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) async {
    if (failRefresh) {
      throw const ApiException(
        'Falha simulada ao atualizar. Os dados anteriores continuam na tela.',
      );
    }

    _refreshCount++;
    final now = _envelope.generatedAt.add(const Duration(seconds: 60));
    final results = _envelope.results
        .map((snapshot) {
          if (provider != null && snapshot.provider != provider) {
            return snapshot;
          }
          if (snapshot.provider == ProviderId.claude) {
            return snapshot.copyWith(fetchedAt: now);
          }
          final windows = snapshot.windows
              .map((window) {
                final delta =
                    0.2 + ((_refreshCount + window.id.length) % 5) * 0.12;
                final used = clampPercent(window.usedPercent + delta);
                return window.copyWith(
                  usedPercent: used,
                  remainingPercent: clampPercent(100 - used),
                  status: statusForUsed(used),
                );
              })
              .toList(growable: false);
          return snapshot.copyWith(windows: windows, fetchedAt: now);
        })
        .toList(growable: false);

    _envelope = SnapshotEnvelope(
      generatedAt: now,
      results: results,
      errors: _envelope.errors,
    );
    return _envelope;
  }

  @override
  Future<List<DoctorCheck>> fetchDoctor() async => const [
    DoctorCheck(
      provider: ProviderId.opencode,
      id: 'credential',
      label: 'Credencial do OpenCode',
      status: DoctorStatus.ok,
      message: 'Credencial encontrada.',
    ),
    DoctorCheck(
      provider: ProviderId.antigravity,
      id: 'language-server',
      label: 'Language server do Antigravity',
      status: DoctorStatus.ok,
      message: 'RPC local disponível.',
    ),
    DoctorCheck(
      provider: ProviderId.codex,
      id: 'auth',
      label: 'Sessão do Codex',
      status: DoctorStatus.ok,
      message: 'Sessão válida.',
    ),
    DoctorCheck(
      provider: ProviderId.claude,
      id: 'auth',
      label: 'Sessão do Claude Code',
      status: DoctorStatus.warn,
      message: 'Token expirado; abra o Claude Code para renovar.',
    ),
  ];

  @override
  Future<HistorySummary> fetchHistory({
    required ProviderId provider,
    required String windowId,
    int hours = 24,
  }) async {
    final snapshot = _envelope.byProvider(provider);
    QuotaWindow? window;
    for (final candidate in snapshot?.windows ?? const <QuotaWindow>[]) {
      if (candidate.id == windowId) {
        window = candidate;
        break;
      }
    }
    final current = window?.usedPercent ?? 0;
    final now = DateTime.now().toUtc();
    final count = hours.clamp(2, 48).toInt();
    final samples = List<HistorySample>.generate(count, (index) {
      final hoursAgo = count - 1 - index;
      final wave = math.sin(index / 2.7) * 1.1;
      final value = clampPercent(current - (count - 1 - index) * 0.32 + wave);
      return HistorySample(
        provider: provider,
        windowId: windowId,
        usedPercent: value,
        fetchedAt: now.subtract(Duration(hours: hoursAgo)),
        stale: false,
      );
    });
    final burnRate = current > 4 ? 0.8 : 0.2;
    final eta = burnRate > 0.01 ? (100 - current) / burnRate : null;
    return HistorySummary(
      provider: provider,
      windowId: windowId,
      samples: samples,
      burnRatePerHour: burnRate,
      etaHours: eta,
    );
  }

  @override
  Future<AppConfig> fetchSettings() async => _config;

  @override
  Future<AppConfig> saveSettings(AppConfig config) async {
    if (failSettings) {
      throw const ApiException(
        'Falha simulada ao salvar as configurações. Tente novamente.',
      );
    }
    _config = config;
    return _config;
  }

  @override
  Future<void> close() async {}

  SnapshotEnvelope _buildEnvelope(DateTime now) {
    if (empty) {
      return SnapshotEnvelope(
        generatedAt: now,
        results: const [],
        errors: const [
          QdeckErrorInfo(
            code: 'AUTH_MISSING',
            message: 'Nenhuma credencial local foi encontrada. Entre em um provedor para começar.',
          ),
        ],
      );
    }

    return SnapshotEnvelope(
      generatedAt: now,
      results: [
        _opencode(now).copyWith(
          surface: ProviderSurface.desktop,
          sourceId: 'opencode-usage-api',
        ),
        _antigravity(now).copyWith(
          surface: ProviderSurface.desktop,
          sourceId: 'antigravity-language-server',
        ),
        _codex(now).copyWith(
          surface: ProviderSurface.desktop,
          sourceId: 'codex-wham-usage',
        ),
        _claude(now).copyWith(
          surface: ProviderSurface.cli,
          sourceId: 'claude-oauth-usage',
        ),
      ],
      errors: const [],
    );
  }

  ProviderSnapshot _opencode(DateTime now) => ProviderSnapshot(
    provider: ProviderId.opencode,
    account: const AccountInfo(label: 'OpenCode Go', plan: 'Go'),
    windows: [
      QuotaWindow(
        id: 'rolling-5h',
        label: 'Rolling 5h',
        kind: WindowKind.rolling,
        usedPercent: 4,
        remainingPercent: 96,
        resetsAt: now.add(const Duration(hours: 4, minutes: 45)),
        status: QuotaStatus.ok,
        source: SourceKind.api,
      ),
      QuotaWindow(
        id: 'weekly',
        label: 'Semanal (7d)',
        kind: WindowKind.weekly,
        usedPercent: 21,
        remainingPercent: 79,
        resetsAt: now.add(const Duration(hours: 8)),
        status: QuotaStatus.ok,
        source: SourceKind.api,
      ),
      QuotaWindow(
        id: 'monthly',
        label: 'Mensal (30d)',
        kind: WindowKind.monthly,
        usedPercent: 16,
        remainingPercent: 84,
        resetsAt: now.add(const Duration(days: 12, hours: 19)),
        status: QuotaStatus.ok,
        source: SourceKind.api,
      ),
    ],
    source: 'opencode-usage-api',
    fetchedAt: now,
    confidence: Confidence.high,
  );

  ProviderSnapshot _antigravity(DateTime now) => ProviderSnapshot(
    provider: ProviderId.antigravity,
    account: const AccountInfo(
      label: 'Antigravity',
      plan: 'Pro',
      maskedEmail: 'us***@example.com',
    ),
    windows: [
      QuotaWindow(
        id: 'gemini-5h',
        label: '5 horas',
        kind: WindowKind.session,
        group: 'Gemini Models',
        usedPercent: 12,
        remainingPercent: 88,
        resetsAt: now.add(const Duration(hours: 3, minutes: 23)),
        status: QuotaStatus.ok,
        source: SourceKind.rpc,
      ),
      QuotaWindow(
        id: 'gemini-weekly',
        label: 'Semanal (7d)',
        kind: WindowKind.weekly,
        group: 'Gemini Models',
        usedPercent: 4.2,
        remainingPercent: 95.8,
        resetsAt: now.add(const Duration(days: 7, hours: 3)),
        status: QuotaStatus.ok,
        source: SourceKind.rpc,
      ),
      QuotaWindow(
        id: '3p-5h',
        label: '5 horas',
        kind: WindowKind.session,
        group: 'Claude and GPT models',
        usedPercent: 0,
        remainingPercent: 100,
        resetsAt: now.add(const Duration(hours: 3, minutes: 23)),
        status: QuotaStatus.ok,
        source: SourceKind.rpc,
      ),
      QuotaWindow(
        id: '3p-weekly',
        label: 'Semanal (7d)',
        kind: WindowKind.weekly,
        group: 'Claude and GPT models',
        usedPercent: 0,
        remainingPercent: 100,
        resetsAt: now.add(const Duration(days: 7, hours: 4)),
        status: QuotaStatus.ok,
        source: SourceKind.rpc,
      ),
    ],
    credits: const CreditsInfo(
      hasCredits: true,
      unlimited: false,
      balance: 500,
      currency: 'prompt-credits',
      note: 'availablePromptCredits',
    ),
    source: 'antigravity-language-server',
    fetchedAt: now,
    confidence: Confidence.high,
  );

  ProviderSnapshot _codex(DateTime now) => ProviderSnapshot(
    provider: ProviderId.codex,
    account: const AccountInfo(
      label: 'Codex',
      plan: 'plus',
      maskedEmail: 'us***@example.com',
    ),
    windows: [
      QuotaWindow(
        id: 'primary-5h',
        label: '5 horas',
        kind: WindowKind.session,
        usedPercent: 0,
        remainingPercent: 100,
        resetsAt: now.add(const Duration(hours: 5, minutes: 12)),
        status: QuotaStatus.ok,
        source: SourceKind.appServer,
      ),
      QuotaWindow(
        id: 'secondary-7d',
        label: 'Semanal (7d)',
        kind: WindowKind.weekly,
        usedPercent: 2,
        remainingPercent: 98,
        resetsAt: now.add(const Duration(days: 4, hours: 12)),
        status: QuotaStatus.ok,
        source: SourceKind.appServer,
      ),
    ],
    credits: const CreditsInfo(
      hasCredits: false,
      unlimited: false,
      balance: 0,
      currency: 'USD',
      note: '2 resets disponíveis',
    ),
    source: 'codex-wham-usage',
    fetchedAt: now,
    confidence: Confidence.high,
  );

  ProviderSnapshot _claude(DateTime now) => ProviderSnapshot(
    provider: ProviderId.claude,
    account: const AccountInfo(label: 'Claude Code', plan: 'pro'),
    windows: [
      QuotaWindow(
        id: 'five-hour',
        label: '5 horas',
        kind: WindowKind.session,
        usedPercent: 12,
        remainingPercent: 88,
        resetsAt: now.add(const Duration(hours: 2)),
        status: QuotaStatus.ok,
        source: SourceKind.cache,
      ),
      QuotaWindow(
        id: 'seven-day',
        label: 'Semanal (7d)',
        kind: WindowKind.weekly,
        usedPercent: 40,
        remainingPercent: 60,
        resetsAt: now.add(const Duration(days: 6, hours: 20)),
        status: QuotaStatus.ok,
        source: SourceKind.cache,
      ),
    ],
    source: 'claude-oauth-usage',
    fetchedAt: now.subtract(const Duration(hours: 2)),
    stale: true,
    confidence: Confidence.low,
    errors: const [
      QdeckErrorInfo(
        code: 'AUTH_EXPIRED',
        message: 'Token do Claude Code expirado. Abra o Claude Code para renovar; os outros provedores continuam funcionando.',
      ),
    ],
  );
}
