import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/error_card.dart';
import '../widgets/onboarding_card.dart';
import '../widgets/provider_card.dart';
import '../widgets/provider_wizard.dart';
import '../widgets/quota_bar.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/sparkline.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.compact = false});

  final bool compact;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _wizardShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    final state = context.read<AppState>();
    await state.initialize();
    if (!mounted) return;
    if (state.config.onboardingCompleted || _wizardShown) return;
    _wizardShown = true;
    await showProviderWizard(context, firstRun: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final palette = QdPalette.of(context);
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compact = widget.compact || viewportWidth < 600;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR): () {
          unawaited(state.refresh());
        },
        const SingleActivator(LogicalKeyboardKey.keyS): () {
          unawaited(showSettingsSheet(context));
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.75, -0.95),
                radius: 1.35,
                colors: [
                  palette.panel2.withValues(
                    alpha: palette.bg.computeLuminance() < 0.2 ? 0.9 : 0.7,
                  ),
                  palette.bg,
                ],
              ),
            ),
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  key: Key(compact ? 'quota-deck-compact' : 'quota-deck-full'),
                  constraints: BoxConstraints(
                    maxWidth: widget.compact ? 420 : 1180,
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 24,
                      compact ? 10 : 22,
                      compact ? 12 : 24,
                      compact ? 16 : 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          state: state,
                          compact: compact,
                          onRefresh: () => unawaited(state.refresh()),
                          onWizard: () =>
                              unawaited(showProviderWizard(context)),
                          onSettings: () =>
                              unawaited(showSettingsSheet(context)),
                        ),
                        if (state.error != null && state.hasData) ...[
                          const SizedBox(height: 12),
                          ErrorCard(
                            dense: true,
                            message: state.error!,
                            onRetry: () => unawaited(state.refresh()),
                          ),
                        ] else if (state.globalErrors.isNotEmpty &&
                            state.visibleSnapshots.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ErrorCard(
                            dense: true,
                            message: state.globalErrors.first.message,
                            onRetry: () => unawaited(state.refresh()),
                          ),
                        ],
                        SizedBox(height: compact ? 12 : 18),
                        if (state.loading && !state.hasData)
                          _LoadingState(compact: compact)
                        else if (state.error != null && !state.hasData)
                          ErrorCard(
                            message: state.error!,
                            onRetry: () => unawaited(state.retry()),
                          )
                        else if (state.isEmpty)
                          OnboardingCard(
                            noProvidersEnabled: !state.hasProvidersEnabled,
                            onRetry: () => unawaited(state.retry()),
                            onOpenWizard: () =>
                                unawaited(showProviderWizard(context)),
                            onOpenSettings: () =>
                                unawaited(showSettingsSheet(context)),
                          )
                        else ...[
                          _SummaryStats(state: state, compact: compact),
                          SizedBox(height: compact ? 12 : 16),
                          _Content(
                            state: state,
                            compact: compact,
                            onAuthAction: (snapshot) =>
                                _showAuthInstructions(context, snapshot),
                          ),
                        ],
                        SizedBox(height: compact ? 14 : 20),
                        _Footer(state: state),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAuthInstructions(
    BuildContext context,
    ProviderSnapshot snapshot,
  ) async {
    final palette = QdPalette.of(context);
    final state = context.read<AppState>();
    final provider = snapshot.provider;
    final command = switch (provider) {
      ProviderId.opencode => 'opencode',
      ProviderId.codex => 'codex',
      ProviderId.claude => 'claude',
      ProviderId.antigravity => null,
    };
    final desktopHistory =
        provider == ProviderId.claude &&
        snapshot.surface == ProviderSurface.desktop;
    String? bundled;
    if (provider == ProviderId.claude) {
      try {
        for (final file in AppPaths.bundledClaudeBinaries()) {
          if (await file.exists()) {
            bundled = file.path;
            break;
          }
        }
      } catch (_) {}
    }

    var checking = false;
    String? result;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: Text('Como renovar ${provider.displayName}'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    desktopHistory
                        ? 'O Claude Desktop só expõe o histórico local (estimado). '
                              'Para dados ao vivo com reset, faça login no Claude Code.'
                        : 'O QuotaDeck não renova tokens automaticamente. '
                              'Faça login na ferramenta original e verifique.',
                  ),
                  const SizedBox(height: 12),
                  if (command != null) ...[
                    Text(
                      'No terminal, execute:',
                      style: TextStyle(color: palette.muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 6),
                    _CommandBox(command: command),
                    const SizedBox(height: 8),
                    Text(
                      'Conclua o login e use "Já renovei — verificar" aqui.',
                      style: TextStyle(color: palette.muted, fontSize: 11.5),
                    ),
                  ] else
                    Text(
                      'Abra o Antigravity, faça login e mantenha o app aberto.',
                      style: TextStyle(color: palette.muted, fontSize: 11.5),
                    ),
                  if (bundled != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'CLI embutida no Claude Desktop:',
                      style: TextStyle(color: palette.muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 6),
                    _CommandBox(command: bundled, small: true),
                  ],
                  if (result != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 14, color: palette.blue),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            result!,
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: checking
                    ? null
                    : () async {
                        setLocal(() {
                          checking = true;
                          result = null;
                        });
                        await state.refresh(provider: provider);
                        if (!dialogContext.mounted) return;
                        final snap = state.envelope?.byProvider(provider);
                        final authError = snap?.errors.any(
                          (error) =>
                              error.code == 'AUTH_MISSING' ||
                              error.code == 'AUTH_EXPIRED' ||
                              error.code == 'NOT_INSTALLED',
                        );
                        setLocal(() {
                          checking = false;
                          if (snap == null) {
                            result = 'Sem resposta do provedor.';
                          } else if (snap.windows.isNotEmpty &&
                              authError != true) {
                            result =
                                'Conectado: ${snap.windows.length} janela(s) lida(s).';
                          } else if (snap.errors.isNotEmpty) {
                            result = snap.errors.first.message;
                          } else {
                            result = 'Ainda sem janelas de quota legíveis.';
                          }
                        });
                      },
                child: checking
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.green,
                        ),
                      )
                    : const Text('Já renovei — verificar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CommandBox extends StatelessWidget {
  const _CommandBox({required this.command, this.small = false});

  final String command;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: SelectableText(
        command,
        maxLines: small ? 2 : 1,
        style: TextStyle(
          color: palette.green,
          fontSize: small ? 10 : 12,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.compact,
    required this.onRefresh,
    required this.onWizard,
    required this.onSettings,
  });

  final AppState state;
  final bool compact;
  final VoidCallback onRefresh;
  final VoidCallback onWizard;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final enabled = ProviderId.values.where(state.config.isEnabled).length;
    final generatedAt = state.envelope?.generatedAt;
    final updateLabel = generatedAt == null
        ? 'carregando'
        : 'Atualizado ${relativeTime(generatedAt)}';

    return Row(
      children: [
        _LogoMark(size: compact ? 30 : 34),
        if (!compact) ...[
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QuotaDeck',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'local-first · $enabled provedores',
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: QdType.meta,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else
          const Spacer(),
        if (!compact) ...[
          Tooltip(
            message: generatedAt == null
                ? 'Aguardando os dados'
                : 'Última atualização: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(generatedAt.toLocal())}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: palette.panel2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: state.refreshing ? palette.yellow : palette.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    updateLabel,
                    style: TextStyle(color: palette.muted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        _HeaderButton(
          key: const Key('header-refresh'),
          icon: state.refreshing ? Icons.sync : Icons.refresh_rounded,
          tooltip: 'Atualizar agora (R)',
          onPressed: state.refreshing ? null : onRefresh,
          compact: compact,
          busy: state.refreshing,
        ),
        const SizedBox(width: 4),
        _HeaderButton(
          key: const Key('header-wizard'),
          icon: Icons.checklist_rtl,
          tooltip: 'Assistente de provedores',
          onPressed: onWizard,
          compact: compact,
        ),
        const SizedBox(width: 4),
        _HeaderButton(
          key: const Key('header-settings'),
          icon: Icons.tune,
          tooltip: 'Configurações (S)',
          onPressed: onSettings,
          compact: compact,
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.compact,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool compact;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final size = compact ? 36.0 : 38.0;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: palette.panel2,
            side: BorderSide(color: palette.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          icon: busy
              ? SizedBox(
                  width: compact ? 14 : 16,
                  height: compact ? 14 : 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.green,
                  ),
                )
              : Icon(icon, size: compact ? 16 : 18),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Semantics(
      label: 'QuotaDeck',
      image: true,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
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
          boxShadow: [
            BoxShadow(
              color: palette.green.withValues(alpha: 0.18),
              blurRadius: 14,
              spreadRadius: -4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: size * 0.44,
          height: size * 0.44,
          decoration: BoxDecoration(
            color: palette.panel,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }
}

class _SummaryStats extends StatelessWidget {
  const _SummaryStats({required this.state, required this.compact});

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final mostUsed = state.tightest;
    final nextReset = state.nextReset;
    final available = state.estimatedAvailablePercent;

    final usedValue = mostUsed == null
        ? '—'
        : '${formatPercent(mostUsed.window.usedPercent)}%';
    final usedSubtitle = mostUsed == null
        ? 'sem janelas de quota'
        : '${mostUsed.snapshot.provider.displayName} · ${mostUsed.window.label}';
    final usedColor = mostUsed == null
        ? palette.dim
        : QuotaBar.colorFor(context, mostUsed.window.status);

    final resetValue = nextReset == null
        ? '—'
        : _formatResetValue(nextReset.window.resetsAt!);
    final resetSubtitle = nextReset == null
        ? 'nada nas próximas 48 h'
        : '${nextReset.snapshot.provider.displayName} · '
              '${nextReset.window.label}';

    final availableValue = available == null
        ? '—'
        : '${formatPercent(available)}%';
    final availableSubtitle = mostUsed == null
        ? 'sem dados para estimar'
        : 'janela mais apertada · ${mostUsed.snapshot.provider.displayName}';
    final availableColor = available == null
        ? palette.dim
        : available >= 50
        ? palette.green
        : available >= 20
        ? palette.yellow
        : palette.red;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.panel2,
          borderRadius: BorderRadius.circular(QdRadius.card),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SummaryKpi(
                label: 'MAIOR CONSUMO',
                value: usedValue,
                subtitle: usedSubtitle,
                color: usedColor,
              ),
            ),
            _KpiDivider(palette: palette),
            Expanded(
              child: _SummaryKpi(
                label: 'PRÓXIMO RESET',
                value: resetValue,
                subtitle: resetSubtitle,
                color: palette.yellow,
              ),
            ),
            _KpiDivider(palette: palette),
            Expanded(
              child: _SummaryKpi(
                label: 'DISPONÍVEL',
                value: availableValue,
                subtitle: availableSubtitle,
                color: availableColor,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _StatCard(
            key: const Key('summary-available'),
            label: 'Disponível estimado',
            value: availableValue,
            subtitle: availableSubtitle,
            color: availableColor,
            large: true,
          ),
          _StatCard(
            label: 'Maior consumo agora',
            value: usedValue,
            subtitle: usedSubtitle,
            color: usedColor,
          ),
          _StatCard(
            label: 'Próximo reset',
            value: resetValue,
            subtitle: resetSubtitle,
            color: palette.yellow,
          ),
        ];
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(flex: i == 0 ? 5 : 4, child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}

class _KpiDivider extends StatelessWidget {
  const _KpiDivider({required this.palette});

  final QdPalette palette;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 46,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: palette.border,
  );
}

class _SummaryKpi extends StatelessWidget {
  const _SummaryKpi({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.muted,
            fontSize: QdType.micro,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.dim, fontSize: QdType.micro),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    this.large = false,
  });

  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.text.withValues(alpha: 0.025), palette.panel2],
        ),
        borderRadius: BorderRadius.circular(QdRadius.card),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.muted,
              fontSize: QdType.micro,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: large ? QdType.kpi : 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              height: 1.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.dim, fontSize: QdType.meta),
          ),
        ],
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.state,
    required this.compact,
    required this.onAuthAction,
  });

  final AppState state;
  final bool compact;
  final ValueChanged<ProviderSnapshot> onAuthAction;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final snapshot in state.visibleSnapshots)
        ProviderCard(
          snapshot: snapshot,
          compact: compact,
          onRetry: () => unawaited(state.refresh(provider: snapshot.provider)),
          onAuthAction: () => onAuthAction(snapshot),
          onOpenWizard: () => unawaited(showProviderWizard(context)),
        ),
    ];

    final side = [
      _ResetsPanel(state: state, compact: compact),
      SizedBox(height: compact ? 10 : 12),
      _TrendPanel(state: state, compact: compact),
    ];

    return LayoutBuilder(
      builder: (context, _) {
        final wide = !compact && MediaQuery.sizeOf(context).width >= 980;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      cards[i],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: side,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(height: compact ? 10 : 12),
              cards[i],
            ],
            SizedBox(height: compact ? 12 : 16),
            ...side,
          ],
        );
      },
    );
  }
}

class _ResetsPanel extends StatelessWidget {
  const _ResetsPanel({required this.state, required this.compact});

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final resets = state.upcomingResets(limit: compact ? 3 : 4);
    return _Panel(
      title: 'Próximos resets',
      trailing: 'próximas 48 h',
      compact: compact,
      child: resets.isEmpty
          ? Text(
              'Nenhum reset agendado.',
              style: TextStyle(color: palette.muted, fontSize: QdType.small),
            )
          : Column(
              children: [
                for (var i = 0; i < resets.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: palette.border),
                  _ResetRow(reset: resets[i], compact: compact),
                ],
              ],
            ),
    );
  }
}

class _ResetRow extends StatelessWidget {
  const _ResetRow({required this.reset, required this.compact});

  final UpcomingReset reset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final window = reset.window;
    final resetAt = window.resetsAt!;
    final color = QuotaBar.colorFor(context, window.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          ProviderAvatar(provider: reset.snapshot.provider, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reset.snapshot.provider.displayName} · ${window.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: compact ? QdType.meta : QdType.small,
                  ),
                ),
                Text(
                  '${_formatWhen(resetAt)} · ${relativeTime(resetAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: QdType.micro,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: palette.panel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              '${formatPercent(window.usedPercent)}%',
              style: TextStyle(
                color: color,
                fontSize: QdType.micro,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.state, required this.compact});

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final quota = state.tightest;
    final history = state.featuredHistory;
    final values =
        history?.samples.map((sample) => sample.usedPercent).toList() ??
        const <double>[];
    final samples = values.length;
    final collecting = samples < 3;
    final color = quota == null
        ? palette.green
        : QuotaBar.colorFor(context, quota.window.status);

    return _Panel(
      title: 'Tendência',
      trailing: quota == null
          ? '24 h'
          : '${quota.snapshot.provider.displayName} · ${quota.window.label}',
      compact: compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (collecting)
            Container(
              height: compact ? 42 : 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(QdRadius.control),
              ),
              child: Text(
                samples == 0
                    ? 'Sem amostras ainda — a tendência aparece após 3 leituras.'
                    : 'Coletando amostras ($samples/3)…',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.dim, fontSize: QdType.meta),
              ),
            )
          else
            Sparkline(values: values, color: color, height: compact ? 42 : 54),
          const SizedBox(height: 6),
          Row(
            children: [
              _LegendDot(color: color),
              const SizedBox(width: 5),
              Text(
                'uso',
                style: TextStyle(color: palette.muted, fontSize: QdType.micro),
              ),
              const SizedBox(width: 12),
              _LegendDot(color: palette.yellow),
              const SizedBox(width: 5),
              Text(
                'atenção 80%',
                style: TextStyle(color: palette.muted, fontSize: QdType.micro),
              ),
              const Spacer(),
              if (!collecting && history?.etaHours != null)
                Text(
                  'ETA ${_formatEta(history!.etaHours)}',
                  style: TextStyle(
                    color: palette.blue,
                    fontSize: QdType.micro,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    required this.compact,
    this.trailing,
  });

  final String title;
  final Widget child;
  final bool compact;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      padding: EdgeInsets.all(compact ? 11 : 13),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: compact ? QdType.small : QdType.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null)
                Flexible(
                  child: Text(
                    trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: palette.dim,
                      fontSize: QdType.micro,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 7 : 8),
          child,
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: compact ? 28 : 44,
      ),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 14),
          Text(
            'Lendo credenciais locais…',
            style: TextStyle(
              color: palette.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'OpenCode Go · Antigravity · Codex · Claude Code',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 10),
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
    final palette = QdPalette.of(context);
    final version = state.meta?.version ?? '0.3.0';
    return Row(
      children: [
        const Spacer(),
        Text('v$version', style: TextStyle(color: palette.dim, fontSize: 9)),
      ],
    );
  }
}

String _formatResetValue(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (_sameDay(local, now)) {
    return DateFormat('HH:mm').format(local);
  }
  return DateFormat('dd/MM HH:mm').format(local);
}

String _formatWhen(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final difference = day.difference(today).inDays;
  final time = DateFormat('HH:mm').format(local);
  if (difference == 0) return 'hoje $time';
  if (difference == 1) return 'amanhã $time';
  return DateFormat('dd/MM HH:mm').format(local);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _formatEta(double? hours) {
  if (hours == null) return '—';
  if (hours < 1) return '${(hours * 60).round()} min';
  if (hours < 24) return '${_decimal(hours)} h';
  return '${_decimal(hours / 24)} d';
}

String _decimal(double value) => value.toStringAsFixed(1).replaceAll('.', ',');
