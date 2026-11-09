// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

import '../app.dart';
import '../state/app_state.dart';
import '../widgets/settings_sheet.dart';

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

  Future<void> initialize() async {
    windowManager.addListener(this);
    trayManager.addListener(this);

    await trayManager.setIcon(
      Platform.isMacOS
          ? 'assets/tray/tray_template.png'
          : 'assets/tray/tray.png',
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
          MenuItem(key: 'show', label: 'Abrir QuotaDeck'),
          MenuItem(key: 'dashboard', label: 'Dashboard'),
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
    final quota = state.tightest;
    String text = 'QuotaDeck';
    if (quota != null) {
      final provider = quota.snapshot.provider.displayName;
      final used = formatPercent(quota.window.usedPercent);
      final reset = quota.window.resetsAt == null
          ? ''
          : ' · reset ${relativeTime(quota.window.resetsAt!)}';
      text = 'QuotaDeck · $provider ${used}% usado$reset';
    }
    try {
      await trayManager.setToolTip(text);
    } catch (_) {}
  }

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
        unawaited(_showCompact());
      case 'dashboard':
        unawaited(_showDashboard());
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
      await _showCompact();
    }
  }

  Future<void> _showCompact() async {
    state.setWindowActive(true);
    await windowManager.setSize(const Size(420, 760));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _showDashboard() async {
    state.setWindowActive(true);
    await windowManager.setSize(const Size(1100, 800));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _showSettings() async {
    state.setWindowActive(true);
    await windowManager.show();
    await windowManager.focus();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      await showSettingsSheet(context);
    }
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
