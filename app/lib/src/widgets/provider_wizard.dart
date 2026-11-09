import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'provider_card.dart';

/// Assistente de configuração: mostra um provedor por vez, permite ativar,
/// explica o login/refresh e valida a credencial na hora.
bool _wizardOpen = false;

Future<void> showProviderWizard(
  BuildContext context, {
  bool firstRun = false,
}) async {
  if (_wizardOpen) return;
  _wizardOpen = true;
  final state = context.read<AppState>();
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: !firstRun,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (_) => _ProviderWizard(state: state, firstRun: firstRun),
    );
  } finally {
    _wizardOpen = false;
  }
}

class _ProviderWizard extends StatefulWidget {
  const _ProviderWizard({required this.state, required this.firstRun});

  final AppState state;
  final bool firstRun;

  @override
  State<_ProviderWizard> createState() => _ProviderWizardState();
}

class _ProviderWizardState extends State<_ProviderWizard> {
  late Map<String, bool> _providers = {...widget.state.config.providers};
  final Set<ProviderId> _checking = <ProviderId>{};
  int _index = 0;
  bool _saving = false;
  String? _error;

  int get _totalSteps => ProviderId.values.length + 1;

  bool get _isSummary => _index == ProviderId.values.length;

  ProviderId get _current => ProviderId.values[_index];

  bool _isEnabled(ProviderId provider) => _providers[provider.wireName] ?? true;

  void _setEnabled(ProviderId provider, bool value) {
    setState(() {
      _providers = {..._providers, provider.wireName: value};
    });
  }

  ProviderSnapshot? _snapshotFor(ProviderId provider) {
    final results = widget.state.envelope?.results;
    if (results == null) return null;
    for (final snapshot in results) {
      if (snapshot.provider == provider) return snapshot;
    }
    return null;
  }

  _ProviderStatus _statusFor(ProviderId provider) {
    final snapshot = _snapshotFor(provider);
    if (snapshot == null) return _ProviderStatus.notDetected;
    final authError = snapshot.errors.any(
      (error) =>
          error.code == 'AUTH_EXPIRED' ||
          error.code == 'AUTH_MISSING' ||
          error.code == 'PERMISSION_DENIED',
    );
    if (authError) return _ProviderStatus.signInNeeded;
    if (snapshot.windows.isNotEmpty) return _ProviderStatus.connected;
    return _ProviderStatus.noData;
  }

  Future<void> _verify(ProviderId provider) async {
    if (_checking.contains(provider)) return;
    setState(() => _checking.add(provider));
    await widget.state.refresh(provider: provider);
    if (!mounted) return;
    setState(() => _checking.remove(provider));
  }

  void _copy(String value) {
    unawaited(Clipboard.setData(ClipboardData(text: value)));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('Comando copiado: $value'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final next = widget.state.config.copyWith(
      providers: {..._providers},
      onboardingCompleted: true,
    );
    final saved = await widget.state.saveSettings(next);
    if (!mounted) return;
    if (!saved) {
      setState(() {
        _saving = false;
        _error =
            widget.state.error ??
            'Não foi possível salvar as configurações. Tente novamente.';
      });
      return;
    }
    setState(() => _saving = false);
    unawaited(widget.state.refresh());
    Navigator.of(context).maybePop();
  }

  void _next() {
    if (_index >= _totalSteps - 1) {
      unawaited(_finish());
      return;
    }
    setState(() => _index += 1);
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index -= 1);
  }

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 470, maxHeight: maxHeight),
        child: Container(
          key: const Key('provider-wizard'),
          decoration: BoxDecoration(
            color: palette.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 36,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(palette),
              _progress(palette),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: _isSummary
                      ? _summary(palette)
                      : _providerStep(palette, _current),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 14, color: palette.red),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: palette.red,
                            fontSize: 10.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _footer(palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(QdPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: palette.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: palette.green.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.checklist_rtl, size: 17, color: palette.green),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configurar provedores',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.firstRun
                      ? 'Um provedor por vez: ative, conecte e siga.'
                      : 'Revise quem aparece no painel e como renovar o login.',
                  style: TextStyle(color: palette.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('wizard-close'),
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
            tooltip: 'Fechar assistente',
            icon: const Icon(Icons.close, size: 17),
          ),
        ],
      ),
    );
  }

  Widget _progress(QdPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_index + 1) / _totalSteps,
              minHeight: 4,
              backgroundColor: palette.panel2,
              valueColor: AlwaysStoppedAnimation<Color>(palette.green),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _isSummary
                ? 'Resumo · etapa ${_index + 1} de $_totalSteps'
                : 'Etapa ${_index + 1} de $_totalSteps',
            style: TextStyle(color: palette.dim, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _providerStep(QdPalette palette, ProviderId provider) {
    final guide = _guideFor(provider);
    final status = _statusFor(provider);
    final enabled = _isEnabled(provider);
    final checking = _checking.contains(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ProviderAvatar(provider: provider, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.displayName,
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _StatusChip(status: status),
                ],
              ),
            ),
            Switch(
              key: Key('wizard-toggle-${provider.name}'),
              value: enabled,
              onChanged: (value) => _setEnabled(provider, value),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          guide.summary,
          style: TextStyle(color: palette.muted, fontSize: 11, height: 1.45),
        ),
        if (!enabled) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: palette.panel2,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.visibility_off_outlined,
                  size: 14,
                  color: palette.dim,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Desativado: fica fora do painel, dos resets e do tray.',
                    style: TextStyle(color: palette.dim, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          'COMO CONECTAR',
          style: TextStyle(
            color: palette.dim,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 7),
        for (var i = 0; i < guide.steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _GuideStep(number: '${i + 1}', text: guide.steps[i]),
        ],
        if (guide.command != null) ...[
          const SizedBox(height: 10),
          _CommandBox(
            command: guide.command!,
            onCopy: () => _copy(guide.command!),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              key: Key('wizard-verify-${provider.name}'),
              onPressed: checking ? null : () => unawaited(_verify(provider)),
              icon: checking
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.green,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 14),
              label: const Text('Verificar agora'),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.text,
                side: BorderSide(color: palette.border),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                checking ? 'Consultando…' : guide.hint,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.dim,
                  fontSize: 9.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _summary(QdPalette palette) {
    final enabled = ProviderId.values.where(_isEnabled).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tudo pronto',
          style: TextStyle(
            color: palette.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          enabled.isEmpty
              ? 'Nenhum provedor ativo. Você pode ativar depois nas configurações.'
              : '${enabled.length} de ${ProviderId.values.length} provedores aparecem no painel.',
          style: TextStyle(color: palette.muted, fontSize: 11, height: 1.45),
        ),
        const SizedBox(height: 12),
        for (final provider in ProviderId.values) ...[
          _SummaryRow(
            provider: provider,
            enabled: _isEnabled(provider),
            status: _statusFor(provider),
            onChanged: (value) => _setEnabled(provider, value),
          ),
          if (provider != ProviderId.values.last) const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: palette.panel2,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tune, size: 14, color: palette.dim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dá para mudar isso a qualquer momento no botão do assistente '
                  'no topo ou nas configurações.',
                  style: TextStyle(
                    color: palette.dim,
                    fontSize: 10,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer(QdPalette palette) {
    final isLast = _index == _totalSteps - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          if (_index > 0)
            TextButton.icon(
              key: const Key('wizard-back'),
              onPressed: _saving ? null : _back,
              icon: const Icon(Icons.arrow_back, size: 14),
              label: const Text('Voltar'),
              style: TextButton.styleFrom(
                foregroundColor: palette.muted,
                textStyle: const TextStyle(fontSize: 11),
              ),
            )
          else
            TextButton(
              key: const Key('wizard-skip'),
              onPressed: _saving ? null : () => unawaited(_finish()),
              style: TextButton.styleFrom(
                foregroundColor: palette.dim,
                textStyle: const TextStyle(fontSize: 11),
              ),
              child: const Text('Pular'),
            ),
          const Spacer(),
          FilledButton(
            key: const Key('wizard-next'),
            onPressed: _saving ? null : _next,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: _saving
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : Text(isLast ? 'Concluir' : 'Próximo'),
          ),
        ],
      ),
    );
  }
}

enum _ProviderStatus { connected, signInNeeded, noData, notDetected }

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _ProviderStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final (label, color) = switch (status) {
      _ProviderStatus.connected => ('conectado', palette.green),
      _ProviderStatus.signInNeeded => ('login necessário', palette.yellow),
      _ProviderStatus.noData => ('sem dados', palette.blue),
      _ProviderStatus.notDetected => ('não detectado', palette.dim),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.provider,
    required this.enabled,
    required this.status,
    required this.onChanged,
  });

  final ProviderId provider;
  final bool enabled;
  final _ProviderStatus status;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 4, 4),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          ProviderAvatar(provider: provider, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.displayName,
                  style: TextStyle(
                    color: enabled ? palette.text : palette.dim,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
          ),
          Switch(
            key: Key('wizard-summary-toggle-${provider.name}'),
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.panel2,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border),
          ),
          child: Text(
            number,
            style: TextStyle(
              color: palette.muted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: palette.muted, fontSize: 10.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _CommandBox extends StatelessWidget {
  const _CommandBox({required this.command, required this.onCopy});

  final String command;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: TextStyle(
                color: palette.green,
                fontSize: 11.5,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            key: const Key('wizard-copy-command'),
            onPressed: onCopy,
            tooltip: 'Copiar comando',
            icon: Icon(Icons.copy, size: 14, color: palette.muted),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _ProviderGuide {
  const _ProviderGuide({
    required this.summary,
    required this.steps,
    required this.hint,
    this.command,
  });

  final String summary;
  final List<String> steps;
  final String hint;
  final String? command;
}

_ProviderGuide _guideFor(ProviderId provider) => switch (provider) {
  ProviderId.opencode => const _ProviderGuide(
    summary:
        'Lê o banco local do OpenCode Go e a credencial da sessão para '
        'calcular as janelas de quota.',
    command: 'opencode',
    steps: [
      'Rode `opencode` no terminal uma vez.',
      'Faça login no provedor quando o CLI pedir.',
      'A sessão fica em %LOCALAPPDATA%\\opencode\\opencode.db (Windows) '
          'ou ~/.local/share/opencode/opencode.db.',
    ],
    hint: 'Se a credencial expirar, abra o OpenCode Go de novo.',
  ),
  ProviderId.antigravity => const _ProviderGuide(
    summary:
        'Converte o RPC local do Antigravity (language_server) em janelas '
        'de quota para Gemini e Claude/GPT.',
    steps: [
      'Abra o app Antigravity e faça login.',
      'Mantenha o Antigravity aberto: o QuotaDeck lê o RPC em 127.0.0.1.',
      'Sem dados? Feche e abra o Antigravity para reiniciar o language_server.',
    ],
    hint: 'O Antigravity precisa estar rodando.',
  ),
  ProviderId.codex => const _ProviderGuide(
    summary:
        'Lê ~/.codex/auth.json (ou CODEX_HOME) e consulta o endpoint de uso '
        'do Codex.',
    command: 'codex',
    steps: [
      'Rode `codex` no terminal e faça login.',
      'Se a sessão expirar, rode `codex login` de novo.',
      'O QuotaDeck não renova o token sozinho.',
    ],
    hint: 'Sessão expirada volta a funcionar após o login.',
  ),
  ProviderId.claude => const _ProviderGuide(
    summary:
        'Lê a credencial OAuth do Claude Code e consulta o uso das janelas '
        'de 5 horas e semanal.',
    command: 'claude',
    steps: [
      'Rode `claude` no terminal e faça login.',
      'Quando o token expirar, abra o Claude Code para renovar.',
      'Windows/Linux: ~/.claude/.credentials.json. macOS: Keychain.',
    ],
    hint: 'O refresh automático é opt-in nas configurações.',
  ),
};
