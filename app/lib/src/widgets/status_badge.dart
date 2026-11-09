import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../theme.dart';

/// Badge compacto de status + confiança, com variante de autenticação e cache.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.confidence = Confidence.none,
    this.stale = false,
    this.auth = false,
  });

  final QuotaStatus status;
  final Confidence confidence;
  final bool stale;
  final bool auth;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final (label, color) = auth
        ? ('renovar login', palette.yellow)
        : switch (status) {
            QuotaStatus.ok => ('ok', palette.green),
            QuotaStatus.warning => ('atenção', palette.yellow),
            QuotaStatus.critical => ('crítico', palette.red),
            QuotaStatus.limited => ('limite', palette.red),
            QuotaStatus.unknown => ('sem dado', palette.dim),
          };

    final confidenceLabel = switch (confidence) {
      Confidence.high => 'alta',
      Confidence.medium => 'média',
      Confidence.low => 'baixa',
      Confidence.none => '',
    };
    final text = label;

    return Semantics(
      label: auth
          ? 'Autenticação necessária'
          : 'Status $label, confiança $confidenceLabel',
      excludeSemantics: true,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: QdType.meta,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (stale)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: palette.panel2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                'desatualizado',
                style: TextStyle(
                  color: palette.muted,
                  fontSize: QdType.micro,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
