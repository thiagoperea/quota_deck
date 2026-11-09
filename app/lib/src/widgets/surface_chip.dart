import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../theme.dart';

/// Chip único de superfície (Desktop/CLI/IDE), com estado opcional.
class SurfaceChip extends StatelessWidget {
  const SurfaceChip({
    super.key,
    required this.surface,
    this.authenticated,
    this.label,
  });

  final ProviderSurface surface;
  final bool? authenticated;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final color = authenticated == null
        ? palette.dim
        : authenticated!
        ? palette.green
        : palette.yellow;
    return Semantics(
      label: label ?? 'Superfície ${surface.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(
          label ?? surface.label,
          style: TextStyle(
            color: color,
            fontSize: QdType.micro,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
