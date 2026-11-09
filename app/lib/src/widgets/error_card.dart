import 'package:flutter/material.dart';

import '../theme.dart';

/// Card de erro amigável com ação de tentar novamente.
class ErrorCard extends StatelessWidget {
  const ErrorCard({
    super.key,
    required this.message,
    this.onRetry,
    this.dense = false,
    this.title = 'Não foi possível carregar as quotas',
  });

  final String message;
  final VoidCallback? onRetry;
  final bool dense;
  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      key: const Key('error-card'),
      padding: EdgeInsets.all(dense ? 10 : 14),
      decoration: BoxDecoration(
        color: palette.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: dense ? 16 : 20,
            color: palette.red,
          ),
          SizedBox(width: dense ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!dense)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Text(
                  message,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: dense ? 10.5 : 11.5,
                    height: 1.4,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 14),
                    label: const Text('Tentar novamente'),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.red,
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(
                        fontSize: QdType.small,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
