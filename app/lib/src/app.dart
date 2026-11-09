import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_page.dart';
import 'state/app_state.dart';
import 'theme.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class QuotaDeckApp extends StatelessWidget {
  const QuotaDeckApp({super.key, this.compactOverride});

  /// Usado por testes e por integrações que já sabem o modo desejado.
  final bool? compactOverride;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final compact = compactOverride ?? detectCompactMode();
        return MaterialApp(
          title: 'QuotaDeck',
          navigatorKey: rootNavigatorKey,
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: state.themeMode,
          initialRoute: compact ? '/compact' : '/',
          onGenerateRoute: (settings) {
            final routeCompact = compact || settings.name == '/compact';
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => HomePage(compact: routeCompact),
            );
          },
        );
      },
    );
  }
}

/// `?compact=1` e `/compact` abrem o layout de popover.
bool detectCompactMode() => isCompactUri(Uri.base);

bool isCompactUri(Uri uri) {
  final path = uri.path;
  return uri.queryParameters['compact'] == '1' ||
      path == '/compact' ||
      path.endsWith('/compact');
}
