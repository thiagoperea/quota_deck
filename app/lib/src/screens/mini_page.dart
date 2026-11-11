import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../desktop/window_mode.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/provider_card.dart';
import '../widgets/provider_wizard.dart';
import '../widgets/quota_bar.dart';
import '../widgets/settings_sheet.dart';

/// Popover compacto aberto pelo clique na bandeja.
///
/// Lista as janelas de cada provedor; o dashboard completo abre em um clique.
/// Sem resumo, histórico ou tendência para caber em ~380x500.
class MiniPage extends StatelessWidget {
  const MiniPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Scaffold(
      key: const Key('quota-deck-mini'),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.75, -0.95),
            radius: 1.4,
            colors: [
              palette.panel2.withValues(
                alpha: palette.bg.computeLuminance() < 0.2 ? 0.9 : 0.7,
              ),
              palette.bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(state: state),
                const SizedBox(height: 6),
                _MiniFreshness(state: state),
                if (state.update != null) ...[
                  const SizedBox(height: 8),
                  _MiniUpdate(state: state),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.loading && !state.hasData)
                          const _MiniLoading()
                        else if (state.visibleSnapshots.isEmpty)
                          _MiniEmpty(state: state)
                        else
                          for (final snapshot in state.visibleSnapshots) ...[
                            _MiniProviderRow(
                              snapshot: snapshot,
                              windows: state.windowsFor(
                                snapshot,
                                includeOnDemand: false,
                              ),
                              onDemandWindows: state.onDemandWindowsFor(
                                snapshot,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _Footer(state: state),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Faixa de frescor do mini: mostra quando o dado é velho e oferece retry.
class _MiniFreshness extends StatelessWidget {
  const _MiniFreshness({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final problem = state.error != null || state.hasStaleData;
    final last = state.lastUpdatedAt;
    final label = last == null
        ? 'carregando dados'
        : 'atualizado ${relativeTime(last)}';

    if (!problem) {
      return Row(
        children: [
          Icon(Icons.schedule, size: 11, color: palette.dim),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.dim, fontSize: QdType.micro),
            ),
          ),
        ],
      );
    }

    return Container(
      key: const Key('mini-stale-strip'),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: palette.yellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(QdRadius.chip),
        border: Border.all(color: palette.yellow.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 12, color: palette.yellow),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              state.error != null
                  ? 'Sem atualizar · $label'
                  : 'Dados antigos · $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.yellow, fontSize: QdType.micro),
            ),
          ),
          TextButton(
            onPressed: state.refreshing
                ? null
                : () => unawaited(state.refresh()),
            style: TextButton.styleFrom(
              foregroundColor: palette.yellow,
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: QdType.micro,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Tentar'),
          ),
        ],
      ),
    );
  }
}

class _MiniUpdate extends StatelessWidget {
  const _MiniUpdate({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final info = state.update!;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: palette.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_alt, size: 13, color: palette.blue),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: () => unawaited(state.openUpdate()),
              child: Text(
                'v${info.version} disponível · baixar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.blue,
                  fontSize: QdType.meta,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dispensar',
            onPressed: state.dismissUpdate,
            icon: const Icon(Icons.close, size: 13),
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: const Key('mini-expand'),
            onTap: () => unawaited(openDashboardWindow(state)),
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: SweepGradient(
                        transform: const GradientRotation(-1.15),
                        colors: [
                          palette.green,
                          palette.green,
                          palette.border,
                          palette.border,
                        ],
                        stops: const [0, 0.62, 0.62, 1],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: palette.panel,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.border.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'QuotaDeck',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _IconButton(
          key: const Key('mini-refresh'),
          icon: state.refreshing ? Icons.sync : Icons.refresh_rounded,
          tooltip: 'Atualizar agora',
          onPressed: state.refreshing ? null : () => unawaited(state.refresh()),
        ),
        const SizedBox(width: 4),
        _IconButton(
          key: const Key('mini-settings'),
          icon: Icons.tune,
          tooltip: 'Configurações',
          onPressed: () => unawaited(showSettingsSheet(context)),
        ),
        const SizedBox(width: 4),
        _IconButton(
          key: const Key('mini-close'),
          icon: Icons.close,
          tooltip: 'Esconder na bandeja',
          onPressed: () => unawaited(hideToTray(state)),
        ),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: palette.panel2,
            side: BorderSide(color: palette.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(icon, size: 15),
        ),
      ),
    );
  }
}

class _MiniProviderRow extends StatefulWidget {
  const _MiniProviderRow({
    required this.snapshot,
    required this.windows,
    required this.onDemandWindows,
  });

  final ProviderSnapshot snapshot;
  final List<QuotaWindow> windows;
  final List<QuotaWindow> onDemandWindows;

  @override
  State<_MiniProviderRow> createState() => _MiniProviderRowState();
}

class _MiniProviderRowState extends State<_MiniProviderRow> {
  bool _expanded = false;

  ProviderSnapshot get snapshot => widget.snapshot;

  bool get _authError => snapshot.errors.any(
    (error) =>
        error.code == 'AUTH_EXPIRED' ||
        error.code == 'AUTH_MISSING' ||
        error.code == 'PERMISSION_DENIED',
  );

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final windows = sortWindowsForDisplay([
      ...widget.windows,
      if (_expanded) ...widget.onDemandWindows,
    ]);
    final groups = <String?, List<QuotaWindow>>{};
    for (final window in windows) {
      groups.putIfAbsent(window.group, () => []).add(window);
    }
    final showGroups = groups.keys.any(
      (group) => group != null && group.trim().isNotEmpty,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _authError
              ? palette.yellow.withValues(alpha: 0.35)
              : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProviderAvatar(provider: snapshot.provider, size: 18),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  snapshot.provider.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (snapshot.surface != null) ...[
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    snapshot.surface!.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.dim,
                      fontSize: QdType.micro,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (_authError)
                Flexible(
                  child: Text(
                    'login necessário',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.yellow,
                      fontSize: QdType.micro,
                    ),
                  ),
                ),
            ],
          ),
          if (windows.isEmpty && widget.onDemandWindows.isEmpty) ...[
            const SizedBox(height: 5),
            Text(
              _authError
                  ? 'sem dados locais'
                  : snapshot.windows.isNotEmpty
                  ? 'janelas ocultas'
                  : 'sem janelas de quota',
              style: TextStyle(color: palette.muted, fontSize: QdType.micro),
            ),
          ] else
            for (final entry in groups.entries) ...[
              if (showGroups &&
                  entry.key != null &&
                  entry.key!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 3),
                  child: Text(
                    entry.key!.toUpperCase(),
                    style: TextStyle(
                      color: palette.dim,
                      fontSize: QdType.micro,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                )
              else
                const SizedBox(height: 6),
              for (var i = 0; i < entry.value.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _MiniWindowRow(window: entry.value[i]),
              ],
            ],
          if (widget.onDemandWindows.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('mini-ondemand-${snapshot.provider.name}'),
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 13,
                ),
                label: Text(
                  _expanded
                      ? 'Mostrar menos'
                      : 'mais ${widget.onDemandWindows.length}',
                  style: const TextStyle(fontSize: QdType.micro),
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 24),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniWindowRow extends StatelessWidget {
  const _MiniWindowRow({required this.window});

  final QuotaWindow window;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final reset = window.resetsAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                window.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formatPercent(window.usedPercent)}%',
              style: TextStyle(
                color: QuotaBar.colorFor(context, window.status),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        QuotaBar(
          usedPercent: window.usedPercent,
          status: window.status,
          height: 4,
        ),
        if (reset != null) ...[
          const SizedBox(height: 2),
          Text(
            'reset ${relativeTime(reset)}',
            style: TextStyle(color: palette.dim, fontSize: QdType.micro),
          ),
        ],
      ],
    );
  }
}

class _MiniLoading extends StatelessWidget {
  const _MiniLoading();

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      alignment: Alignment.center,
      child: Column(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(height: 10),
          Text(
            'Lendo credenciais locais…',
            style: TextStyle(color: palette.muted, fontSize: QdType.meta),
          ),
        ],
      ),
    );
  }
}

class _MiniEmpty extends StatelessWidget {
  const _MiniEmpty({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.error ?? 'Nenhum provedor detectado.',
            style: TextStyle(
              color: palette.muted,
              fontSize: QdType.small,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => unawaited(state.retry()),
                child: const Text('Verificar'),
              ),
              TextButton(
                onPressed: () => unawaited(showProviderWizard(context)),
                child: const Text('Assistente'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: FilledButton.icon(
        key: const Key('mini-open-dashboard'),
        onPressed: () => unawaited(openDashboardWindow(state)),
        icon: const Icon(Icons.open_in_full, size: 15),
        label: const Text('Abrir dashboard'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          textStyle: const TextStyle(
            fontSize: QdType.meta,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }
}
