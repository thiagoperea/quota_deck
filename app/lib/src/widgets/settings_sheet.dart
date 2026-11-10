import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../state/app_state.dart';
import '../theme.dart';

Future<void> showSettingsSheet(BuildContext context) {
  final state = context.read<AppState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => SettingsSheet(state: state),
  );
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late AppConfig _initial = widget.state.config;
  late AppConfig _config = widget.state.config;
  bool _saving = false;
  bool _allowPop = false;
  String? _error;

  static const _refreshOptions = [30, 60, 120];

  bool get _dirty =>
      jsonEncode(_config.toJson()) != jsonEncode(_initial.toJson());

  int get _refreshValue => _refreshOptions.contains(_config.refreshSeconds)
      ? _config.refreshSeconds
      : 60;

  String get _themeValue => switch (_config.theme.trim().toLowerCase()) {
    'light' => 'light',
    'dark' => 'dark',
    _ => 'system',
  };

  void _setProvider(ProviderId provider, bool enabled) {
    setState(() {
      _config = _config.copyWith(
        providers: {..._config.providers, provider.wireName: enabled},
      );
    });
  }

  void _setTheme(String value) {
    setState(() => _config = _config.copyWith(theme: value));
    widget.state.applyThemePreview(value);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.state.saveSettings(_config);
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
    final messenger = ScaffoldMessenger.of(context);
    final warning = widget.state.error;
    await widget.state.refresh();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _initial = _config;
      _allowPop = true;
    });
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(warning ?? 'Configurações salvas'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: warning == null ? 2 : 5),
      ),
    );
  }

  Future<void> _discardAndPop() async {
    widget.state.applyThemePreview(_initial.theme);
    setState(() {
      _config = _initial;
      _allowPop = true;
    });
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDiscard() async {
    final palette = QdPalette.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text('As mudanças não salvas serão perdidas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            key: const Key('settings-discard'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: palette.red),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) await _discardAndPop();
  }

  Future<void> _close() async {
    if (_dirty && !_saving) {
      await _confirmDiscard();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return PopScope(
      canPop: _allowPop || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        await _confirmDiscard();
      },
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: palette.panel,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              border: Border.all(color: palette.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                _header(palette),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionLabel('Provedores'),
                        Material(
                          color: palette.panel2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: palette.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < ProviderId.values.length; i++)
                                _providerTile(
                                  ProviderId.values[i],
                                  showDivider: i > 0,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _SectionLabel('Atualização automática'),
                        _choiceWrap<int>(
                          options: _refreshOptions,
                          selected: _refreshValue,
                          label: (value) => '$value s',
                          keyFor: (value) => Key('settings-refresh-$value'),
                          onSelected: (value) => setState(() {
                            _config = _config.copyWith(refreshSeconds: value);
                          }),
                        ),
                        const SizedBox(height: 16),
                        const _SectionLabel('Tema'),
                        _choiceWrap<String>(
                          options: const ['dark', 'light', 'system'],
                          selected: _themeValue,
                          label: (value) => switch (value) {
                            'dark' => 'Escuro',
                            'light' => 'Claro',
                            _ => 'Sistema',
                          },
                          keyFor: (value) => Key('settings-theme-$value'),
                          onSelected: _setTheme,
                        ),
                        const SizedBox(height: 16),
                        const _SectionLabel('Sistema'),
                        Material(
                          color: palette.panel2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: palette.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SwitchListTile(
                            key: const Key('settings-launch-at-login'),
                            value: _config.launchAtLogin,
                            onChanged: (value) => setState(() {
                              _config = _config.copyWith(launchAtLogin: value);
                            }),
                            title: Text(
                              'Iniciar com o sistema',
                              style: TextStyle(
                                color: palette.text,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              'Abre direto na bandeja ao entrar no sistema.',
                              style: TextStyle(
                                color: palette.muted,
                                fontSize: 10,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum token é exibido ou armazenado pelo painel. '
                          'As preferências ficam neste computador.',
                          style: TextStyle(
                            color: palette.dim,
                            fontSize: QdType.meta,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
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
                              fontSize: QdType.small,
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
      ),
    );
  }

  Widget _header(QdPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configurações',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dirty ? 'Alterações não salvas' : 'Ajustes locais do painel',
                  style: TextStyle(
                    color: _dirty ? palette.yellow : palette.muted,
                    fontSize: QdType.small,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('settings-close'),
            onPressed: _saving ? null : _close,
            tooltip: 'Fechar configurações',
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _footer(QdPalette palette) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          TextButton(
            key: const Key('settings-cancel'),
            onPressed: _saving ? null : _discardAndPop,
            child: const Text('Cancelar'),
          ),
          const Spacer(),
          FilledButton(
            key: const Key('settings-save'),
            onPressed: _saving || !_dirty ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  String _surfaceSummary(ProviderId provider) {
    final detection = widget.state.detectionFor(provider);
    if (detection == null || detection.surfaces.isEmpty) {
      return 'Detectando superfícies…';
    }
    final installed = detection.installedSurfaces;
    if (installed.isEmpty) return 'Não instalado';
    return installed
        .map(
          (s) =>
              '${s.surface.label} (${s.authenticated ? 'conectado' : 'login'})',
        )
        .join(' · ');
  }

  Widget _providerTile(ProviderId provider, {required bool showDivider}) {
    final palette = QdPalette.of(context);
    return Column(
      children: [
        if (showDivider)
          Divider(height: 1, thickness: 1, color: palette.border),
        SwitchListTile(
          key: Key('settings-provider-${provider.name}'),
          value: _config.isEnabled(provider),
          onChanged: (value) => _setProvider(provider, value),
          title: Text(
            provider.displayName,
            style: TextStyle(
              color: palette.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            _surfaceSummary(provider),
            style: TextStyle(color: palette.muted, fontSize: 10),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ],
    );
  }

  Widget _choiceWrap<T>({
    required List<T> options,
    required T selected,
    required String Function(T value) label,
    required Key Function(T value) keyFor,
    required ValueChanged<T> onSelected,
  }) {
    final palette = QdPalette.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            key: keyFor(option),
            label: Text(label(option)),
            selected: option == selected,
            onSelected: (_) => onSelected(option),
            showCheckmark: false,
            labelStyle: TextStyle(
              color: option == selected ? palette.text : palette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            selectedColor: palette.green.withValues(alpha: 0.16),
            backgroundColor: palette.panel2,
            side: BorderSide(
              color: option == selected
                  ? palette.green.withValues(alpha: 0.55)
                  : palette.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: palette.dim,
          fontSize: QdType.micro,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}
