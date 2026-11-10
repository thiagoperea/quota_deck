import 'dart:async';
import 'dart:math' as math;

import 'package:quota_deck_models/quota_deck_models.dart';

import '../version.dart';
import 'quota_api.dart';

/// Cenários de mock para validar todos os estados visuais do painel.
enum MockScenario {
  normal('Normal', 'Quatro provedores com dados realistas.'),
  statuses('Status', 'ok · warning · critical · limited · unknown.'),
  edgeCases(
    'Estados de card',
    'Auth, erro, stale, créditos, sem janelas e superfícies.',
  ),
  groups(
    'Grupos e textos longos',
    'Muitas janelas, grupos e rótulos compridos.',
  ),
  single(
    'Um provedor',
    'Só OpenCode, para testar o resumo com pouca densidade.',
  ),
  notInstalled('Não instalado', 'Quatro cards de ferramenta ausente.'),
  empty('Vazio', 'Onboarding sem nenhum provedor.'),
  error('Erro inicial', 'Falha ao carregar o resumo.'),
  loading('Carregando', 'Spinner infinito, sem dados.');

  const MockScenario(this.label, this.description);

  final String label;
  final String description;
}

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
    MockScenario? scenario,
    AppConfig? config,
  }) : _config =
           config ??
           AppConfig.defaults().copyWith(
             theme: 'dark',
             refreshSeconds: 60,
             notificationsEnabled: true,
           ),
       _scenario = MockScenario.normal {
    if (empty) {
      _scenario = MockScenario.empty;
    } else if (scenario != null) {
      _scenario = scenario;
    }
    _envelope = _buildEnvelope(DateTime.now().toUtc());
  }

  final bool failSummary;
  final bool failRefresh;
  final bool failSettings;
  final bool empty;
  final Set<ProviderId>? installedProviders;

  AppConfig _config;
  late SnapshotEnvelope _envelope;
  MockScenario _scenario;
  int _refreshCount = 0;

  MockScenario get scenario => _scenario;

  void setScenario(MockScenario value) {
    _scenario = value;
    _envelope = _buildEnvelope(DateTime.now().toUtc());
  }

  static const _version = appVersion;
  static const _dataDir = '~/Library/Application Support/QuotaDeck';

  @override
  Future<SummaryPayload> fetchSummary() async {
    if (_scenario == MockScenario.loading) {
      return Completer<SummaryPayload>().future;
    }
    if (failSummary || _scenario == MockScenario.error) {
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
    if (_scenario == MockScenario.empty ||
        _scenario == MockScenario.notInstalled) {
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

  bool _isInstalled(ProviderId id) {
    if (_scenario == MockScenario.empty ||
        _scenario == MockScenario.notInstalled) {
      return false;
    }
    if (_scenario == MockScenario.single) return id == ProviderId.opencode;
    return installedProviders?.contains(id) ?? true;
  }

  bool _hasError(ProviderId id) => _envelope.results
      .where((r) => r.provider == id)
      .any((r) => r.errors.isNotEmpty);

  @override
  Future<SnapshotEnvelope> refresh({ProviderId? provider}) async {
    if (_scenario == MockScenario.loading) {
      return Completer<SnapshotEnvelope>().future;
    }
    if (failRefresh || _scenario == MockScenario.error) {
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
    if (_scenario == MockScenario.empty) {
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

    return switch (_scenario) {
      MockScenario.normal => SnapshotEnvelope(
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
            surface: ProviderSurface.desktop,
            sourceId: 'claude-desktop-oauth',
          ),
        ],
        errors: const [],
      ),
      MockScenario.statuses => _statusEnvelope(now),
      MockScenario.edgeCases => _edgeEnvelope(now),
      MockScenario.groups => _groupsEnvelope(now),
      MockScenario.single => SnapshotEnvelope(
        generatedAt: now,
        results: [_opencode(now)],
        errors: const [],
      ),
      MockScenario.notInstalled => _notInstalledEnvelope(now),
      MockScenario.empty => SnapshotEnvelope(
        generatedAt: now,
        results: const [],
      ),
      // Os dados não importam para erro/loading: a falha vem do fetchSummary.
      MockScenario.error || MockScenario.loading => SnapshotEnvelope(
        generatedAt: now,
        results: const [],
      ),
    };
  }

  QuotaWindow _window(
    DateTime now,
    String id,
    String label,
    double used, {
    String? group,
    WindowKind kind = WindowKind.session,
    Duration? resetIn,
    bool noReset = false,
    QuotaStatus? status,
    SourceKind source = SourceKind.api,
  }) => QuotaWindow(
    id: id,
    label: label,
    kind: kind,
    group: group,
    usedPercent: used,
    remainingPercent: clampPercent(100 - used),
    resetsAt: noReset ? null : now.add(resetIn ?? _defaultReset(kind)),
    status: status ?? statusForUsed(used),
    source: source,
  );

  static Duration _defaultReset(WindowKind kind) => switch (kind) {
    WindowKind.rolling => const Duration(hours: 3, minutes: 48),
    WindowKind.session => const Duration(hours: 4, minutes: 37),
    WindowKind.weekly => const Duration(days: 6, hours: 7, minutes: 21),
    WindowKind.monthly => const Duration(days: 21, hours: 5, minutes: 13),
    WindowKind.model => const Duration(days: 5, hours: 14, minutes: 9),
    WindowKind.credits => const Duration(days: 18, hours: 2, minutes: 41),
    WindowKind.unknown => const Duration(days: 2, hours: 9, minutes: 44),
  };

  ProviderSnapshot _snapshot(
    DateTime now,
    ProviderId provider, {
    required String label,
    String? plan,
    String? email,
    required List<QuotaWindow> windows,
    ProviderSurface surface = ProviderSurface.desktop,
    String source = 'mock',
    String? sourceId,
    bool stale = false,
    Confidence confidence = Confidence.high,
    CreditsInfo? credits,
    List<QdeckErrorInfo> errors = const [],
    Duration age = Duration.zero,
  }) => ProviderSnapshot(
    provider: provider,
    account: AccountInfo(label: label, plan: plan, maskedEmail: email),
    windows: windows,
    credits: credits,
    source: source,
    sourceId: sourceId ?? source,
    surface: surface,
    fetchedAt: now.subtract(age),
    stale: stale,
    confidence: confidence,
    errors: errors,
  );

  ProviderSnapshot _errorSnapshot(
    DateTime now,
    ProviderId provider, {
    required String state,
    required String code,
    required String message,
    List<QuotaWindow> windows = const [],
    ProviderSurface surface = ProviderSurface.desktop,
    String source = 'error',
    bool stale = false,
    Confidence confidence = Confidence.none,
    CreditsInfo? credits,
  }) => _snapshot(
    now,
    provider,
    label: provider.displayName,
    plan: state,
    windows: windows,
    surface: surface,
    source: source,
    sourceId: source,
    stale: stale,
    confidence: confidence,
    credits: credits,
    errors: [QdeckErrorInfo(code: code, message: message, retryable: true)],
  );

  SnapshotEnvelope _statusEnvelope(DateTime now) => SnapshotEnvelope(
    generatedAt: now,
    results: [
      _snapshot(
        now,
        ProviderId.opencode,
        label: 'OpenCode Go',
        plan: 'Go',
        windows: [
          _window(now, 'rolling-ok', '5 horas', 42, kind: WindowKind.rolling),
          _window(
            now,
            'weekly-warning',
            'Semanal (7d)',
            83,
            kind: WindowKind.weekly,
          ),
          _window(
            now,
            'monthly-critical',
            'Mensal (30d)',
            96,
            kind: WindowKind.monthly,
          ),
          _window(
            now,
            'credits-limited',
            'Créditos',
            100,
            kind: WindowKind.credits,
            status: QuotaStatus.limited,
            source: SourceKind.cache,
          ),
        ],
      ),
      _snapshot(
        now,
        ProviderId.antigravity,
        label: 'Antigravity',
        plan: 'Pro',
        windows: [
          _window(now, 'gemini-5h', '5 horas', 79, group: 'Gemini Models'),
          _window(
            now,
            'gemini-weekly',
            'Semanal (7d)',
            95,
            group: 'Gemini Models',
            kind: WindowKind.weekly,
            status: QuotaStatus.critical,
          ),
          _window(
            now,
            '3p-5h',
            '5 horas',
            100,
            group: 'Claude and GPT models',
            status: QuotaStatus.limited,
          ),
          _window(
            now,
            '3p-weekly',
            'Semanal (7d)',
            0,
            group: 'Claude and GPT models',
            kind: WindowKind.weekly,
          ),
        ],
        source: 'antigravity-language-server',
        confidence: Confidence.high,
      ),
      _snapshot(
        now,
        ProviderId.codex,
        label: 'Codex',
        plan: 'plus',
        windows: [
          _window(
            now,
            'primary-5h',
            '5 horas',
            0,
            source: SourceKind.appServer,
          ),
          _window(
            now,
            'secondary-7d',
            'Semanal (7d)',
            80,
            kind: WindowKind.weekly,
            status: QuotaStatus.warning,
            source: SourceKind.appServer,
          ),
          _window(
            now,
            'headers-unknown',
            'Janela sem status',
            50,
            noReset: true,
            status: QuotaStatus.unknown,
            source: SourceKind.headers,
          ),
        ],
        source: 'codex-wham-usage',
        confidence: Confidence.medium,
      ),
      _snapshot(
        now,
        ProviderId.claude,
        label: 'Claude Desktop',
        plan: 'team',
        windows: [
          _window(
            now,
            'five-hour',
            '5 horas',
            95,
            status: QuotaStatus.critical,
            noReset: true,
          ),
          _window(
            now,
            'seven-day',
            'Semanal (7d)',
            100,
            kind: WindowKind.weekly,
            status: QuotaStatus.limited,
            noReset: true,
          ),
        ],
        source: 'claude-desktop-oauth',
        confidence: Confidence.high,
      ),
    ],
    errors: const [],
  );

  SnapshotEnvelope _edgeEnvelope(DateTime now) => SnapshotEnvelope(
    generatedAt: now,
    results: [
      _snapshot(
        now,
        ProviderId.opencode,
        label: 'OpenCode Go',
        plan: 'Go',
        windows: [
          _window(now, 'rolling', '5 horas', 4, kind: WindowKind.rolling),
          _window(now, 'weekly', 'Semanal (7d)', 21, kind: WindowKind.weekly),
          _window(now, 'monthly', 'Mensal (30d)', 16, kind: WindowKind.monthly),
        ],
        source: 'opencode-usage-api',
        sourceId: 'opencode-db',
        confidence: Confidence.medium,
      ),
      _snapshot(
        now,
        ProviderId.codex,
        label: 'Codex',
        plan: 'plus',
        windows: const [],
        source: 'codex-wham-usage',
        confidence: Confidence.medium,
      ),
      _snapshot(
        now,
        ProviderId.antigravity,
        label: 'Antigravity',
        plan: 'Ultra',
        windows: [
          _window(now, 'gemini-5h', '5 horas', 20, group: 'Gemini Models'),
          _window(
            now,
            'gemini-w',
            'Semanal (7d)',
            31,
            group: 'Gemini Models',
            kind: WindowKind.weekly,
          ),
          _window(now, '3p-5h', '5 horas', 50, group: 'Claude and GPT models'),
          _window(
            now,
            '3p-w',
            'Semanal (7d)',
            12,
            group: 'Claude and GPT models',
            kind: WindowKind.weekly,
          ),
        ],
        source: 'antigravity-language-server',
        stale: true,
        confidence: Confidence.low,
        age: const Duration(hours: 3),
        credits: const CreditsInfo(
          hasCredits: true,
          unlimited: false,
          balance: 12.5,
          currency: 'BRL',
          note: 'Créditos de prompt com um texto bem longo para testar truncamento e quebra de linha no rodapé do card',
        ),
      ),
      _errorSnapshot(
        now,
        ProviderId.claude,
        state: 'sem login',
        code: 'AUTH_MISSING',
        message:
            'Claude Desktop não tem sessão local. Abra o app e faça login.',
      ),
      _errorSnapshot(
        now,
        ProviderId.claude,
        state: 'expirado',
        code: 'AUTH_EXPIRED',
        message:
            'Sessão do Claude Code expirou. O cache abaixo pode estar velho.',
        windows: [
          _window(now, 'five-hour', '5 horas', 12, source: SourceKind.cache),
          _window(
            now,
            'seven-day',
            'Semanal (7d)',
            40,
            kind: WindowKind.weekly,
            source: SourceKind.cache,
          ),
        ],
        surface: ProviderSurface.cli,
        source: 'claude-oauth-usage',
        stale: true,
        confidence: Confidence.low,
      ),
      _errorSnapshot(
        now,
        ProviderId.claude,
        state: 'permissão',
        code: 'PERMISSION_DENIED',
        message: 'Acesso negado ao Keychain. Autorize o QuotaDeck nas preferências do sistema.',
      ),
      _errorSnapshot(
        now,
        ProviderId.claude,
        state: 'schema',
        code: 'SCHEMA_CHANGED',
        message: 'O provedor respondeu sem janelas conhecidas. O layout ainda mostra o último snapshot.',
        windows: [
          _window(now, 'five-hour', '5 horas', 8, source: SourceKind.cache),
        ],
        source: 'claude-desktop-oauth',
        stale: true,
        confidence: Confidence.low,
      ),
      _snapshot(
        now,
        ProviderId.claude,
        label: 'Claude Desktop',
        plan: 'team',
        windows: [
          _window(now, 'five-hour', '5 horas', 4),
          _window(now, 'seven-day', 'Semanal (7d)', 4, kind: WindowKind.weekly),
        ],
        source: 'claude-desktop-oauth',
        confidence: Confidence.high,
      ),
      _errorSnapshot(
        now,
        ProviderId.opencode,
        state: 'não instalado',
        code: 'NOT_INSTALLED',
        message: 'OpenCode não foi encontrado nesta máquina.',
        source: 'detection',
      ),
      _snapshot(
        now,
        ProviderId.codex,
        label: 'Codex IDE',
        plan: 'plus',
        windows: [
          _window(now, 'ide-5h', '5 horas', 8, source: SourceKind.appServer),
          _window(
            now,
            'ide-7d',
            'Semanal (7d)',
            15,
            kind: WindowKind.weekly,
            source: SourceKind.appServer,
          ),
        ],
        surface: ProviderSurface.ide,
        source: 'codex-app-server',
        confidence: Confidence.medium,
      ),
    ],
    errors: const [],
  );

  SnapshotEnvelope _groupsEnvelope(DateTime now) => SnapshotEnvelope(
    generatedAt: now,
    results: [
      _snapshot(
        now,
        ProviderId.antigravity,
        label: 'Antigravity',
        plan: 'Pro com nome comprido de plano',
        windows: [
          _window(
            now,
            'g1',
            'Semanal (7d) · Gemini Models — limite compartilhado da organização',
            31.6,
            group: 'Gemini Models',
            kind: WindowKind.weekly,
          ),
          _window(
            now,
            'g2',
            '5 horas · Gemini Models — janela móvel de cinco horas',
            20.5,
            group: 'Gemini Models',
          ),
          _window(
            now,
            'g3',
            'Semanal (7d) · Claude and GPT models — limite secundário',
            50,
            group: 'Claude and GPT models',
            kind: WindowKind.weekly,
          ),
          _window(
            now,
            'g4',
            '5 horas · Claude and GPT models',
            0,
            group: 'Claude and GPT models',
          ),
          _window(
            now,
            'g5',
            'Semanal (7d) · Gemini 4 Argon — limite experimental',
            0,
            group: 'Gemini 4 Argon',
            kind: WindowKind.weekly,
          ),
          _window(
            now,
            'g6',
            '5 horas · Gemini 4 Argon',
            0,
            group: 'Gemini 4 Argon',
          ),
          _window(
            now,
            'g7',
            'Créditos de prompt da organização',
            12.5,
            group: 'Créditos',
            kind: WindowKind.credits,
            status: QuotaStatus.warning,
          ),
        ],
        source: 'antigravity-language-server',
        confidence: Confidence.high,
        credits: const CreditsInfo(
          hasCredits: true,
          unlimited: false,
          balance: 500,
          currency: 'prompt-credits',
          note: 'limite mensal da organização',
        ),
      ),
      _snapshot(
        now,
        ProviderId.claude,
        label: 'Claude Desktop',
        plan: 'team · plano empresarial',
        windows: [
          _window(now, 'c1', '5 horas · limite unificado de sessão', 4),
          _window(
            now,
            'c2',
            'Semanal (7d) · limite unificado semanal',
            4,
            kind: WindowKind.weekly,
          ),
          _window(
            now,
            'c3',
            'Semanal Sonnet (7d) · somente modelos Sonnet',
            25,
            kind: WindowKind.model,
          ),
          _window(
            now,
            'c4',
            'Semanal Opus (7d) · somente modelos Opus',
            0,
            kind: WindowKind.model,
            noReset: true,
          ),
          _window(
            now,
            'c5',
            'Créditos extras pay-as-you-go',
            12.5,
            kind: WindowKind.credits,
            noReset: true,
          ),
        ],
        source: 'claude-desktop-oauth',
        confidence: Confidence.high,
        credits: const CreditsInfo(
          hasCredits: true,
          unlimited: false,
          balance: 87.5,
          currency: 'BRL',
          note: 'Créditos extras · limite mensal de R\$ 100,00 com texto longo',
        ),
      ),
    ],
    errors: const [],
  );

  SnapshotEnvelope _notInstalledEnvelope(DateTime now) => SnapshotEnvelope(
    generatedAt: now,
    results: [
      for (final provider in ProviderId.values)
        _errorSnapshot(
          now,
          provider,
          state: 'não instalado',
          code: 'NOT_INSTALLED',
          message:
              '${provider.displayName} não foi encontrado nesta máquina (mock).',
          source: 'detection',
        ),
    ],
    errors: const [],
  );

  ProviderSnapshot _opencode(DateTime now) => ProviderSnapshot(
    provider: ProviderId.opencode,
    account: const AccountInfo(label: 'OpenCode Go', plan: 'Go'),
    windows: [
      QuotaWindow(
        id: 'rolling-5h',
        label: '5 horas',
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
    account: const AccountInfo(label: 'Antigravity', plan: 'Pro'),
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
    source: 'antigravity-language-server',
    fetchedAt: now,
    confidence: Confidence.high,
  );

  ProviderSnapshot _codex(DateTime now) => ProviderSnapshot(
    provider: ProviderId.codex,
    account: const AccountInfo(label: 'Codex', plan: 'plus'),
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
    account: const AccountInfo(label: 'Claude Desktop', plan: 'team'),
    windows: [
      QuotaWindow(
        id: 'five_hour',
        label: '5 horas',
        kind: WindowKind.session,
        usedPercent: 10,
        remainingPercent: 90,
        resetsAt: now.add(const Duration(hours: 3, minutes: 19)),
        status: QuotaStatus.ok,
        source: SourceKind.api,
      ),
      QuotaWindow(
        id: 'seven_day',
        label: 'Semanal (7d)',
        kind: WindowKind.weekly,
        usedPercent: 5,
        remainingPercent: 95,
        resetsAt: now.add(const Duration(days: 1, hours: 21)),
        status: QuotaStatus.ok,
        source: SourceKind.api,
      ),
    ],
    source: _srcDesktopOauth,
    sourceId: _srcDesktopOauth,
    surface: ProviderSurface.desktop,
    fetchedAt: now,
    confidence: Confidence.high,
  );

  static const _srcDesktopOauth = 'claude-desktop-oauth';
}
