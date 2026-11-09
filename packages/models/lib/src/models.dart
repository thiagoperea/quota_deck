// DTOs compartilhados entre core, daemon, CLI e app Flutter.
// Este arquivo deve ser web-safe: sem dart:io, sem sqlite3, sem Flutter.

enum ProviderId {
  opencode,
  antigravity,
  codex,
  claude;

  String get wireName => name;

  String get displayName => vendorName;

  /// Nome do fornecedor, sem produto/superfície (ex.: "Claude", não "Claude Code").
  String get vendorName => switch (this) {
    ProviderId.opencode => 'OpenCode',
    ProviderId.antigravity => 'Antigravity',
    ProviderId.codex => 'Codex',
    ProviderId.claude => 'Claude',
  };

  static ProviderId? tryParse(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    for (final p in ProviderId.values) {
      if (p.name == v) return p;
    }
    return null;
  }
}

enum WindowKind {
  rolling,
  session,
  weekly,
  monthly,
  model,
  credits,
  unknown;

  String get wireName => name;

  static WindowKind fromWire(String? value) {
    final v = (value ?? '').trim();
    for (final k in WindowKind.values) {
      if (k.name == v) return k;
    }
    return WindowKind.unknown;
  }
}

enum QuotaStatus {
  ok,
  warning,
  critical,
  limited,
  unknown;

  String get wireName => name;

  static QuotaStatus fromWire(String? value) {
    final v = (value ?? '').trim();
    for (final s in QuotaStatus.values) {
      if (s.name == v) return s;
    }
    return QuotaStatus.unknown;
  }
}

enum Confidence {
  high,
  medium,
  low,
  none;

  String get wireName => name;

  static Confidence fromWire(String? value) {
    final v = (value ?? '').trim();
    for (final c in Confidence.values) {
      if (c.name == v) return c;
    }
    return Confidence.none;
  }
}

enum SourceKind {
  api,
  rpc,
  appServer,
  cli,
  headers,
  log,
  cache;

  String get wireName => switch (this) {
    SourceKind.api => 'api',
    SourceKind.rpc => 'rpc',
    SourceKind.appServer => 'app-server',
    SourceKind.cli => 'cli',
    SourceKind.headers => 'headers',
    SourceKind.log => 'log',
    SourceKind.cache => 'cache',
  };

  static SourceKind fromWire(String? value) {
    final v = (value ?? '').trim();
    for (final s in SourceKind.values) {
      if (s.wireName == v) return s;
    }
    return SourceKind.api;
  }
}

enum ProviderSurface {
  cli,
  desktop,
  ide;

  String get wireName => name;

  String get label => switch (this) {
    ProviderSurface.cli => 'CLI',
    ProviderSurface.desktop => 'Desktop',
    ProviderSurface.ide => 'IDE',
  };

  static ProviderSurface? tryParse(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    for (final s in ProviderSurface.values) {
      if (s.name == v) return s;
    }
    return null;
  }
}

enum DoctorStatus {
  ok,
  warn,
  fail;

  String get wireName => name;

  static DoctorStatus fromWire(String? value) {
    final v = (value ?? '').trim();
    for (final s in DoctorStatus.values) {
      if (s.name == v) return s;
    }
    return DoctorStatus.warn;
  }
}

class AccountInfo {
  final String label;
  final String? plan;
  final String? maskedEmail;

  const AccountInfo({required this.label, this.plan, this.maskedEmail});

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
    label: (json['label'] ?? 'Conta').toString(),
    plan: json['plan']?.toString(),
    maskedEmail: json['maskedEmail']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'plan': plan,
    'maskedEmail': maskedEmail,
  };
}

class QuotaWindow {
  final String id;
  final String label;
  final WindowKind kind;
  final String? group;
  final double usedPercent;
  final double remainingPercent;
  final DateTime? resetsAt;
  final QuotaStatus status;
  final SourceKind source;

  const QuotaWindow({
    required this.id,
    required this.label,
    required this.kind,
    this.group,
    required this.usedPercent,
    required this.remainingPercent,
    this.resetsAt,
    required this.status,
    required this.source,
  });

  factory QuotaWindow.fromJson(Map<String, dynamic> json) {
    final used = _asDouble(json['usedPercent']);
    final remaining = json['remainingPercent'] != null
        ? _asDouble(json['remainingPercent'])
        : (100.0 - used);
    return QuotaWindow(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? json['id'] ?? '').toString(),
      kind: WindowKind.fromWire(json['kind']?.toString()),
      group: json['group']?.toString(),
      usedPercent: clampPercent(used),
      remainingPercent: clampPercent(remaining),
      resetsAt: parseDate(json['resetsAt']),
      status: QuotaStatus.fromWire(json['status']?.toString()),
      source: SourceKind.fromWire(json['source']?.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.wireName,
    'group': group,
    'usedPercent': usedPercent,
    'remainingPercent': remainingPercent,
    'resetsAt': formatDate(resetsAt),
    'status': status.wireName,
    'source': source.wireName,
  };

  QuotaWindow copyWith({
    double? usedPercent,
    double? remainingPercent,
    DateTime? resetsAt,
    QuotaStatus? status,
    SourceKind? source,
  }) => QuotaWindow(
    id: id,
    label: label,
    kind: kind,
    group: group,
    usedPercent: usedPercent ?? this.usedPercent,
    remainingPercent: remainingPercent ?? this.remainingPercent,
    resetsAt: resetsAt ?? this.resetsAt,
    status: status ?? this.status,
    source: source ?? this.source,
  );
}

class CreditsInfo {
  final bool hasCredits;
  final bool unlimited;
  final double? balance;
  final String? currency;
  final String? note;

  const CreditsInfo({
    required this.hasCredits,
    required this.unlimited,
    this.balance,
    this.currency,
    this.note,
  });

  factory CreditsInfo.fromJson(Map<String, dynamic> json) => CreditsInfo(
    hasCredits: _asBool(json['hasCredits']),
    unlimited: _asBool(json['unlimited']),
    balance: json['balance'] == null ? null : _asDouble(json['balance']),
    currency: json['currency']?.toString(),
    note: json['note']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'hasCredits': hasCredits,
    'unlimited': unlimited,
    'balance': balance,
    'currency': currency,
    'note': note,
  };
}

class QdeckErrorInfo {
  final String code;
  final String message;
  final bool retryable;
  final Map<String, dynamic>? details;

  const QdeckErrorInfo({
    required this.code,
    required this.message,
    this.retryable = false,
    this.details,
  });

  factory QdeckErrorInfo.fromJson(Map<String, dynamic> json) => QdeckErrorInfo(
    code: (json['code'] ?? 'UNKNOWN').toString(),
    message: (json['message'] ?? '').toString(),
    retryable: _asBool(json['retryable']),
    details: json['details'] is Map<String, dynamic>
        ? json['details'] as Map<String, dynamic>
        : null,
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'retryable': retryable,
    if (details != null) 'details': details,
  };
}

class ProviderSnapshot {
  final int schemaVersion;
  final ProviderId provider;
  final AccountInfo account;
  final List<QuotaWindow> windows;
  final CreditsInfo? credits;
  final String source;
  final String? sourceId;
  final ProviderSurface? surface;
  final DateTime fetchedAt;
  final bool stale;
  final Confidence confidence;
  final List<QdeckErrorInfo> errors;

  const ProviderSnapshot({
    this.schemaVersion = 1,
    required this.provider,
    required this.account,
    required this.windows,
    this.credits,
    required this.source,
    this.sourceId,
    this.surface,
    required this.fetchedAt,
    this.stale = false,
    this.confidence = Confidence.none,
    this.errors = const [],
  });

  factory ProviderSnapshot.fromJson(Map<String, dynamic> json) {
    final provider =
        ProviderId.tryParse(json['provider']?.toString()) ??
        ProviderId.opencode;
    final windows = (json['windows'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(QuotaWindow.fromJson)
        .toList(growable: false);
    final errors = (json['errors'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(QdeckErrorInfo.fromJson)
        .toList(growable: false);
    return ProviderSnapshot(
      schemaVersion: _asInt(json['schemaVersion'], 1),
      provider: provider,
      account: json['account'] is Map<String, dynamic>
          ? AccountInfo.fromJson(json['account'] as Map<String, dynamic>)
          : AccountInfo(label: provider.displayName),
      windows: windows,
      credits: json['credits'] is Map<String, dynamic>
          ? CreditsInfo.fromJson(json['credits'] as Map<String, dynamic>)
          : null,
      source: (json['source'] ?? 'unknown').toString(),
      sourceId: json['sourceId']?.toString(),
      surface: ProviderSurface.tryParse(json['surface']?.toString()),
      fetchedAt: parseDate(json['fetchedAt']) ?? DateTime.now().toUtc(),
      stale: _asBool(json['stale']),
      confidence: Confidence.fromWire(json['confidence']?.toString()),
      errors: errors,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'provider': provider.wireName,
    'account': account.toJson(),
    'windows': windows.map((w) => w.toJson()).toList(growable: false),
    'credits': credits?.toJson(),
    'source': source,
    'sourceId': sourceId,
    'surface': surface?.wireName,
    'fetchedAt': formatDate(fetchedAt),
    'stale': stale,
    'confidence': confidence.wireName,
    'errors': errors.map((e) => e.toJson()).toList(growable: false),
  };

  ProviderSnapshot copyWith({
    List<QuotaWindow>? windows,
    CreditsInfo? credits,
    String? source,
    String? sourceId,
    ProviderSurface? surface,
    DateTime? fetchedAt,
    bool? stale,
    Confidence? confidence,
    List<QdeckErrorInfo>? errors,
  }) => ProviderSnapshot(
    schemaVersion: schemaVersion,
    provider: provider,
    account: account,
    windows: windows ?? this.windows,
    credits: credits ?? this.credits,
    source: source ?? this.source,
    sourceId: sourceId ?? this.sourceId,
    surface: surface ?? this.surface,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    stale: stale ?? this.stale,
    confidence: confidence ?? this.confidence,
    errors: errors ?? this.errors,
  );

  bool get hasError => errors.isNotEmpty;

  String? get primaryError => errors.isEmpty ? null : errors.first.message;

  double get worstUsedPercent {
    if (windows.isEmpty) return 0;
    return windows.map((w) => w.usedPercent).reduce((a, b) => a > b ? a : b);
  }

  QuotaWindow? get worstWindow {
    if (windows.isEmpty) return null;
    return windows.reduce((a, b) => a.usedPercent >= b.usedPercent ? a : b);
  }
}

class SnapshotEnvelope {
  final int schemaVersion;
  final DateTime generatedAt;
  final List<ProviderSnapshot> results;
  final List<QdeckErrorInfo> errors;

  const SnapshotEnvelope({
    this.schemaVersion = 1,
    required this.generatedAt,
    required this.results,
    this.errors = const [],
  });

  factory SnapshotEnvelope.fromJson(Map<String, dynamic> json) =>
      SnapshotEnvelope(
        schemaVersion: _asInt(json['schemaVersion'], 1),
        generatedAt: parseDate(json['generatedAt']) ?? DateTime.now().toUtc(),
        results: (json['results'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ProviderSnapshot.fromJson)
            .toList(growable: false),
        errors: (json['errors'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(QdeckErrorInfo.fromJson)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'generatedAt': formatDate(generatedAt),
    'results': results.map((r) => r.toJson()).toList(growable: false),
    'errors': errors.map((e) => e.toJson()).toList(growable: false),
  };

  ProviderSnapshot? byProvider(ProviderId id) {
    for (final r in results) {
      if (r.provider == id) return r;
    }
    return null;
  }
}

class DetectionResult {
  final ProviderId provider;
  final bool detected;
  final String? reason;
  final Map<String, dynamic>? details;
  final List<SurfaceState> surfaces;

  const DetectionResult({
    required this.provider,
    required this.detected,
    this.reason,
    this.details,
    this.surfaces = const [],
  });

  factory DetectionResult.fromSurfaces({
    required ProviderId provider,
    required List<SurfaceState> surfaces,
    String? reason,
  }) {
    final installed = surfaces
        .where((s) => s.installed)
        .toList(growable: false);
    return DetectionResult(
      provider: provider,
      detected: installed.isNotEmpty,
      reason: reason ?? (installed.isEmpty ? _summary(surfaces) : null),
      surfaces: surfaces,
    );
  }

  List<SurfaceState> get installedSurfaces =>
      surfaces.where((s) => s.installed).toList(growable: false);

  List<SurfaceState> get authenticatedSurfaces => surfaces
      .where((s) => s.installed && s.authenticated)
      .toList(growable: false);

  bool get authenticated => authenticatedSurfaces.isNotEmpty;

  SurfaceState? get preferredSurface {
    for (final surface in authenticatedSurfaces) {
      if (surface.live) return surface;
    }
    final authenticatedAll = authenticatedSurfaces;
    if (authenticatedAll.isNotEmpty) return authenticatedAll.first;
    final installed = installedSurfaces;
    return installed.isEmpty ? null : installed.first;
  }

  Map<String, dynamic> toJson() => {
    'provider': provider.wireName,
    'detected': detected,
    'reason': reason,
    if (details != null) 'details': details,
    if (surfaces.isNotEmpty)
      'surfaces': surfaces.map((s) => s.toJson()).toList(growable: false),
  };

  static String _summary(List<SurfaceState> surfaces) {
    if (surfaces.isEmpty) return 'Nenhuma superfície conhecida.';
    return surfaces
        .map(
          (s) => '${s.surface.label}: ${s.installed ? 'instalado' : 'ausente'}',
        )
        .join('; ');
  }
}

class SurfaceState {
  final ProviderSurface surface;
  final bool installed;
  final bool authenticated;
  final bool live;
  final String? version;
  final String? location;
  final String? account;
  final String? reason;
  final String? action;

  const SurfaceState({
    required this.surface,
    required this.installed,
    this.authenticated = false,
    this.live = true,
    this.version,
    this.location,
    this.account,
    this.reason,
    this.action,
  });

  factory SurfaceState.fromJson(Map<String, dynamic> json) => SurfaceState(
    surface:
        ProviderSurface.tryParse(json['surface']?.toString()) ??
        ProviderSurface.cli,
    installed: _asBool(json['installed']),
    authenticated: _asBool(json['authenticated']),
    live: json['live'] == null ? true : _asBool(json['live']),
    version: json['version']?.toString(),
    location: json['location']?.toString(),
    account: json['account']?.toString(),
    reason: json['reason']?.toString(),
    action: json['action']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'surface': surface.wireName,
    'installed': installed,
    'authenticated': authenticated,
    'live': live,
    'version': version,
    'location': location,
    'account': account,
    'reason': reason,
    'action': action,
  };
}

class DoctorCheck {
  final ProviderId provider;
  final String id;
  final String label;
  final DoctorStatus status;
  final String message;
  final Map<String, dynamic>? details;

  const DoctorCheck({
    required this.provider,
    required this.id,
    required this.label,
    required this.status,
    required this.message,
    this.details,
  });

  Map<String, dynamic> toJson() => {
    'provider': provider.wireName,
    'id': id,
    'label': label,
    'status': status.wireName,
    'message': message,
    if (details != null) 'details': details,
  };
}

class HistorySample {
  final ProviderId provider;
  final String windowId;
  final double usedPercent;
  final DateTime fetchedAt;
  final bool stale;

  const HistorySample({
    required this.provider,
    required this.windowId,
    required this.usedPercent,
    required this.fetchedAt,
    this.stale = false,
  });

  Map<String, dynamic> toJson() => {
    'provider': provider.wireName,
    'windowId': windowId,
    'usedPercent': usedPercent,
    'fetchedAt': formatDate(fetchedAt),
    'stale': stale,
  };

  factory HistorySample.fromJson(Map<String, dynamic> json) => HistorySample(
    provider:
        ProviderId.tryParse(json['provider']?.toString()) ??
        ProviderId.opencode,
    windowId: (json['windowId'] ?? '').toString(),
    usedPercent: clampPercent(_asDouble(json['usedPercent'])),
    fetchedAt: parseDate(json['fetchedAt']) ?? DateTime.now().toUtc(),
    stale: _asBool(json['stale']),
  );
}

class HistorySummary {
  final ProviderId provider;
  final String windowId;
  final List<HistorySample> samples;
  final double burnRatePerHour;
  final double? etaHours;

  const HistorySummary({
    required this.provider,
    required this.windowId,
    required this.samples,
    required this.burnRatePerHour,
    this.etaHours,
  });

  Map<String, dynamic> toJson() => {
    'provider': provider.wireName,
    'windowId': windowId,
    'samples': samples.map((s) => s.toJson()).toList(growable: false),
    'burnRatePerHour': burnRatePerHour,
    'etaHours': etaHours,
  };
}

class AppConfig {
  final int schemaVersion;
  final Map<String, bool> providers;
  final Map<String, bool> surfaces;
  final int refreshSeconds;
  final int cacheTtlSeconds;
  final bool historyEnabled;
  final int retentionDays;
  final bool notificationsEnabled;
  final int warningThreshold;
  final int criticalThreshold;
  final int resetSoonMinutes;
  final String theme;
  final bool launchAtLogin;
  final bool allowProbe;
  final bool allowOAuthRefresh;
  final bool onboardingCompleted;

  const AppConfig({
    this.schemaVersion = 1,
    required this.providers,
    this.surfaces = const {},
    this.refreshSeconds = 60,
    this.cacheTtlSeconds = 60,
    this.historyEnabled = true,
    this.retentionDays = 30,
    this.notificationsEnabled = true,
    this.warningThreshold = 80,
    this.criticalThreshold = 95,
    this.resetSoonMinutes = 15,
    this.theme = 'system',
    this.launchAtLogin = false,
    this.allowProbe = false,
    this.allowOAuthRefresh = false,
    this.onboardingCompleted = false,
  });

  factory AppConfig.defaults() => const AppConfig(
    providers: {
      'opencode': true,
      'antigravity': true,
      'codex': true,
      'claude': true,
    },
  );

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final defaults = AppConfig.defaults();
    final rawProviders = json['providers'];
    final providers = <String, bool>{...defaults.providers};
    if (rawProviders is Map) {
      for (final entry in rawProviders.entries) {
        providers[entry.key.toString()] = _asBool(entry.value);
      }
    }
    final rawSurfaces = json['surfaces'];
    final surfaces = <String, bool>{...defaults.surfaces};
    if (rawSurfaces is Map) {
      for (final entry in rawSurfaces.entries) {
        surfaces[entry.key.toString()] = _asBool(entry.value);
      }
    }
    return AppConfig(
      schemaVersion: _asInt(json['schemaVersion'], 1),
      providers: providers,
      surfaces: surfaces,
      refreshSeconds: _asInt(json['refreshSeconds'], defaults.refreshSeconds),
      cacheTtlSeconds: _asInt(
        json['cacheTtlSeconds'],
        defaults.cacheTtlSeconds,
      ),
      historyEnabled: json['historyEnabled'] == null
          ? defaults.historyEnabled
          : _asBool(json['historyEnabled']),
      retentionDays: _asInt(json['retentionDays'], defaults.retentionDays),
      notificationsEnabled: json['notificationsEnabled'] == null
          ? defaults.notificationsEnabled
          : _asBool(json['notificationsEnabled']),
      warningThreshold: _asInt(
        json['warningThreshold'],
        defaults.warningThreshold,
      ),
      criticalThreshold: _asInt(
        json['criticalThreshold'],
        defaults.criticalThreshold,
      ),
      resetSoonMinutes: _asInt(
        json['resetSoonMinutes'],
        defaults.resetSoonMinutes,
      ),
      theme: (json['theme'] ?? defaults.theme).toString(),
      launchAtLogin: json['launchAtLogin'] == null
          ? defaults.launchAtLogin
          : _asBool(json['launchAtLogin']),
      allowProbe: json['allowProbe'] == null
          ? defaults.allowProbe
          : _asBool(json['allowProbe']),
      allowOAuthRefresh: json['allowOAuthRefresh'] == null
          ? defaults.allowOAuthRefresh
          : _asBool(json['allowOAuthRefresh']),
      onboardingCompleted: json['onboardingCompleted'] == null
          ? defaults.onboardingCompleted
          : _asBool(json['onboardingCompleted']),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'providers': providers,
    'surfaces': surfaces,
    'refreshSeconds': refreshSeconds,
    'cacheTtlSeconds': cacheTtlSeconds,
    'historyEnabled': historyEnabled,
    'retentionDays': retentionDays,
    'notificationsEnabled': notificationsEnabled,
    'warningThreshold': warningThreshold,
    'criticalThreshold': criticalThreshold,
    'resetSoonMinutes': resetSoonMinutes,
    'theme': theme,
    'launchAtLogin': launchAtLogin,
    'allowProbe': allowProbe,
    'allowOAuthRefresh': allowOAuthRefresh,
    'onboardingCompleted': onboardingCompleted,
  };

  bool isEnabled(ProviderId id) => providers[id.wireName] ?? true;

  bool isSurfaceEnabled(ProviderId id, ProviderSurface surface) =>
      surfaces['${id.wireName}.${surface.wireName}'] ?? true;

  AppConfig copyWith({
    Map<String, bool>? providers,
    Map<String, bool>? surfaces,
    int? refreshSeconds,
    int? cacheTtlSeconds,
    bool? historyEnabled,
    int? retentionDays,
    bool? notificationsEnabled,
    int? warningThreshold,
    int? criticalThreshold,
    int? resetSoonMinutes,
    String? theme,
    bool? launchAtLogin,
    bool? allowProbe,
    bool? allowOAuthRefresh,
    bool? onboardingCompleted,
  }) => AppConfig(
    schemaVersion: schemaVersion,
    providers: providers ?? this.providers,
    surfaces: surfaces ?? this.surfaces,
    refreshSeconds: refreshSeconds ?? this.refreshSeconds,
    cacheTtlSeconds: cacheTtlSeconds ?? this.cacheTtlSeconds,
    historyEnabled: historyEnabled ?? this.historyEnabled,
    retentionDays: retentionDays ?? this.retentionDays,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    warningThreshold: warningThreshold ?? this.warningThreshold,
    criticalThreshold: criticalThreshold ?? this.criticalThreshold,
    resetSoonMinutes: resetSoonMinutes ?? this.resetSoonMinutes,
    theme: theme ?? this.theme,
    launchAtLogin: launchAtLogin ?? this.launchAtLogin,
    allowProbe: allowProbe ?? this.allowProbe,
    allowOAuthRefresh: allowOAuthRefresh ?? this.allowOAuthRefresh,
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
  );
}

// ---------------------------------------------------------------------------
// Helpers (também exportados via status.dart)
// ---------------------------------------------------------------------------

double clampPercent(num value) {
  final v = value.toDouble();
  if (v.isNaN) return 0;
  if (v < 0) return 0;
  if (v > 100) return 100;
  return (v * 10).roundToDouble() / 10;
}

double asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? asDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? asIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is num) {
    var n = value.toDouble();
    // Aceita epoch em segundos (~1.7e9) ou milissegundos (~1.7e12).
    if (n < 100000000000) n *= 1000;
    return DateTime.fromMillisecondsSinceEpoch(n.round(), isUtc: true);
  }
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toUtc();
}

String? formatDate(DateTime? value) =>
    value?.toUtc().toIso8601String().replaceFirst(RegExp(r'\.000Z$'), 'Z');

int _asInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  final s = value?.toString().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}
