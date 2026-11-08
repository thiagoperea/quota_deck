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
  late AppConfig _config = widget.state.config;
  bool _saving = false;
  String? _error;

  static const _refreshOptions = [30, 60, 120];

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
    setState(() => _saving = false);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: palette.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              Padding(
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
                            'Ajustes locais do painel',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Fechar configurações',
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
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
                        onSelected: (value) => setState(() {
                          _config = _config.copyWith(theme: value);
                        }),
                      ),
                      const SizedBox(height: 16),
                      const _SectionLabel('Notificações'),
                      Material(
                        color: palette.panel2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: palette.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: SwitchListTile(
                          key: const Key('settings-notifications'),
                          value: _config.notificationsEnabled,
                          onChanged: (value) => setState(() {
                            _config = _config.copyWith(
                              notificationsEnabled: value,
                            );
                          }),
                          title: Text(
                            'Notificações de limite',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            'Avisar ao cruzar 80% e 95% de uso.',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 10.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Material(
                        color: palette.panel2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: palette.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          key: const Key('settings-advanced'),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            12,
                            0,
                            12,
                            4,
                          ),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          iconColor: palette.muted,
                          collapsedIconColor: palette.muted,
                          title: Text(
                            'Avançado',
                            style: TextStyle(
                              color: palette.text,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Sondagem local e renovação OAuth',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 10.5,
                            ),
                          ),
                          children: [
                            SwitchListTile(
                              key: const Key('settings-allow-probe'),
                              value: _config.allowProbe,
                              onChanged: (value) => setState(() {
                                _config = _config.copyWith(allowProbe: value);
                              }),
                              title: Text(
                                'Permitir sondagem local',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: Text(
                                'Detectar apps em execução sem fazer rede.',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 10,
                                ),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                            SwitchListTile(
                              key: const Key('settings-allow-oauth'),
                              value: _config.allowOAuthRefresh,
                              onChanged: (value) => setState(() {
                                _config = _config.copyWith(
                                  allowOAuthRefresh: value,
                                );
                              }),
                              title: Text(
                                'Renovar OAuth automaticamente',
                                style: TextStyle(
                                  color: palette.text,
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: Text(
                                'Quando o provedor permitir; desligado por padrão.',
                                style: TextStyle(
                                  color: palette.muted,
                                  fontSize: 10,
                                ),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nenhum token é exibido ou armazenado pelo painel. '
                        'As preferências ficam neste computador.',
                        style: TextStyle(
                          color: palette.dim,
                          fontSize: 9.5,
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
                            fontSize: 10.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: palette.border)),
                ),
                child: Row(
                  children: [
                    TextButton(
                      key: const Key('settings-cancel'),
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text('Cancelar'),
                    ),
                    const Spacer(),
                    FilledButton(
                      key: const Key('settings-save'),
                      onPressed: _saving ? null : _save,
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
              ),
            ],
          ),
        ),
      ),
    );
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
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}
