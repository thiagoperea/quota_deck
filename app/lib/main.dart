// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/legacy.dart';

import 'src/api/local_quota_api.dart';
import 'src/api/mock_api.dart';
import 'src/api/quota_api.dart';
import 'src/app.dart';
import 'src/desktop/tray_service.dart';
import 'src/state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const mockFlag = String.fromEnvironment('QDECK_MOCK', defaultValue: '');
  final useMock = mockFlag == '1' || mockFlag.toLowerCase() == 'true';
  final QuotaApi api = useMock ? MockApi() : LocalQuotaApi();
  final state = AppState(api);

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
      minimumSize: Size(380, 600),
      center: true,
      title: 'QuotaDeck',
      backgroundColor: Color(0xFF0F1115),
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
}
