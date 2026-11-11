// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'src/screens/customize_page.dart';
import 'src/state/app_state.dart';
import 'src/widgets/provider_wizard.dart';
import 'src/widgets/settings_sheet.dart';

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

  if (args.contains('--capture-screenshots')) {
    await _runScreenshotCapture(state);
    return;
  }

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

final GlobalKey _captureKey = GlobalKey();
final ValueNotifier<Size> _captureSize = ValueNotifier<Size>(
  const Size(1100, 1180),
);

Future<void> _runScreenshotCapture(AppState state) async {
  await state.initialize();
  await state.detectProviders();
  state.applyThemePreview('dark');

  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: ValueListenableBuilder<Size>(
        valueListenable: _captureSize,
        builder: (context, size, _) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              color: const Color(0xFF0F1115),
              alignment: Alignment.topLeft,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: size,
                      devicePixelRatio: 2.0,
                      platformBrightness: Brightness.dark,
                      textScaler: TextScaler.noScaling,
                    ),
                    child: RepaintBoundary(
                      key: _captureKey,
                      child: const QuotaDeckApp(compactOverride: false),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1200, 920),
      minimumSize: Size(320, 400),
      center: true,
      title: 'QuotaDeck',
      backgroundColor: Color(0xFF0F1115),
    ),
    () async {
      await windowManager.show();
    },
  );

  Future<void> snap(String filename, Size size) async {
    _captureSize.value = size;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final boundary =
        _captureKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      'C:/Repositories/quota_deck/docs/screenshots/$filename',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(byteData!.buffer.asUint8List());
  }

  void tapButtonsWithTooltip(String tooltip, {int maxTaps = 2}) {
    var tapped = 0;
    void visit(Element element) {
      if (tapped >= maxTaps) return;
      final widget = element.widget;
      if (widget is IconButton &&
          widget.tooltip == tooltip &&
          widget.onPressed != null) {
        widget.onPressed!();
        tapped++;
        return;
      }
      element.visitChildren(visit);
    }

    rootNavigatorKey.currentContext?.visitChildElements(visit);
  }

  void tapByKey(Key targetKey) {
    void visit(Element element) {
      final widget = element.widget;
      if (widget.key == targetKey) {
        if (widget is ButtonStyleButton && widget.onPressed != null) {
          widget.onPressed!();
          return;
        }
        if (widget is IconButton && widget.onPressed != null) {
          widget.onPressed!();
          return;
        }
      }
      element.visitChildren(visit);
    }

    rootNavigatorKey.currentContext?.visitChildElements(visit);
  }

  await Future<void>.delayed(const Duration(milliseconds: 1200));

  // 1. Full Dashboard (Wide 2-column layout)
  state.setMiniMode(false);
  await snap('01-dashboard-live.png', const Size(1100, 1240));

  // 2. Mini Popover (Tray popover)
  state.setMiniMode(true);
  await snap('02-mini-popover.png', const Size(380, 860));

  // 3. Compact Mode (Single-column layout)
  state.setMiniMode(false);
  await snap('03-compact-live.png', const Size(430, 1200));

  // 4. Customize Page (Personalizar painel)
  _captureSize.value = const Size(500, 760);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  unawaited(showCustomizePage(rootNavigatorKey.currentContext!));
  await Future<void>.delayed(const Duration(milliseconds: 500));
  tapButtonsWithTooltip('Editar janelas', maxTaps: 2);
  await snap('04-customize-panel.png', const Size(500, 760));
  rootNavigatorKey.currentState?.pop();
  await Future<void>.delayed(const Duration(milliseconds: 400));

  // 5. Settings Sheet (Notificações, Painel, Sistema)
  _captureSize.value = const Size(500, 1260);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  unawaited(showSettingsSheet(rootNavigatorKey.currentContext!));
  await snap('05-settings-notifications.png', const Size(500, 1260));
  rootNavigatorKey.currentState?.pop();
  await Future<void>.delayed(const Duration(milliseconds: 400));

  // 6. Provider Wizard Summary + Step
  _captureSize.value = const Size(500, 740);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  unawaited(
    showProviderWizard(rootNavigatorKey.currentContext!, firstRun: true),
  );
  await snap('06-provider-wizard.png', const Size(500, 740));
  tapByKey(const Key('wizard-back'));
  await snap('07-wizard-claude-step.png', const Size(500, 740));
  rootNavigatorKey.currentState?.pop();

  exit(0);
}
