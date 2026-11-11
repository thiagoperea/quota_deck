import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../api/quota_api.dart';
import '../desktop/notification_service.dart';
import '../desktop/update_service.dart';
import '../version.dart';

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
  AppState(
    this._api, {
    this.onLaunchAtLoginChanged,
    this.isLaunchAtLoginEnabled,
    Notifier? notifier,
    NotificationStateStore notificationStore = const NotificationStateStore(
      null,
    ),
    UpdateService? updateService,
    this.onRequestNotificationPermission,
  }) : _notifier = notifier, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _notificationStore = notificationStore,
       // ignore: prefer_initializing_formals
       _updateService = updateService;

  final QuotaApi _api;

  /// Aplica a preferência no sistema operacional. `null` em testes/CLI.
  final Future<bool> Function(bool enabled)? onLaunchAtLoginChanged;

  /// Lê o estado real do autostart para refletir no toggle.
  final Future<bool> Function()? isLaunchAtLoginEnabled;

  /// Pede permissão de notificação no macOS (ligado no `main`).
  final Future<void> Function()? onRequestNotificationPermission;

  final Notifier? _notifier;
  final NotificationStateStore _notificationStore;
  final UpdateService? _updateService;
  NotificationPolicy _notificationPolicy = NotificationPolicy();
  UpdateInfo? _update;
  DateTime? _lastUpdateCheck;
  Timer? _updateTimer;
  DateTime? _lastBackgroundRefresh;

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
  bool _miniMode = false;
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

  /// Release mais nova encontrada, se houver.
  UpdateInfo? get update => _update;

  /// Janela mini (popover da bandeja) em vez do painel completo.
  bool get miniMode => _miniMode;

  void setMiniMode(bool value) {
    if (_miniMode == value) return;
    _miniMode = value;
    _safeNotify();
  }

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
    enabled.sort((a, b) {
      final byRank = _config
          .providerRank(a.provider)
          .compareTo(_config.providerRank(b.provider));
      if (byRank != 0) return byRank;
      return a.provider.displayName.toLowerCase().compareTo(
        b.provider.displayName.toLowerCase(),
      );
    });
    return enabled;
  }

  /// Janelas que devem aparecer, respeitando a visibilidade configurada.
  List<QuotaWindow> windowsFor(
    ProviderSnapshot snapshot, {
    bool includeOnDemand = true,
  }) {
    return [
      for (final window in snapshot.windows)
        if (_config.visibilityFor(snapshot.provider, window.id) ==
            WindowVisibility.always)
          window
        else if (includeOnDemand &&
            _config.visibilityFor(snapshot.provider, window.id) ==
                WindowVisibility.onDemand)
          window,
    ];
  }

  List<QuotaWindow> onDemandWindowsFor(ProviderSnapshot snapshot) => [
    for (final window in snapshot.windows)
      if (_config.visibilityFor(snapshot.provider, window.id) ==
          WindowVisibility.onDemand)
        window,
  ];

  int onDemandCount(ProviderSnapshot snapshot) =>
      onDemandWindowsFor(snapshot).length;

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
      for (final window in windowsFor(snapshot, includeOnDemand: false)) {
        if (result == null || window.usedPercent > result.window.usedPercent) {
          result = TightestQuota(snapshot: snapshot, window: window);
        }
      }
    }
    return result;
  }

  /// Provedores que pedem ação: erro de autenticação, dado velho ou janela
  /// em aviso/crítico. Usado pela faixa "Precisa de atenção".
  List<ProviderSnapshot> get attentionProviders => [
    for (final snapshot in visibleSnapshots)
      if (_isAuthError(snapshot) ||
          snapshot.stale ||
          switch (snapshot.worstWindow?.status) {
            QuotaStatus.warning ||
            QuotaStatus.critical ||
            QuotaStatus.limited => true,
            _ => false,
          })
        snapshot,
  ];

  /// Momento do dado mais antigo exibido. Evita dizer "atualizado agora"
  /// quando parte dos provedores veio do cache.
  DateTime? get lastUpdatedAt {
    DateTime? oldest;
    for (final snapshot in visibleSnapshots) {
      final fetched = snapshot.fetchedAt;
      if (oldest == null || fetched.isBefore(oldest)) oldest = fetched;
    }
    return oldest ?? _envelope?.generatedAt;
  }

  bool get hasStaleData =>
      _error != null || visibleSnapshots.any((snapshot) => snapshot.stale);

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
      _notificationPolicy = await _notificationStore.load();
      final actualLaunchAtLogin = await isLaunchAtLoginEnabled?.call();
      if (actualLaunchAtLogin != null &&
          actualLaunchAtLogin != _config.launchAtLogin) {
        _config = _config.copyWith(launchAtLogin: actualLaunchAtLogin);
      }
      if (_config.launchAtLogin) {
        unawaited(_applyLaunchAtLogin(true));
      }
      _scheduleTimer();
      _scheduleUpdateTimer();
      _loading = false;
      _initialized = true;
      _safeNotify();
      await _loadFeaturedHistory();
      if (_config.notificationsEnabled) {
        unawaited(requestNotificationPermission());
      }
      unawaited(_evaluateNotifications(summary.envelope));
      if (_config.checkUpdates) unawaited(checkForUpdates());
      // Na primeira execução a detecção define o que aparece no painel; nas
      // seguintes ela é complementar e não deve atrasar a abertura.
      if (_config.onboardingCompleted) {
        unawaited(detectProviders());
      } else {
        await detectProviders();
      }
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

  Future<void>? _refreshFuture;
  bool _refreshDirty = false;
  ProviderId? _nextProvider;
  bool _nextSilent = true;

  /// Atualiza as quotas. Chamadas concorrentes não são descartadas: quem
  /// chega durante uma execução aguarda e pede uma nova rodada no final
  /// (last-wins), devolvendo dados realmente frescos para botão e wizard.
  Future<void> refresh({ProviderId? provider, bool silent = false}) {
    final running = _refreshFuture;
    if (running != null) {
      _refreshDirty = true;
      _nextProvider = provider;
      _nextSilent = _nextSilent && silent;
      return running;
    }
    final future = _drainRefresh(provider: provider, silent: silent);
    _refreshFuture = future;
    return future;
  }

  Future<void> _drainRefresh({
    ProviderId? provider,
    bool silent = false,
  }) async {
    var nextProvider = provider;
    var nextSilent = silent;
    _refreshing = true;
    _nextSilent = true;
    if (!nextSilent) _safeNotify();
    try {
      while (true) {
        _refreshDirty = false;
        await _refreshOnce(provider: nextProvider);
        if (!_refreshDirty) break;
        nextProvider = _nextProvider;
        nextSilent = _nextSilent;
        _nextProvider = null;
        if (!nextSilent) _safeNotify();
      }
    } finally {
      _refreshing = false;
      _refreshFuture = null;
      _safeNotify();
    }
  }

  Future<void> _refreshOnce({ProviderId? provider}) async {
    try {
      final envelope = await _api.refresh(provider: provider);
      if (_disposed) return;
      _envelope = envelope;
      _error = null;
      _lastBackgroundRefresh = DateTime.now();
      _safeNotify();
      await _loadFeaturedHistory(force: true);
      unawaited(_evaluateNotifications(envelope));
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      _error =
          'Não foi possível atualizar as quotas. Os dados anteriores continuam na tela.';
    }
  }

  /// Aplica o tema só em memória, para preview imediato no sheet.
  void applyThemePreview(String theme) {
    _config = _config.copyWith(theme: theme);
    _safeNotify();
  }

  AppConfig? _pendingSave;
  Future<bool>? _saveFuture;
  bool _lastSaveResult = true;

  /// Grava as configurações em série. Chamadas durante uma gravação são
  /// coalescidas: o snapshot mais recente é o que fica no disco.
  Future<bool> saveSettings(AppConfig next) {
    _pendingSave = next;
    final running = _saveFuture;
    if (running != null) {
      return running.then((_) => _lastSaveResult);
    }
    final future = _drainSaves();
    _saveFuture = future;
    return future;
  }

  Future<bool> _drainSaves() async {
    _saving = true;
    _safeNotify();
    var ok = true;
    try {
      while (_pendingSave != null) {
        final next = _pendingSave!;
        _pendingSave = null;
        ok = await _saveConfig(next);
      }
    } finally {
      _lastSaveResult = ok;
      _saving = false;
      _saveFuture = null;
      _safeNotify();
    }
    return ok;
  }

  Future<bool> _saveConfig(AppConfig next) async {
    try {
      final previous = _config;
      final saved = await _api.saveSettings(next);
      _config = saved;
      _error = null;
      if (previous.launchAtLogin != saved.launchAtLogin) {
        final applied = await _applyLaunchAtLogin(saved.launchAtLogin);
        if (!applied) {
          _error =
              'Configurações salvas, mas não foi possível alterar a '
              'inicialização automática do sistema.';
        }
      }
      _scheduleTimer();
      _scheduleUpdateTimer();
      if (!previous.notificationsEnabled && saved.notificationsEnabled) {
        await requestNotificationPermission();
        final envelope = _envelope;
        if (envelope != null) unawaited(_evaluateNotifications(envelope));
      }
      if (!previous.checkUpdates && saved.checkUpdates) {
        unawaited(checkForUpdates(force: true));
      }
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } catch (_) {
      _error = 'Não foi possível salvar as configurações. Tente novamente.';
      return false;
    }
  }

  Future<bool> _applyLaunchAtLogin(bool enabled) async {
    final callback = onLaunchAtLoginChanged;
    if (callback == null) return true;
    try {
      return await callback(enabled);
    } catch (_) {
      return false;
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

  Future<void> detectProviders({bool force = false}) {
    if (force) {
      _detectionFuture = null;
    }
    return _detectionFuture ??= _runDetection(explicit: force);
  }

  /// Nova varredura pedida pelo usuário (bandeja/assistente).
  Future<void> redetect() async {
    final pending = _detectionFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    _detectionFuture = null;
    await detectProviders(force: true);
  }

  Future<void> _runDetection({bool explicit = false}) async {
    _detecting = true;
    _safeNotify();
    try {
      _detections = await _api.detect();
      final installed = <ProviderId>{
        for (final detection in _detections)
          if (detection.detected) detection.provider,
      };
      if (_detections.isEmpty) return;

      final firstRun = !_config.onboardingCompleted;
      if (firstRun) {
        // Primeira execução: o painel mostra só o que existe e o resultado
        // é persistido para não depender do wizard.
        _config = _config.copyWith(
          providers: {
            for (final provider in ProviderId.values)
              provider.wireName: installed.contains(provider),
          },
        );
        await _persistDetection();
      } else if (explicit) {
        // Detecção pedida pelo usuário só liga o que achou; nunca desliga.
        if (installed.any((provider) => !_config.isEnabled(provider))) {
          _config = _config.copyWith(
            providers: {
              ..._config.providers,
              for (final provider in installed) provider.wireName: true,
            },
          );
          await _persistDetection();
        }
      }
    } catch (_) {
      // Detecção é complementar: mantém o que já havia.
    } finally {
      _detecting = false;
      _detectionFuture = null;
      _safeNotify();
    }
  }

  Future<void> _persistDetection() async {
    try {
      _config = await _api.saveSettings(_config);
    } catch (_) {
      // Mantém a mudança em memória se a gravação falhar.
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
      if (_disposed) return;
      if (!_windowActive) {
        // Com a janela na bandeja, só busca para poder notificar.
        if (!_config.notificationsEnabled) return;
        final now = DateTime.now();
        final last = _lastBackgroundRefresh;
        if (last != null && now.difference(last) < const Duration(minutes: 5)) {
          return;
        }
        _lastBackgroundRefresh = now;
      }
      unawaited(refresh(silent: true));
    });
  }

  /// Pede permissão de notificação (macOS) quando o usuário ativa o recurso.
  Future<void> requestNotificationPermission() async {
    try {
      await onRequestNotificationPermission?.call();
    } catch (_) {}
  }

  /// Envia uma notificação de teste para validar a entrega no sistema.
  Future<bool> sendTestNotification() async {
    final notifier = _notifier;
    if (notifier == null) return false;
    await notifier.show(
      const NotificationMessage(
        title: 'QuotaDeck',
        body: 'Notificações ativas. Você será avisado ao cruzar os limites.',
      ),
    );
    return true;
  }

  Future<void> _evaluateNotifications(SnapshotEnvelope envelope) async {
    if (!_config.notificationsEnabled) return;
    // Com o painel à frente o usuário já vê o estado; notificar seria ruído.
    if (_windowActive) return;
    final notifier = _notifier;
    if (notifier == null) return;
    final messages = _notificationPolicy.evaluate(
      envelope: envelope,
      config: _config,
    );
    for (final message in messages) {
      await notifier.show(message);
    }
    if (messages.isNotEmpty || _notificationStore.file != null) {
      await _notificationStore.save(_notificationPolicy);
    }
  }

  void _scheduleUpdateTimer() {
    _updateTimer?.cancel();
    if (_updateService == null || !_config.checkUpdates) return;
    _updateTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => unawaited(checkForUpdates(force: true)),
    );
  }

  /// Consulta a última release; silencioso em qualquer falha.
  Future<void> checkForUpdates({bool force = false}) async {
    final service = _updateService;
    if (service == null) return;
    if (!_config.checkUpdates && !force) return;
    final now = DateTime.now();
    final last = _lastUpdateCheck;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(hours: 24)) {
      return;
    }
    _lastUpdateCheck = now;
    final info = await service.check(currentVersion: appVersion);
    if (info == null || _disposed) return;
    _update = info;
    _safeNotify();
  }

  void dismissUpdate() {
    _update = null;
    _safeNotify();
  }

  Future<bool> openUpdate() async {
    final info = _update;
    final service = _updateService;
    if (info == null || service == null) return false;
    return service.openExternal(info.url);
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
    _updateTimer?.cancel();
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
    _updateTimer?.cancel();
    unawaited(_api.close());
    super.dispose();
  }
}
