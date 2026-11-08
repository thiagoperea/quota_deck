import 'package:flutter/material.dart';

/// Paleta do QuotaDeck.
@immutable
class QdPalette extends ThemeExtension<QdPalette> {
  const QdPalette({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.border,
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
  final Color border;
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
    text: Color(0xFFE8EBF2),
    muted: Color(0xFF8B93A7),
    dim: Color(0xFF697386),
    green: Color(0xFF3DDC97),
    yellow: Color(0xFFF5C451),
    red: Color(0xFFFF6B6B),
    blue: Color(0xFF6EA8FE),
    purple: Color(0xFFB197FC),
  );

  static const light = QdPalette(
    bg: Color(0xFFF3F5F9),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFF8FAFC),
    border: Color(0xFFDDE3EC),
    text: Color(0xFF141922),
    muted: Color(0xFF5B6577),
    dim: Color(0xFF7C8798),
    green: Color(0xFF0E9F6E),
    yellow: Color(0xFFB7791F),
    red: Color(0xFFD64545),
    blue: Color(0xFF2B6CB0),
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

/// Cores fixas usadas em gradientes de avatar e detalhes.
abstract final class QdColors {
  static const bg = Color(0xFF0F1115);
  static const panel = Color(0xFF171A21);
  static const panel2 = Color(0xFF1D212A);
  static const border = Color(0xFF2A303C);
  static const text = Color(0xFFE8EBF2);
  static const muted = Color(0xFF8B93A7);
  static const dim = Color(0xFF697386);
  static const green = Color(0xFF3DDC97);
  static const yellow = Color(0xFFF5C451);
  static const red = Color(0xFFFF6B6B);
  static const blue = Color(0xFF6EA8FE);
  static const purple = Color(0xFFB197FC);
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
        outline: palette.border,
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
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
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
        highlightColor: palette.panel2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
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
        borderSide: BorderSide(color: palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.green.withValues(alpha: 0.8)),
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
    focusColor: palette.green.withValues(alpha: 0.16),
  );
}
