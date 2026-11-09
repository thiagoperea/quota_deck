import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
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
    final compact = widget.compact || viewportWidth < 520;

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
    final provider = snapshot.provider;
    final command = switch (provider) {
      ProviderId.opencode => 'opencode',
      ProviderId.codex => 'codex',
      ProviderId.claude => 'claude',
      ProviderId.antigravity => null,
    };

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Renovar ${provider.displayName}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'O QuotaDeck não renova tokens automaticamente. '
                'Abra o aplicativo original para renovar o login.',
              ),
              const SizedBox(height: 12),
              if (command != null) ...[
                Text(
                  'No terminal, execute:',
                  style: TextStyle(color: palette.muted, fontSize: 11.5),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.panel2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.border),
                  ),
                  child: SelectableText(
                    command,
                    style: TextStyle(
                      color: palette.green,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Conclua o login na ferramenta e volte para atualizar.',
                  style: TextStyle(color: palette.muted, fontSize: 11.5),
                ),
              ] else
                Text(
                  'Abra o aplicativo Antigravity, faça login e volte para atualizar.',
                  style: TextStyle(color: palette.muted, fontSize: 11.5),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
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
        _LogoMark(size: compact ? 28 : 34),
        SizedBox(width: compact ? 8 : 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QuotaDeck',
                style: TextStyle(
                  color: palette.text,
                  fontSize: compact ? 14 : 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'local-first · $enabled provedores',
                    style: TextStyle(color: palette.muted, fontSize: 10.5),
                  ),
                ),
            ],
          ),
        ),
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
    final size = compact ? 30.0 : 34.0;
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

    final mostUsedValue = mostUsed == null
        ? '—'
        : mostUsed.snapshot.provider.displayName;
    final mostUsedSubtitle = mostUsed == null
        ? 'Sem janelas de quota'
        : '${mostUsed.window.label} · '
              '${formatPercent(mostUsed.window.usedPercent)}% usado';
    final mostUsedColor = mostUsed == null
        ? palette.dim
        : QuotaBar.colorFor(context, mostUsed.window.status);

    final resetValue = nextReset == null
        ? '—'
        : _formatResetValue(nextReset.window.resetsAt!);
    final resetSubtitle = nextReset == null
        ? 'Nenhum reset agendado'
        : '${nextReset.snapshot.provider.displayName} · '
              '${nextReset.window.label}';

    final availableValue = available == null
        ? '—'
        : '${formatPercent(available)}%';
    final availableSubtitle = mostUsed == null
        ? 'Sem dados para estimar'
        : 'pior janela · ${mostUsed.snapshot.provider.displayName}';
    final availableColor = available == null
        ? palette.dim
        : available >= 50
        ? palette.green
        : available >= 20
        ? palette.yellow
        : palette.red;

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.panel2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROVEDOR MAIS USADO',
              style: TextStyle(
                color: palette.dim,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              mostUsedValue,
              style: TextStyle(
                color: mostUsedColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              mostUsedSubtitle,
              style: TextStyle(color: palette.muted, fontSize: 9.5),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Divider(height: 1, color: palette.border),
            ),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'PRÓXIMO RESET',
                    value: resetValue,
                    subtitle: resetSubtitle,
                    color: palette.yellow,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniStat(
                    label: 'USO DISPONÍVEL ESTIMADO',
                    value: availableValue,
                    subtitle: availableSubtitle,
                    color: availableColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _StatCard(
            label: 'Provedor mais usado',
            value: mostUsedValue,
            subtitle: mostUsedSubtitle,
            color: mostUsedColor,
          ),
          _StatCard(
            label: 'Próximo reset',
            value: resetValue,
            subtitle: resetSubtitle,
            color: palette.yellow,
          ),
          _StatCard(
            label: 'Uso disponível estimado',
            value: availableValue,
            subtitle: availableSubtitle,
            color: availableColor,
          ),
        ];
        if (constraints.maxWidth >= 640) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
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

class _StatCard extends StatelessWidget {
  const _StatCard({
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
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.text.withValues(alpha: 0.025), palette.panel2],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: palette.dim,
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 10, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
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
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.dim,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: palette.muted, fontSize: 9),
        ),
      ],
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
        ),
    ];

    final side = [
      _ResetsPanel(state: state, compact: compact),
      SizedBox(height: compact ? 10 : 12),
      _TrendPanel(state: state, compact: compact),
    ];

    return LayoutBuilder(
      builder: (context, _) {
        final wide = !compact && MediaQuery.sizeOf(context).width >= 900;
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
      trailing: '48h',
      compact: compact,
      child: resets.isEmpty
          ? Text(
              'Nenhum reset agendado.',
              style: TextStyle(color: palette.muted, fontSize: 10.5),
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
                    fontSize: compact ? 10 : 10.5,
                  ),
                ),
                Text(
                  '${_formatWhen(resetAt)} · ${relativeTime(resetAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.muted, fontSize: 9),
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
                fontSize: 9,
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
    final color = quota == null
        ? palette.green
        : QuotaBar.colorFor(context, quota.window.status);

    return _Panel(
      title: 'Tendência',
      trailing: quota == null
          ? '24h'
          : '${quota.snapshot.provider.displayName} · ${quota.window.label}',
      compact: compact,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sparkline(values: values, color: color, height: compact ? 42 : 54),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('uso', style: TextStyle(color: palette.dim, fontSize: 9)),
              const SizedBox(width: 10),
              Text(
                'warning 80%',
                style: TextStyle(color: palette.dim, fontSize: 9),
              ),
              const Spacer(),
              if (history != null)
                Text(
                  'ETA ${_formatEta(history.etaHours)}',
                  style: TextStyle(
                    color: palette.blue,
                    fontSize: 9,
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
                    fontSize: compact ? 11.5 : 12,
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
                    style: TextStyle(color: palette.dim, fontSize: 9),
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
    final version = state.meta?.version ?? '0.1.1';
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
