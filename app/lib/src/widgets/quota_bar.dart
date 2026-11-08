import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../theme.dart';

/// Barra horizontal de uso (0–100%). A cor segue o status da janela.
class QuotaBar extends StatelessWidget {
  const QuotaBar({
    super.key,
    required this.usedPercent,
    this.status,
    this.height = 6,
    this.color,
  });

  final double usedPercent;
  final QuotaStatus? status;
  final double height;
  final Color? color;

  static Color colorFor(BuildContext context, QuotaStatus status) {
    final palette = QdPalette.of(context);
    return switch (status) {
      QuotaStatus.ok => palette.green,
      QuotaStatus.warning => palette.yellow,
      QuotaStatus.critical || QuotaStatus.limited => palette.red,
      QuotaStatus.unknown => palette.dim,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final effectiveStatus =
        status ??
        statusForUsed(usedPercent, warningThreshold: 80, criticalThreshold: 95);
    final fillColor = color ?? colorFor(context, effectiveStatus);
    final value = clampPercent(usedPercent);
    final fraction = value / 100;

    return Semantics(
      label: '${formatPercent(value)} por cento usado',
      value: '${formatPercent(value)}%',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: palette.border.withValues(alpha: 0.8)),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  heightFactor: 1,
                  child: Container(
                    key: const Key('quota-bar-fill'),
                    decoration: BoxDecoration(
                      color: fillColor,
                      borderRadius: BorderRadius.circular(height),
                      boxShadow: [
                        BoxShadow(
                          color: fillColor.withValues(alpha: 0.35),
                          blurRadius: 6,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
