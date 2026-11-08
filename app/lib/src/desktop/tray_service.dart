// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

import '../state/app_state.dart';

/// Bandeja do sistema + janela compacta.
///
/// Clique esquerdo: mostra/esconde a janela compacta.
/// Clique direito: menu (Abrir, Dashboard, Atualizar, Sair).
/// Fechar a janela esconde para a bandeja; "Sair" encerra o app.
class TrayService with TrayListener, WindowListener {
  TrayService(this.state);

  final AppState state;
  bool _initialized = false;
  bool _quitting = false;

  Future<void> initialize() async {
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    trayManager.addListener(this);

    await trayManager.setIcon(
      Platform.isMacOS
          ? 'assets/tray/tray_template.png'
          : 'assets/tray/tray.png',
      isTemplate: Platform.isMacOS,
      iconSize: 18,
    );
    await trayManager.setToolTip('QuotaDeck');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Abrir QuotaDeck'),
          MenuItem(key: 'dashboard', label: 'Dashboard'),
          MenuItem(key: 'refresh', label: 'Atualizar agora'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Sair'),
        ],
      ),
    );
    _initialized = true;
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
      case 'refresh':
        unawaited(state.refresh());
      case 'quit':
        unawaited(_quit());
    }
  }

  @override
  void onWindowClose() {
    if (!_quitting) {
      unawaited(windowManager.hide());
    }
  }

  Future<void> _toggle() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await _showCompact();
    }
  }

  Future<void> _showCompact() async {
    await windowManager.setSize(const Size(420, 760));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _showDashboard() async {
    await windowManager.setSize(const Size(1100, 800));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    _quitting = true;
    await windowManager.setPreventClose(false);
    if (_initialized) {
      await trayManager.destroy();
    }
    await windowManager.destroy();
    exit(0);
  }

  void dispose() {
    if (!_initialized) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    unawaited(trayManager.destroy());
    _initialized = false;
  }
}
