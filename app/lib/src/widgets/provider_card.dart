import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final (colors, initials) = switch (provider) {
      ProviderId.opencode => (
        const [Color(0xFF3DDC97), Color(0xFF1F9E6B)],
        'OC',
      ),
      ProviderId.antigravity => (
        const [Color(0xFF6EA8FE), Color(0xFFB197FC)],
        'AG',
      ),
      ProviderId.codex => (const [Color(0xFFE8EBF2), Color(0xFF9AA4B8)], 'CX'),
      ProviderId.claude => (const [Color(0xFFF5C451), Color(0xFFE08A3C)], 'CL'),
    };

    return Semantics(
      label: provider.displayName,
      image: true,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: TextStyle(
            color: const Color(0xFF0B0D11),
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

/// Card de um provedor. Renderiza janelas agrupadas, erros de auth e cache.
class ProviderCard extends StatelessWidget {
  const ProviderCard({
    super.key,
    required this.snapshot,
    this.compact = false,
    this.onRetry,
    this.onAuthAction,
    this.onOpenWizard,
  });

  final ProviderSnapshot snapshot;
  final bool compact;
  final VoidCallback? onRetry;
  final VoidCallback? onAuthAction;
  final VoidCallback? onOpenWizard;

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
            if (snapshot.windows.isNotEmpty) ...[
              if (snapshot.hasError) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.history, size: 12, color: palette.dim),
                    const SizedBox(width: 5),
                    Text(
                      snapshot.sourceId == 'claude-desktop-history'
                          ? 'Histórico local do Desktop (estimado)'
                          : 'Último snapshot em cache',
                      style: TextStyle(
                        color: palette.dim,
                        fontSize: QdType.micro,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ] else
                const SizedBox(height: 9),
              ..._buildGroups(context),
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
                        minimumSize: const Size(0, 30),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'fonte: ${_friendlySource(snapshot)}',
                    style: TextStyle(
                      color: palette.dim,
                      fontSize: QdType.micro,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _confidenceLabel(snapshot.confidence) == null
                      ? 'atualizado ${relativeTime(snapshot.fetchedAt)}'
                      : 'conf. ${_confidenceLabel(snapshot.confidence)} · '
                            '${relativeTime(snapshot.fetchedAt)}',
                  style: TextStyle(color: palette.dim, fontSize: QdType.micro),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroups(BuildContext context) {
    final palette = QdPalette.of(context);
    final groups = <String?, List<QuotaWindow>>{};
    for (final window in snapshot.windows) {
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
    return widgets;
  }

  String? get _creditsLabel {
    final credits = snapshot.credits;
    if (credits == null) return null;
    final note = credits.note;
    if (note != null && note.trim().isNotEmpty) return note;
    if (credits.unlimited) return 'Créditos ilimitados';
    if (credits.balance != null) {
      final currency = credits.currency;
      return 'Saldo: ${credits.balance}${currency == null ? '' : ' $currency'}';
    }
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
    final rawEmail = snapshot.account.maskedEmail ?? '';
    final email = rawEmail.contains('*') ? rawEmail : shortEmail(rawEmail);

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
              if (email.isNotEmpty)
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.dim, fontSize: QdType.micro),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: StatusBadge(
            status: snapshot.worstWindow?.status ?? QuotaStatus.unknown,
            confidence: snapshot.confidence,
            stale: snapshot.stale,
            auth: snapshot.errors.any(
              (error) =>
                  error.code == 'AUTH_EXPIRED' || error.code == 'AUTH_MISSING',
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
                color: palette.text,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 4 : 5),
        QuotaBar(
          usedPercent: window.usedPercent,
          status: window.status,
          height: compact ? 5 : 6,
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Tooltip(
              message: reset == null
                  ? 'Sem reset previsto'
                  : 'Reset em ${DateFormat('dd/MM/yyyy HH:mm').format(reset.toLocal())}',
              child: Text(
                resetLabel,
                style: TextStyle(color: palette.dim, fontSize: QdType.micro),
              ),
            ),
            const Spacer(),
            Text(
              _sourceLabel(window.source),
              style: TextStyle(color: palette.dim, fontSize: QdType.micro),
            ),
          ],
        ),
      ],
    );
  }

  static String _sourceLabel(SourceKind source) => switch (source) {
    SourceKind.api => 'API',
    SourceKind.rpc => 'RPC local',
    SourceKind.appServer => 'app-server',
    SourceKind.cli => 'CLI',
    SourceKind.headers => 'headers',
    SourceKind.log => 'histórico local',
    SourceKind.cache => 'cache',
  };
}

String _friendlySource(ProviderSnapshot snapshot) {
  final id = snapshot.sourceId ?? snapshot.source;
  return switch (id) {
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

String? _confidenceLabel(Confidence confidence) => switch (confidence) {
  Confidence.high => 'alta',
  Confidence.medium => 'média',
  Confidence.low => 'baixa',
  Confidence.none => null,
};

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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.muted,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: QdType.meta),
                  ),
                  child: const Text('Já renovei'),
                ),
              const SizedBox(width: 4),
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
                  minimumSize: const Size(0, 32),
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
                    minimumSize: const Size(0, 30),
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

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
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
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: palette.red,
                    minimumSize: const Size(0, 28),
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
            error.message,
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
