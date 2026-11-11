// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck_core/quota_deck_core.dart' show AppPaths;
import 'package:window_manager/legacy.dart';

import 'src/api/local_quota_api.dart';
import 'src/api/quota_api.dart';
import 'src/app.dart';
import 'src/desktop/notification_service.dart';
import 'src/desktop/single_instance.dart';
import 'src/desktop/startup_args.dart';
import 'src/desktop/startup_service.dart';
import 'src/desktop/tray_service.dart';
import 'src/desktop/update_service.dart';
import 'src/desktop/window_mode.dart';
import 'src/state/app_state.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final startHidden = launchedAtStartup(args);

  final single = SingleInstance(
    port: 47831,
    onShow: () async {
      await ensureWindowOnScreen();
      await windowManager.show();
      await windowManager.focus();
    },
  );
  final isFirst = await single.acquire();
  if (!isFirst && await single.notifyExisting()) {
    // Já existe uma instância: pede foco e encerra esta.
    exit(0);
  }

  final QuotaApi api = LocalQuotaApi();
  final paths = AppPaths.forPlatform();
  final notifications = LocalNotificationService();
  await notifications.initialize();
  final state = AppState(
    api,
    onLaunchAtLoginChanged: StartupService.setEnabled,
    isLaunchAtLoginEnabled: StartupService.isEnabled,
    notifier: notifications,
    notificationStore: NotificationStateStore(paths.notificationsFile),
    updateService: UpdateService(),
    onRequestNotificationPermission: notifications.requestPermission,
  );
  notifications.onTap = () async {
    // Não encolhe o dashboard aberto: só abre o mini se a janela estiver oculta.
    if (await windowManager.isVisible()) {
      state.setWindowActive(true);
      await windowManager.show();
      await windowManager.focus();
      return;
    }
    await openMiniWindow(state);
  };

  final tray = TrayService(state);
  try {
    await tray.initialize();
  } catch (error) {
    debugPrint('Tray indisponível: $error');
  }

  runApp(
    ChangeNotifierProvider.value(value: state, child: const QuotaDeckApp()),
  );

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(420, 760),
      minimumSize: Size(320, 400),
      center: true,
      title: 'QuotaDeck',
      backgroundColor: Color(0xFF0F1115),
    ),
    () async {
      if (startHidden) {
        state.setWindowActive(false);
        await windowManager.hide();
        return;
      }
      const miniFlag = String.fromEnvironment('QDECK_MINI', defaultValue: '');
      if (miniFlag == '1') {
        await openMiniWindow(state);
        return;
      }
      await windowManager.show();
      await windowManager.focus();
    },
  );
}
