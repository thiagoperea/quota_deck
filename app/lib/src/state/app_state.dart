import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../api/quota_api.dart';

class TightestQuota {
  const TightestQuota({required this.snapshot, required this.window});

  final ProviderSnapshot snapshot;
  final QuotaWindow window;
}

class UpcomingReset {
  const UpcomingReset({required this.snapshot, required this.window});

  final ProviderSnapshot snapshot;
  final QuotaWindow window;
}

class AppState extends ChangeNotifier {
  AppState(this._api);

  final QuotaApi _api;

  SnapshotEnvelope? _envelope;
  AppConfig _config = AppConfig.defaults().copyWith(theme: 'dark');
  ApiMeta? _meta;
  bool _loading = true;
  bool _refreshing = false;
  bool _saving = false;
  bool _initializing = false;
  bool _initialized = false;
  bool _disposed = false;
  String? _error;
  Timer? _timer;
  final Map<String, HistorySummary> _history = {};
  bool _loadingHistory = false;
  bool _wizardVisible = false;
  bool _detecting = false;
  bool _windowActive = true;
  Future<void>? _detectionFuture;
  List<DetectionResult> _detections = const [];
  List<DoctorCheck> _doctorChecks = const [];

  SnapshotEnvelope? get envelope => _envelope;
  AppConfig get config => _config;
  ApiMeta? get meta => _meta;
  bool get loading => _loading;
  bool get refreshing => _refreshing;
  bool get saving => _saving;
  bool get hasData => _envelope != null;
  String? get error => _error;
  List<DoctorCheck> get doctorChecks => _doctorChecks;
  List<DetectionResult> get detections => _detections;
  bool get detecting => _detecting;

  DetectionResult? detectionFor(ProviderId provider) {
    for (final detection in _detections) {
      if (detection.provider == provider) return detection;
    }
    return null;
  }

  List<ProviderId> get installedProviders => [
    for (final detection in _detections)
      if (detection.detected) detection.provider,
  ];

  bool get hasProvidersEnabled =>
      ProviderId.values.any((provider) => _config.isEnabled(provider));

  int get enabledProviderCount =>
      ProviderId.values.where(_config.isEnabled).length;

  bool get needsOnboarding => !_config.onboardingCompleted;

  /// Evita dois assistentes abertos quando há mais de uma rota montada.
  bool tryClaimWizard() {
    if (_wizardVisible) return false;
    _wizardVisible = true;
    return true;
  }

  void releaseWizard() {
    _wizardVisible = false;
  }

  /// Estimativa conservadora: 100% menos a janela mais consumida.
  double? get estimatedAvailablePercent {
    final quota = tightest;
    if (quota == null) return null;
    final value = 100 - quota.window.usedPercent;
    return value < 0 ? 0 : value;
  }

  List<ProviderSnapshot> get visibleSnapshots {
    final results = _envelope?.results ?? const <ProviderSnapshot>[];
    final enabled = results
        .where((snapshot) {
          if (!_config.isEnabled(snapshot.provider)) return false;
          final surface = snapshot.surface;
          if (surface != null &&
              !_config.isSurfaceEnabled(snapshot.provider, surface)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    enabled.sort((a, b) => a.provider.index.compareTo(b.provider.index));
    return enabled;
  }

  bool get isEmpty =>
      _initialized &&
      !_loading &&
      _envelope != null &&
      visibleSnapshots.isEmpty;

  List<QdeckErrorInfo> get globalErrors {
    final envelope = _envelope;
    if (envelope == null) return const <QdeckErrorInfo>[];
    final perProvider = <String>{
      for (final snapshot in envelope.results)
        for (final error in snapshot.errors) '${error.code}|${error.message}',
    };
    return envelope.errors
        .where(
          (error) => !perProvider.contains('${error.code}|${error.message}'),
        )
        .toList(growable: false);
  }

  TightestQuota? get tightest {
    TightestQuota? result;
    for (final snapshot in visibleSnapshots) {
      if (_isAuthError(snapshot)) continue;
      for (final window in snapshot.windows) {
        if (result == null || window.usedPercent > result.window.usedPercent) {
          result = TightestQuota(snapshot: snapshot, window: window);
        }
      }
    }
    return result;
  }

  List<UpcomingReset> upcomingResets({
    int limit = 4,
    Duration horizon = const Duration(hours: 48),
  }) {
    final now = DateTime.now().toUtc();
    final cutoff = now.add(horizon);
    final resets = <UpcomingReset>[];
    for (final snapshot in visibleSnapshots) {
      if (_isAuthError(snapshot)) continue;
      for (final window in snapshot.windows) {
        final reset = window.resetsAt;
        if (reset == null || !reset.isAfter(now) || reset.isAfter(cutoff)) {
          continue;
        }
        resets.add(UpcomingReset(snapshot: snapshot, window: window));
      }
    }
    resets.sort((a, b) => a.window.resetsAt!.compareTo(b.window.resetsAt!));
    return resets.take(limit).toList(growable: false);
  }

  UpcomingReset? get nextReset {
    final resets = upcomingResets(limit: 1);
    return resets.isEmpty ? null : resets.first;
  }

  HistorySummary? historyFor(ProviderId provider, String windowId) =>
      _history['${provider.wireName}:$windowId'];

  HistorySummary? get featuredHistory {
    final quota = tightest;
    if (quota == null) return null;
    return historyFor(quota.snapshot.provider, quota.window.id);
  }

  ThemeMode get themeMode => switch (_config.theme.trim().toLowerCase()) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> initialize({bool force = false}) async {
    if (_initializing) return;
    if (_initialized && !force) return;
    _initializing = true;
    if (_envelope == null) {
      _loading = true;
      _safeNotify();
    }

    try {
      final summary = await _api.fetchSummary();
      _envelope = summary.envelope;
      _config = summary.config;
      _meta = summary.meta;
      _error = null;
      _scheduleTimer();
      _loading = false;
      _initialized = true;
      _safeNotify();
      await _loadFeaturedHistory();
      unawaited(detectProviders());
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Não foi possível carregar os dados locais. Verifique as credenciais e tente novamente.';
    } finally {
      _loading = false;
      _initialized = true;
      _initializing = false;
      _safeNotify();
    }
  }

  Future<void> retry() => initialize(force: true);

  Future<void> refresh({ProviderId? provider, bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent) _safeNotify();

    try {
      final envelope = await _api.refresh(provider: provider);
      _envelope = envelope;
      _error = null;
      _refreshing = false;
      _safeNotify();
      await _loadFeaturedHistory(force: true);
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Não foi possível atualizar as quotas. Os dados anteriores continuam na tela.';
    } finally {
      _refreshing = false;
      _safeNotify();
    }
  }

  /// Aplica o tema só em memória, para preview imediato no sheet.
  void applyThemePreview(String theme) {
    _config = _config.copyWith(theme: theme);
    _safeNotify();
  }

  Future<bool> saveSettings(AppConfig next) async {
    if (_saving) return false;
    _saving = true;
    _safeNotify();
    try {
      final saved = await _api.saveSettings(next);
      _config = saved;
      _error = null;
      _scheduleTimer();
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } catch (_) {
      _error = 'Não foi possível salvar as configurações. Tente novamente.';
      return false;
    } finally {
      _saving = false;
      _safeNotify();
    }
  }

  Future<HistorySummary?> loadHistory(
    ProviderId provider,
    String windowId, {
    int hours = 24,
  }) async {
    try {
      final history = await _api.fetchHistory(
        provider: provider,
        windowId: windowId,
        hours: hours,
      );
      _history['${provider.wireName}:$windowId'] = history;
      _safeNotify();
      return history;
    } catch (_) {
      // Histórico é complementar: não derruba o painel.
      return null;
    }
  }

  Future<void> loadDoctor() async {
    try {
      _doctorChecks = await _api.fetchDoctor();
    } catch (_) {
      _doctorChecks = const [];
    }
    _safeNotify();
  }

  Future<void> detectProviders() => _detectionFuture ??= _runDetection();

  Future<void> _runDetection() async {
    _detecting = true;
    _safeNotify();
    try {
      _detections = await _api.detect();
      if (!_config.onboardingCompleted && _detections.isNotEmpty) {
        // Primeira execução: o painel atrás do wizard só mostra o que existe.
        final installed = {
          for (final d in _detections)
            if (d.detected) d.provider,
        };
        _config = _config.copyWith(
          providers: {
            for (final provider in ProviderId.values)
              provider.wireName: installed.contains(provider),
          },
        );
      }
    } catch (_) {
      // Detecção é complementar: mantém o que já havia.
    } finally {
      _detecting = false;
      _detectionFuture = null;
      _safeNotify();
    }
  }

  Future<void> _loadFeaturedHistory({bool force = false}) async {
    final quota = tightest;
    if (quota == null || _loadingHistory) return;
    final key = '${quota.snapshot.provider.wireName}:${quota.window.id}';
    if (!force && _history.containsKey(key)) return;
    _loadingHistory = true;
    try {
      await loadHistory(quota.snapshot.provider, quota.window.id);
    } finally {
      _loadingHistory = false;
    }
  }

  void _scheduleTimer() {
    _timer?.cancel();
    final seconds = _config.refreshSeconds;
    if (seconds <= 0) return;
    _timer = Timer.periodic(Duration(seconds: seconds), (_) {
      if (_disposed || !_windowActive) return;
      unawaited(refresh(silent: true));
    });
  }

  /// Pausa o polling quando a janela está oculta na bandeja.
  void setWindowActive(bool active) {
    if (_windowActive == active) return;
    _windowActive = active;
    if (active) unawaited(refresh(silent: true));
  }

  /// Fecha recursos pendentes antes de encerrar o processo.
  Future<void> shutdown() async {
    _timer?.cancel();
    _disposed = true;
    await _api.close();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  static bool _isAuthError(ProviderSnapshot snapshot) => snapshot.errors.any(
    (error) =>
        error.code == 'AUTH_EXPIRED' ||
        error.code == 'AUTH_MISSING' ||
        error.code == 'PERMISSION_DENIED',
  );

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_api.close());
    super.dispose();
  }
}
