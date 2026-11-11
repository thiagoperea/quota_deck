// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

import '../app.dart';
import '../screens/customize_page.dart';
import '../state/app_state.dart';
import '../widgets/settings_sheet.dart';
import 'window_mode.dart';

/// Bandeja do sistema + janela compacta.
///
/// Clique esquerdo: mostra/esconde a janela compacta.
/// Clique direito: menu (Abrir, Dashboard, Configurações, Atualizar, Sair).
/// Fechar a janela esconde para a bandeja (com aviso na primeira vez).
class TrayService with TrayListener, WindowListener {
  TrayService(this.state);

  final AppState state;
  bool _initialized = false;
  bool _quitting = false;
  bool _closeHintShown = false;
  QuotaStatus? _iconStatus;

  Future<void> initialize() async {
    windowManager.addListener(this);
    trayManager.addListener(this);

    await trayManager.setIcon(
      Platform.isMacOS
          ? 'assets/tray/tray_template.png'
          : 'assets/tray/tray_ok.png',
      isTemplate: Platform.isMacOS,
      iconSize: 18,
    );
    await _updateTooltip();
    await _rebuildMenu();
    // Só sequestra o fechamento depois que o tray está funcional.
    await windowManager.setPreventClose(true);
    state.addListener(_onState);
    _initialized = true;
  }

  Future<void> _rebuildMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Abrir mini'),
          MenuItem(key: 'dashboard', label: 'Dashboard completo'),
          MenuItem(key: 'customize', label: 'Personalizar painel…'),
          MenuItem(key: 'detect', label: 'Detectar provedores'),
          MenuItem(key: 'settings', label: 'Configurações…'),
          MenuItem(key: 'refresh', label: 'Atualizar agora'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Sair'),
        ],
      ),
    );
  }

  Future<void> _updateTooltip() async {
    if (!_initialized && !state.hasData) return;
    final snapshots = state.visibleSnapshots;
    final buffer = StringBuffer('QuotaDeck');
    if (snapshots.isEmpty) {
      buffer.write(' · sem provedores');
    } else {
      for (final snapshot in snapshots) {
        final window = _worstWindow(snapshot);
        buffer.write('\n${snapshot.provider.displayName} · ');
        if (window == null) {
          buffer.write(snapshot.hasError ? 'erro' : 'sem dados');
          continue;
        }
        buffer.write('${formatPercent(window.usedPercent)}% (${window.label})');
        if (snapshot.stale) buffer.write(' · desatualizado');
        if (snapshot.errors.any(_isAuthErrorCode)) buffer.write(' · login');
      }
    }
    var text = buffer.toString();
    // O tooltip do shell no Windows trunca perto de 128 caracteres.
    if (Platform.isWindows && text.length > 120) {
      final parts = [
        for (final snapshot in snapshots)
          '${_code(snapshot.provider)} '
              '${_worstWindow(snapshot) == null ? '!' : '${formatPercent(_worstWindow(snapshot)!.usedPercent)}%'}',
      ];
      text = 'QuotaDeck · ${parts.join(' · ')}';
    }
    try {
      await trayManager.setToolTip(text);
    } catch (_) {}
    await _updateIcon(snapshots);
  }

  static String _code(ProviderId provider) => switch (provider) {
    ProviderId.opencode => 'OC',
    ProviderId.antigravity => 'AG',
    ProviderId.codex => 'CX',
    ProviderId.claude => 'CL',
  };

  Future<void> _updateIcon(List<ProviderSnapshot> snapshots) async {
    if (Platform.isMacOS) return;
    var status = QuotaStatus.ok;
    for (final snapshot in snapshots) {
      for (final window in state.windowsFor(snapshot)) {
        if (window.status == QuotaStatus.limited ||
            window.status == QuotaStatus.critical) {
          status = QuotaStatus.critical;
          break;
        }
        if (window.status == QuotaStatus.warning) {
          status = QuotaStatus.warning;
        }
      }
      if (status == QuotaStatus.critical) break;
    }
    if (status == _iconStatus) return;
    _iconStatus = status;
    final asset = switch (status) {
      QuotaStatus.critical ||
      QuotaStatus.limited => 'assets/tray/tray_crit.png',
      QuotaStatus.warning => 'assets/tray/tray_warn.png',
      _ => 'assets/tray/tray_ok.png',
    };
    try {
      await trayManager.setIcon(asset, isTemplate: false, iconSize: 18);
    } catch (_) {}
  }

  QuotaWindow? _worstWindow(ProviderSnapshot snapshot) {
    QuotaWindow? worst;
    for (final window in state.windowsFor(snapshot)) {
      if (worst == null || window.usedPercent > worst.usedPercent) {
        worst = window;
      }
    }
    return worst;
  }

  static bool _isAuthErrorCode(QdeckErrorInfo error) =>
      error.code == 'AUTH_EXPIRED' ||
      error.code == 'AUTH_MISSING' ||
      error.code == 'PERMISSION_DENIED';

  void _onState() {
    unawaited(_updateTooltip());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_toggle());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_showMini());
      case 'dashboard':
        unawaited(_showDashboard());
      case 'customize':
        unawaited(_showCustomize());
      case 'detect':
        unawaited(_detectProviders());
      case 'settings':
        unawaited(_showSettings());
      case 'refresh':
        unawaited(_refresh());
      case 'quit':
        unawaited(_quit());
    }
  }

  @override
  void onWindowClose() {
    if (!_quitting) {
      unawaited(_hideWithHint());
    }
  }

  Future<void> _toggle() async {
    if (await windowManager.isVisible()) {
      state.setWindowActive(false);
      await windowManager.hide();
    } else {
      await _showMini();
    }
  }

  Future<void> _showMini() async {
    await openMiniWindow(state);
  }

  Future<void> _showDashboard() async {
    await openDashboardWindow(state);
  }

  Future<void> _showSettings() async {
    await openDashboardWindow(state);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      // ignore: use_build_context_synchronously
      await showSettingsSheet(context);
    }
  }

  Future<void> _showCustomize() async {
    await openDashboardWindow(state);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      // ignore: use_build_context_synchronously
      await showCustomizePage(context);
    }
  }

  Future<void> _detectProviders() async {
    await state.redetect();
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final detections = state.detections;
    final installed = detections.where((item) => item.detected).length;
    final detail = detections.isEmpty
        ? 'Nenhuma superfície conhecida foi encontrada.'
        : detections
              .map(
                (item) =>
                    '${item.provider.displayName}: '
                    '${item.detected ? 'instalado' : 'não instalado'}',
              )
              .join('\n');
    // ignore: use_build_context_synchronously
    await showDialog<void>(
      context: context, // ignore: use_build_context_synchronously
      builder: (dialogContext) => AlertDialog(
        title: const Text('Detecção concluída'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            '$installed de ${detections.length} detectados.\n\n$detail',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    await state.refresh();
    await _updateTooltip();
  }

  Future<void> _hideWithHint() async {
    final context = rootNavigatorKey.currentContext;
    if (!_closeHintShown && context != null) {
      _closeHintShown = true;
      try {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Continua na bandeja'),
            content: const Text(
              'O QuotaDeck segue rodando. Clique no ícone da bandeja para abrir; '
              'use "Sair" no menu para encerrar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      } catch (_) {}
    }
    state.setWindowActive(false);
    await windowManager.hide();
  }

  Future<void> _quit() async {
    _quitting = true;
    await windowManager.setPreventClose(false);
    state.removeListener(_onState);
    await state.shutdown();
    if (_initialized) {
      await trayManager.destroy();
    }
    await windowManager.destroy();
    exit(0);
  }

  void dispose() {
    if (!_initialized) return;
    state.removeListener(_onState);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    unawaited(trayManager.destroy());
    _initialized = false;
  }
}
