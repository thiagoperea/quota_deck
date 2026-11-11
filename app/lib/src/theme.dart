import 'package:flutter/material.dart';

/// Paleta do QuotaDeck.
@immutable
class QdPalette extends ThemeExtension<QdPalette> {
  const QdPalette({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.dim,
    required this.green,
    required this.yellow,
    required this.red,
    required this.blue,
    required this.purple,
  });

  final Color bg;
  final Color panel;
  final Color panel2;

  /// Separadores decorativos (cards, divisórias).
  final Color border;

  /// Bordas de controle (inputs, tracks, chips): contraste ≥ 3:1.
  final Color borderStrong;
  final Color text;
  final Color muted;
  final Color dim;
  final Color green;
  final Color yellow;
  final Color red;
  final Color blue;
  final Color purple;

  static const dark = QdPalette(
    bg: Color(0xFF0F1115),
    panel: Color(0xFF171A21),
    panel2: Color(0xFF1D212A),
    border: Color(0xFF2A303C),
    borderStrong: Color(0xFF626D82),
    text: Color(0xFFE8EBF2),
    muted: Color(0xFF98A1B3),
    dim: Color(0xFFA8B2C4),
    green: Color(0xFF3DDC97),
    yellow: Color(0xFFF5C451),
    red: Color(0xFFFF6B6B),
    blue: Color(0xFF6EA8FE),
    purple: Color(0xFFB197FC),
  );

  static const light = QdPalette(
    bg: Color(0xFFE9EEF5),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFFBFCFE),
    border: Color(0xFFC9D3E1),
    borderStrong: Color(0xFF7C8798),
    text: Color(0xFF121826),
    muted: Color(0xFF4E5A6B),
    dim: Color(0xFF4A5568),
    green: Color(0xFF0A6B4E),
    yellow: Color(0xFF7A4E0A),
    red: Color(0xFFB42318),
    blue: Color(0xFF1D4ED8),
    purple: Color(0xFF6B46C1),
  );

  static QdPalette of(BuildContext context) =>
      Theme.of(context).extension<QdPalette>() ?? dark;

  @override
  QdPalette copyWith({
    Color? bg,
    Color? panel,
    Color? panel2,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? muted,
    Color? dim,
    Color? green,
    Color? yellow,
    Color? red,
    Color? blue,
    Color? purple,
  }) => QdPalette(
    bg: bg ?? this.bg,
    panel: panel ?? this.panel,
    panel2: panel2 ?? this.panel2,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    dim: dim ?? this.dim,
    green: green ?? this.green,
    yellow: yellow ?? this.yellow,
    red: red ?? this.red,
    blue: blue ?? this.blue,
    purple: purple ?? this.purple,
  );

  @override
  QdPalette lerp(covariant QdPalette? other, double t) {
    if (other == null) return this;
    return QdPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panel2: Color.lerp(panel2, other.panel2, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      green: Color.lerp(green, other.green, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
      red: Color.lerp(red, other.red, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
    );
  }
}

/// Escala tipográfica única (6 passos).
///
/// Piso de 10,5 px: 9,5 px `dim` reprovava AA no tema claro.
abstract final class QdType {
  static const micro = 10.5;
  static const meta = 11.0;
  static const small = 11.5;
  static const body = 12.5;
  static const title = 15.0;
  static const kpi = 22.0;

  /// Números que mudam (%, horários): dígitos de largura fixa evitam
  /// o "pulo" a cada atualização.
  static const numeric = <FontFeature>[FontFeature.tabularFigures()];
}

/// Grade de espaçamento (8 pt, com meios passos para micro-layouts).
abstract final class QdSpace {
  static const xs = 2.0;
  static const sm = 4.0;
  static const md = 6.0;
  static const base = 8.0;
  static const lg = 12.0;
  static const xl = 16.0;
  static const xxl = 24.0;
}

/// Raios de canto padronizados.
abstract final class QdRadius {
  static const chip = 6.0;
  static const control = 10.0;
  static const card = 12.0;
  static const dialog = 16.0;
  static const sheet = 20.0;
  static const pill = 999.0;
}

/// Durações curtas para transições de valor. Respeita "reduzir movimento".
abstract final class QdMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 180);

  static Duration of(BuildContext context, Duration duration) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return reduce ? Duration.zero : duration;
  }
}

ThemeData buildDarkTheme() => _buildTheme(Brightness.dark, QdPalette.dark);

ThemeData buildLightTheme() => _buildTheme(Brightness.light, QdPalette.light);

ThemeData _buildTheme(Brightness brightness, QdPalette palette) {
  final isDark = brightness == Brightness.dark;
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.green,
        brightness: brightness,
      ).copyWith(
        primary: palette.green,
        onPrimary: isDark ? const Color(0xFF06110B) : Colors.white,
        secondary: palette.blue,
        onSecondary: isDark ? const Color(0xFF06101D) : Colors.white,
        surface: palette.panel,
        onSurface: palette.text,
        error: palette.red,
        onError: Colors.white,
        outline: palette.borderStrong,
        outlineVariant: palette.border,
        surfaceContainer: palette.panel,
        surfaceContainerHigh: palette.panel2,
        surfaceContainerHighest: palette.panel2,
        onSurfaceVariant: palette.muted,
      );

  final textTheme = base.textTheme
      .apply(bodyColor: palette.text, displayColor: palette.text)
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.35),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
        ),
      );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.bg,
    canvasColor: palette.panel,
    dividerColor: palette.border,
    textTheme: textTheme,
    extensions: <ThemeExtension<dynamic>>[palette],
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      color: palette.panel2,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QdRadius.card),
        side: BorderSide(color: palette.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QdRadius.dialog),
        side: BorderSide(color: palette.border),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.muted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.panel,
      modalBackgroundColor: palette.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.panel2,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.green,
        foregroundColor: isDark ? const Color(0xFF06110B) : Colors.white,
        minimumSize: const Size(0, 44),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.muted,
        minimumSize: const Size(0, 40),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: palette.muted,
        highlightColor: palette.text.withValues(alpha: 0.12),
        hoverColor: palette.text.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QdRadius.control),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.green
            : palette.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.green.withValues(alpha: 0.28)
            : palette.border.withValues(alpha: 0.7),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.green.withValues(alpha: 0.55)
            : palette.border,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.panel2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.green, width: 2),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: palette.text),
      waitDuration: const Duration(milliseconds: 500),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.green,
      linearTrackColor: palette.border,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.green,
      selectionColor: palette.green.withValues(alpha: 0.25),
      selectionHandleColor: palette.green,
    ),
    focusColor: palette.green.withValues(alpha: 0.32),
  );
}
