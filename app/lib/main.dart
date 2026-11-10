// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:window_manager/legacy.dart';

import 'src/api/local_quota_api.dart';
import 'src/api/mock_api.dart';
import 'src/api/quota_api.dart';
import 'src/app.dart';
import 'src/desktop/single_instance.dart';
import 'src/desktop/startup_args.dart';
import 'src/desktop/startup_service.dart';
import 'src/desktop/tray_service.dart';
import 'src/desktop/window_mode.dart';
import 'src/state/app_state.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final startHidden = launchedAtStartup(args);

  const mockFlag = String.fromEnvironment('QDECK_MOCK', defaultValue: '');
  final useMock = mockFlag == '1' || mockFlag.toLowerCase() == 'true';

  final single = SingleInstance(
    port: useMock ? 47832 : 47831,
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

  final QuotaApi api = useMock
      ? MockApi(
          config: AppConfig.defaults().copyWith(
            theme: 'dark',
            refreshSeconds: 0,
            onboardingCompleted: true,
          ),
        )
      : LocalQuotaApi();
  final state = AppState(
    api,
    onLaunchAtLoginChanged: useMock ? null : StartupService.setEnabled,
    isLaunchAtLoginEnabled: useMock ? null : StartupService.isEnabled,
  );

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
