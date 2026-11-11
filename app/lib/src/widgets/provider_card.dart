import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../theme.dart';
import 'quota_bar.dart';
import 'status_badge.dart';
import 'surface_chip.dart';

class ProviderAvatar extends StatelessWidget {
  const ProviderAvatar({super.key, required this.provider, this.size = 24});

  final ProviderId provider;
  final double size;

  static const _svgLogos = {
    ProviderId.claude: 'assets/providers/claude.svg',
    ProviderId.codex: 'assets/providers/codex.svg',
  };

  static const _pngLogos = {
    ProviderId.opencode: 'assets/providers/opencode.png',
    ProviderId.antigravity: 'assets/providers/antigravity.png',
  };

  @override
  Widget build(BuildContext context) {
    final svg = _svgLogos[provider];
    final png = _pngLogos[provider];
    final Widget logo = svg != null
        ? SvgPicture.asset(svg, width: size, height: size)
        : Image.asset(
            png!,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          );

    return Semantics(
      label: provider.displayName,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: logo),
      ),
    );
  }
}

/// Card de um provedor. Renderiza janelas agrupadas, erros de auth e cache.
class ProviderCard extends StatefulWidget {
  const ProviderCard({
    super.key,
    required this.snapshot,
    this.compact = false,
    this.onRetry,
    this.onAuthAction,
    this.onOpenWizard,
    this.onOpenCustomize,
    this.windows,
    this.onDemandWindows = const [],
  });

  final ProviderSnapshot snapshot;
  final bool compact;
  final VoidCallback? onRetry;
  final VoidCallback? onAuthAction;
  final VoidCallback? onOpenWizard;

  /// Abre a personalização do painel a partir do aviso de janelas ocultas.
  final VoidCallback? onOpenCustomize;

  /// Janelas sempre visíveis. `null` usa todas as janelas do snapshot.
  final List<QuotaWindow>? windows;

  /// Janelas atrás do "mostrar mais".
  final List<QuotaWindow> onDemandWindows;

  @override
  State<ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<ProviderCard> {
  bool _expanded = false;

  ProviderSnapshot get snapshot => widget.snapshot;
  bool get compact => widget.compact;
  VoidCallback? get onRetry => widget.onRetry;
  VoidCallback? get onAuthAction => widget.onAuthAction;
  VoidCallback? get onOpenWizard => widget.onOpenWizard;

  List<QuotaWindow> get _alwaysWindows => widget.windows ?? snapshot.windows;

  bool get _isAuthError => snapshot.errors.any(
    (error) =>
        error.code == 'AUTH_EXPIRED' ||
        error.code == 'AUTH_MISSING' ||
        error.code == 'PERMISSION_DENIED',
  );

  QdeckErrorInfo? get _authError {
    for (final error in snapshot.errors) {
      if (error.code == 'AUTH_EXPIRED' ||
          error.code == 'AUTH_MISSING' ||
          error.code == 'PERMISSION_DENIED') {
        return error;
      }
    }
    return null;
  }

  QdeckErrorInfo? get _otherError {
    for (final error in snapshot.errors) {
      if (error.code != 'AUTH_EXPIRED' &&
          error.code != 'AUTH_MISSING' &&
          error.code != 'PERMISSION_DENIED') {
        return error;
      }
    }
    return null;
  }

  bool get _isNotInstalled =>
      snapshot.errors.any((error) => error.code == 'NOT_INSTALLED');

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final borderColor = _isAuthError
        ? palette.yellow.withValues(alpha: 0.45)
        : _otherError != null
        ? palette.red.withValues(alpha: 0.4)
        : palette.border;
    final cardGradient = _isAuthError
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.yellow.withValues(alpha: 0.08), palette.panel2],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.text.withValues(alpha: 0.022), palette.panel2],
          );

    return Semantics(
      container: true,
      label: 'Provedor ${snapshot.provider.displayName}',
      child: Container(
        key: Key('provider-card-${snapshot.provider.name}'),
        padding: EdgeInsets.all(compact ? 11 : 12),
        decoration: BoxDecoration(
          gradient: cardGradient,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(snapshot: snapshot, compact: compact),
            if (_isNotInstalled) ...[
              const SizedBox(height: 9),
              _NotInstalledPanel(
                snapshot: snapshot,
                onOpenWizard: onOpenWizard,
              ),
            ] else if (_authError != null) ...[
              const SizedBox(height: 9),
              _AuthPanel(
                snapshot: snapshot,
                error: _authError!,
                onAction: onAuthAction,
                onRetry: onRetry,
              ),
            ] else if (_otherError != null) ...[
              const SizedBox(height: 9),
              _ErrorPanel(error: _otherError!, onRetry: onRetry),
            ],
            if (_alwaysWindows.isNotEmpty ||
                widget.onDemandWindows.isNotEmpty) ...[
              if (snapshot.hasError) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.history, size: 12, color: palette.dim),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        snapshot.sourceId == 'claude-desktop-history'
                            ? 'Histórico local do Desktop (estimado)'
                            : 'Último snapshot em cache',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.dim,
                          fontSize: QdType.micro,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else
                const SizedBox(height: 9),
              ..._buildGroups(context),
            ] else if (snapshot.windows.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: Key('provider-customize-${snapshot.provider.name}'),
                  onPressed: widget.onOpenCustomize,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: const TextStyle(fontSize: QdType.small),
                  ),
                  child: const Text(
                    'Todas as janelas estão ocultas · Personalizar',
                  ),
                ),
              ),
            ] else if (_isNotInstalled) ...[
              const SizedBox(height: 8),
              Text(
                'Ative o assistente para instalar ou conectar este provedor.',
                style: TextStyle(color: palette.muted, fontSize: QdType.small),
              ),
            ] else if (!snapshot.hasError) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Nenhuma janela de quota disponível.',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: QdType.small,
                      ),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text(
                        'Tentar',
                        style: TextStyle(fontSize: QdType.meta),
                      ),
                    ),
                ],
              ),
            ],
            if (_creditsLabel != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: palette.panel.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 12, color: palette.dim),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _creditsLabel!,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: QdType.meta,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (snapshot.stale ||
                snapshot.hasError ||
                snapshot.confidence != Confidence.high) ...[
              const SizedBox(height: 6),
              Text(
                '${_friendlySource(snapshot)} · '
                '${relativeTime(snapshot.fetchedAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.dim, fontSize: QdType.micro),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroups(BuildContext context) {
    final palette = QdPalette.of(context);
    final groups = <String?, List<QuotaWindow>>{};
    final windows = [
      ..._alwaysWindows,
      if (_expanded) ...widget.onDemandWindows,
    ];
    for (final window in sortWindowsForDisplay(windows)) {
      groups.putIfAbsent(window.group, () => []).add(window);
    }

    final widgets = <Widget>[];
    var firstGroup = true;
    for (final entry in groups.entries) {
      if (entry.key != null && entry.key!.trim().isNotEmpty) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: firstGroup ? 0 : 10, bottom: 4),
            child: Text(
              entry.key!.toUpperCase(),
              style: TextStyle(
                color: palette.dim,
                fontSize: QdType.micro,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
        firstGroup = false;
      }
      for (var i = 0; i < entry.value.length; i++) {
        if (i > 0) widgets.add(const SizedBox(height: 9));
        widgets.add(_WindowRow(window: entry.value[i], compact: compact));
      }
    }
    if (widget.onDemandWindows.isNotEmpty) {
      widgets.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: Key('provider-ondemand-${snapshot.provider.name}'),
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 14,
            ),
            label: Text(
              _expanded
                  ? 'Mostrar menos'
                  : 'Mostrar mais (${widget.onDemandWindows.length})',
              style: const TextStyle(fontSize: QdType.meta),
            ),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  String? get _creditsLabel {
    final credits = snapshot.credits;
    if (credits == null) return null;
    final note = credits.note?.trim();
    final hasNote = note != null && note.isNotEmpty;
    if (credits.unlimited) {
      return hasNote ? 'Créditos ilimitados · $note' : 'Créditos ilimitados';
    }
    final balance = credits.balance;
    if (balance != null && balance > 0) {
      final currency = credits.currency;
      final amount = NumberFormat.simpleCurrency(
        locale: 'pt_BR',
        name: currency ?? 'BRL',
      ).format(balance);
      final value = 'Saldo: $amount';
      return hasNote ? '$value · $note' : value;
    }
    if (hasNote) return note;
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.snapshot, required this.compact});

  final ProviderSnapshot snapshot;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final plan = snapshot.account.plan;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProviderAvatar(provider: snapshot.provider, size: compact ? 22 : 24),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 5,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    snapshot.provider.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (plan != null && plan.trim().isNotEmpty)
                    Text(
                      plan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: QdType.meta,
                      ),
                    ),
                  if (snapshot.surface != null)
                    SurfaceChip(
                      surface: snapshot.surface!,
                      authenticated:
                          snapshot.errors.isEmpty &&
                          snapshot.windows.isNotEmpty,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Align(
            alignment: Alignment.topRight,
            child: StatusBadge(
              status: snapshot.worstWindow?.status ?? QuotaStatus.unknown,
              confidence: snapshot.confidence,
              stale: snapshot.stale,
              auth: snapshot.errors.any(
                (error) =>
                    error.code == 'AUTH_EXPIRED' ||
                    error.code == 'AUTH_MISSING',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WindowRow extends StatelessWidget {
  const _WindowRow({required this.window, required this.compact});

  final QuotaWindow window;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final reset = window.resetsAt;
    final resetLabel = reset == null
        ? 'sem reset'
        : 'reset ${relativeTime(reset)}';
    final used = formatPercent(window.usedPercent);
    final remaining = formatPercent(window.remainingPercent);

    return Semantics(
      container: true,
      label: '${window.label}: $used por cento usado, restam $remaining, '
          '$resetLabel',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
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
              Tooltip(
                message: 'Restam $remaining%',
                child: Text(
                  '$used%',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    letterSpacing: -0.2,
                    fontFeatures: QdType.numeric,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 5),
          QuotaBar(
            usedPercent: window.usedPercent,
            status: window.status,
            height: compact ? 6 : 8,
          ),
          const SizedBox(height: 3),
          Text(
            resetLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.dim, fontSize: QdType.micro),
          ),
        ],
      ),
    );
  }
}

String _friendlySource(ProviderSnapshot snapshot) {
  final id = snapshot.sourceId ?? snapshot.source;
  return switch (id) {
    'claude-desktop-oauth' => 'sessão do Claude Desktop (ao vivo)',
    'claude-desktop-history' => 'histórico local do Claude Desktop (estimado)',
    'claude-oauth-usage' => 'API do Claude Code',
    'opencode-db' => 'banco local do OpenCode',
    'opencode-usage-api' => 'API do OpenCode',
    'codex-app-server' => 'app-server do Codex',
    'codex-wham-usage' => 'API de uso do Codex',
    'antigravity-language-server' => 'RPC local do Antigravity',
    _ => snapshot.source,
  };
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.snapshot,
    required this.error,
    required this.onAction,
    required this.onRetry,
  });

  final ProviderSnapshot snapshot;
  final QdeckErrorInfo error;
  final VoidCallback? onAction;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final missing = error.code == 'AUTH_MISSING';
    final title = missing ? 'Credencial ausente' : 'Sessão expirada';
    final message = error.message.trim().isEmpty
        ? 'Renove o login na ferramenta original.'
        : error.message;

    return Container(
      key: Key('auth-panel-${snapshot.provider.name}'),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: palette.yellow.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.yellow.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_clock, size: 14, color: palette.yellow),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: palette.yellow,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            message,
            style: TextStyle(
              color: palette.muted,
              fontSize: QdType.small,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            runSpacing: 4,
            children: [
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.muted,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: QdType.meta),
                  ),
                  child: const Text('Já renovei'),
                ),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.open_in_new, size: 13),
                label: const Text('Como renovar'),
                style: TextButton.styleFrom(
                  foregroundColor: palette.yellow,
                  backgroundColor: palette.yellow.withValues(alpha: 0.1),
                  side: BorderSide(
                    color: palette.yellow.withValues(alpha: 0.4),
                  ),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(
                    fontSize: QdType.meta,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotInstalledPanel extends StatelessWidget {
  const _NotInstalledPanel({
    required this.snapshot,
    required this.onOpenWizard,
  });

  final ProviderSnapshot snapshot;
  final VoidCallback? onOpenWizard;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      key: Key('not-installed-panel-${snapshot.provider.name}'),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.extension_off, size: 14, color: palette.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Não instalado',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onOpenWizard != null)
                TextButton(
                  onPressed: onOpenWizard,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: QdType.meta),
                  ),
                  child: const Text('Abrir assistente'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Esta ferramenta não foi encontrada nesta máquina. '
            'O painel continua mostrando o card porque ela está habilitada.',
            style: TextStyle(
              color: palette.muted,
              fontSize: QdType.small,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final QdeckErrorInfo error;
  final VoidCallback? onRetry;

  DateTime? get _retryAt => parseDate(error.details?['retryAt']);

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final retryAt = _retryAt;
    final blocked = retryAt != null && retryAt.isAfter(DateTime.now().toUtc());
    return Container(
      key: const Key('provider-error-panel'),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: palette.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 14, color: palette.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  switch (error.code) {
                    'NO_SUBSCRIPTION' => 'Sem assinatura',
                    'API_KEY_MODE' => 'Modo API key',
                    'CREDENTIAL_UNREADABLE' => 'Credencial ilegível',
                    'RATE_LIMITED' => 'Rate limit',
                    _ => 'Falha ao consultar',
                  },
                  style: TextStyle(
                    color: palette.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onRetry != null && !blocked)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.red,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text(
                    'Tentar',
                    style: TextStyle(fontSize: QdType.meta),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            blocked
                ? 'Nova tentativa ${relativeTime(retryAt)}.'
                : error.message,
            style: TextStyle(
              color: palette.muted,
              fontSize: QdType.small,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
