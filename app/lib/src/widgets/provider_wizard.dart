import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'provider_card.dart';

/// Assistente dirigido por detecção: mostra só o que está instalado,
/// com uma linha por superfície (desktop/CLI) e instruções específicas.
Future<void> showProviderWizard(
  BuildContext context, {
  bool firstRun = false,
}) async {
  final state = context.read<AppState>();
  if (!state.tryClaimWizard()) return;
  try {
    await state.detectProviders();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: !firstRun,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (_) => _ProviderWizard(state: state, firstRun: firstRun),
    );
  } finally {
    state.releaseWizard();
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
  bool _showAll = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.firstRun) return;
    final installed = widget.state.installedProviders;
    final allAuthenticated =
        installed.isNotEmpty &&
        installed.every(
          (provider) =>
              widget.state.detectionFor(provider)?.authenticated == true,
        );
    if (allAuthenticated) _index = _steps.length;
  }

  List<ProviderId> get _steps {
    final installed = widget.state.installedProviders.toSet();
    if (_showAll) return ProviderId.values;
    return [
      for (final provider in ProviderId.values)
        if (installed.contains(provider)) provider,
    ];
  }

  int get _totalSteps => _steps.isEmpty ? 1 : _steps.length + 1;

  bool get _isSummary => _steps.isEmpty || _index >= _steps.length;

  ProviderId get _current =>
      _steps[_index < _steps.length ? _index : _steps.length - 1];

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
    final authError = snapshot?.errors.any(
      (error) =>
          error.code == 'AUTH_EXPIRED' ||
          error.code == 'AUTH_MISSING' ||
          error.code == 'PERMISSION_DENIED' ||
          error.code == 'NOT_INSTALLED' ||
          error.code == 'CREDENTIAL_UNREADABLE',
    );
    if (snapshot != null && snapshot.windows.isNotEmpty && authError != true) {
      return _ProviderStatus.connected;
    }
    final detection = widget.state.detectionFor(provider);
    if (detection != null) {
      if (detection.authenticated) return _ProviderStatus.credentialFound;
      if (detection.detected) return _ProviderStatus.signInNeeded;
      return _ProviderStatus.notDetected;
    }
    if (snapshot != null && snapshot.windows.isNotEmpty) {
      return _ProviderStatus.connected;
    }
    return _ProviderStatus.notDetected;
  }

  Future<void> _verify(ProviderId provider) async {
    if (_checking.contains(provider)) return;
    setState(() => _checking.add(provider));
    await Future.wait([
      widget.state.detectProviders(),
      widget.state.refresh(provider: provider),
    ]);
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

  Future<void> _close() async {
    if (widget.firstRun) {
      await _finish();
      return;
    }
    Navigator.of(context).maybePop();
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
                      ? 'Detectamos o que está instalado. Um provedor por vez.'
                      : 'Revise o que aparece no painel e como renovar o login.',
                  style: TextStyle(color: palette.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('wizard-close'),
            onPressed: _saving ? null : _close,
            tooltip: 'Fechar assistente',
            icon: const Icon(Icons.close, size: 17),
          ),
        ],
      ),
    );
  }

  Widget _progress(QdPalette palette) {
    final stepLabel = _isSummary
        ? 'Resumo · etapa ${_index + 1} de $_totalSteps'
        : 'Etapa ${_index + 1} de $_totalSteps';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stepLabel,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.state.detecting)
                Icon(Icons.radar, size: 11, color: palette.dim)
              else
                Text(
                  '${((_index + 1) / _totalSteps * 100).round()}%',
                  style: TextStyle(color: palette.dim, fontSize: 9),
                ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_index + 1) / _totalSteps,
              minHeight: 4,
              backgroundColor: palette.panel2,
              valueColor: AlwaysStoppedAnimation<Color>(palette.green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerStep(QdPalette palette, ProviderId provider) {
    final guide = _guideFor(provider);
    final detection = widget.state.detectionFor(provider);
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
        _sectionLabel(palette, 'SUPERFÍCIES DETECTADAS'),
        const SizedBox(height: 7),
        if (detection == null || detection.surfaces.isEmpty)
          Text(
            'Detecção ainda não rodou para este provedor.',
            style: TextStyle(color: palette.dim, fontSize: 10),
          )
        else
          for (final surface in detection.surfaces) ...[
            _SurfaceRow(surface: surface),
            const SizedBox(height: 6),
          ],
        const SizedBox(height: 6),
        _sectionLabel(palette, 'COMO CONECTAR'),
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

  Widget _sectionLabel(QdPalette palette, String text) {
    return Text(
      text,
      style: TextStyle(
        color: palette.dim,
        fontSize: 8.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
      ),
    );
  }

  Widget _summary(QdPalette palette) {
    final enabled = ProviderId.values.where(_isEnabled).toList(growable: false);
    final nothingDetected = _steps.isEmpty;
    final hidden = [
      for (final provider in ProviderId.values)
        if (!_steps.contains(provider)) provider,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          nothingDetected ? 'Nenhuma ferramenta detectada' : 'Tudo pronto',
          style: TextStyle(
            color: palette.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          nothingDetected
              ? 'Abra o app ou rode o CLI de um provedor e use "Verificar de novo". '
                    'Você também pode habilitar manualmente abaixo.'
              : enabled.isEmpty
              ? 'Nenhum provedor ativo. Você pode ativar depois nas configurações.'
              : '${enabled.length} de ${ProviderId.values.length} provedores aparecem no painel.',
          style: TextStyle(color: palette.muted, fontSize: 11, height: 1.45),
        ),
        if (nothingDetected) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('wizard-redetect'),
            onPressed: widget.state.detecting
                ? null
                : () async {
                    await widget.state.detectProviders();
                    if (!mounted) return;
                    setState(() {});
                  },
            icon: widget.state.detecting
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.green,
                    ),
                  )
                : const Icon(Icons.refresh, size: 14),
            label: const Text('Verificar de novo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.text,
              side: BorderSide(color: palette.border),
              minimumSize: const Size(0, 36),
              textStyle: const TextStyle(fontSize: 10.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (final provider in ProviderId.values) ...[
          _SummaryRow(
            provider: provider,
            enabled: _isEnabled(provider),
            status: _statusFor(provider),
            detection: widget.state.detectionFor(provider),
            onChanged: (value) => _setEnabled(provider, value),
          ),
          if (provider != ProviderId.values.last) const SizedBox(height: 8),
        ],
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            key: const Key('wizard-show-all'),
            onPressed: () => setState(() {
              _showAll = true;
              _index = 0;
            }),
            icon: const Icon(Icons.search, size: 14),
            label: Text(
              'Mostrar ${hidden.length} provedor'
              '${hidden.length == 1 ? '' : 'es'} não detectado'
              '${hidden.length == 1 ? '' : 's'}',
            ),
            style: TextButton.styleFrom(
              foregroundColor: palette.muted,
              textStyle: const TextStyle(fontSize: 10.5),
            ),
          ),
        ],
        const SizedBox(height: 10),
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

enum _ProviderStatus {
  connected,
  credentialFound,
  signInNeeded,
  noData,
  notDetected,
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _ProviderStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final (label, color) = switch (status) {
      _ProviderStatus.connected => ('conectado', palette.green),
      _ProviderStatus.credentialFound => (
        'credencial encontrada',
        palette.blue,
      ),
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

class _SurfaceRow extends StatelessWidget {
  const _SurfaceRow({required this.surface});

  final SurfaceState surface;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final color = surface.authenticated
        ? palette.green
        : surface.installed
        ? palette.yellow
        : palette.dim;
    final state = surface.authenticated
        ? 'conectado'
        : surface.installed
        ? 'login necessário'
        : 'ausente';
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Text(
              surface.surface.label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      state,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (surface.version != null)
                      Text(
                        'v${surface.version}',
                        style: TextStyle(color: palette.dim, fontSize: 9),
                      ),
                    if (!surface.live)
                      Text(
                        'histórico',
                        style: TextStyle(color: palette.blue, fontSize: 9),
                      ),
                  ],
                ),
                if ((surface.reason ?? '').isNotEmpty)
                  Text(
                    surface.reason!,
                    style: TextStyle(
                      color: palette.muted,
                      fontSize: 9.5,
                      height: 1.3,
                    ),
                  ),
                if ((surface.location ?? '').isNotEmpty)
                  Text(
                    surface.location!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.dim, fontSize: 8.5),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.provider,
    required this.enabled,
    required this.status,
    required this.detection,
    required this.onChanged,
  });

  final ProviderId provider;
  final bool enabled;
  final _ProviderStatus status;
  final DetectionResult? detection;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final surfaces = detection?.installedSurfaces ?? const <SurfaceState>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 4, 6),
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
                Wrap(
                  spacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      provider.displayName,
                      style: TextStyle(
                        color: enabled ? palette.text : palette.dim,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final surface in surfaces)
                      Text(
                        surface.surface.label,
                        style: TextStyle(
                          color: surface.authenticated
                              ? palette.green
                              : palette.yellow,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
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
        'Lê o banco local do OpenCode (desktop ou CLI) e consulta a API de uso '
        'do plano Go/Zen.',
    command: 'opencode',
    steps: [
      'Desktop: abra o OpenCode e faça login na conta certa.',
      'CLI: rode opencode no terminal e faça login.',
      'O banco fica em ~/.local/share/opencode/opencode.db (ou XDG_DATA_HOME).',
    ],
    hint: 'Desktop e CLI compartilham o mesmo banco.',
  ),
  ProviderId.antigravity => const _ProviderGuide(
    summary:
        'Converte o RPC local do Antigravity (language_server) em janelas de '
        'quota para Gemini e Claude/GPT.',
    steps: [
      'Abra o app Antigravity e faça login.',
      'Mantenha o Antigravity aberto: o QuotaDeck lê o RPC em 127.0.0.1.',
      'Sem dados? Feche e abra o Antigravity para reiniciar o language_server.',
    ],
    hint: 'Só existe superfície desktop.',
  ),
  ProviderId.codex => const _ProviderGuide(
    summary:
        'Usa o auth.json compartilhado entre Codex desktop e CLI e consulta o '
        'uso pelo app-server ou wham.',
    command: 'codex',
    steps: [
      'Abra o Codex (desktop) ou rode codex no terminal e faça login.',
      'A sessão fica em ~/.codex/auth.json (ou CODEX_HOME).',
      'Se expirar, refaça o login na mesma superfície.',
    ],
    hint: 'Desktop e CLI compartilham a mesma sessão.',
  ),
  ProviderId.claude => const _ProviderGuide(
    summary:
        'Claude Desktop: histórico local (estimado, sem reset). Claude Code: '
        'API ao vivo com reset.',
    command: 'claude',
    steps: [
      'Desktop: mantenha o app aberto para o histórico ser atualizado.',
      'Ao vivo: rode claude no terminal e faça login (OAuth do Claude Code).',
      'O CLI também vem embutido no Claude Desktop, em Claude-Data\\...\\claude-code.',
    ],
    hint: 'Histórico é estimado; API do CLI é a fonte precisa.',
  ),
};
