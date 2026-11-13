import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/provider_card.dart';
import '../widgets/settings_sheet.dart';

/// Abre a tela de personalização (ordem e janelas visíveis).
Future<void> showCustomizePage(BuildContext context) {
  final state = context.read<AppState>();
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => CustomizePage(state: state)));
}

class CustomizePage extends StatefulWidget {
  const CustomizePage({super.key, required this.state});

  final AppState state;

  @override
  State<CustomizePage> createState() => _CustomizePageState();
}

class _CustomizePageState extends State<CustomizePage> {
  late AppConfig _config = widget.state.config;
  Future<void> _queue = Future<void>.value();

  bool get _hasCustomization =>
      _config.providerOrder.isNotEmpty || _config.windowVisibility.isNotEmpty;

  void _apply(AppConfig next) {
    setState(() => _config = next);
    _queue = _queue.then((_) async {
      final saved = await widget.state.saveSettings(next);
      if (saved && mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Personalização salva.'),
              duration: Duration(milliseconds: 1400),
            ),
          );
      }
      if (!saved && mounted) {
        final reason = widget.state.error ?? 'Não foi possível salvar.';
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(reason),
            action: SnackBarAction(
              label: 'Tentar de novo',
              onPressed: () => _apply(_config),
            ),
          ),
        );
      }
    });
  }

  void _reset() {
    final previous = _config;
    _apply(_config.clearCustomization());
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: const Text('Ordem e visibilidade restauradas.'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () => _apply(previous),
        ),
      ),
    );
  }

  void _move(int oldIndex, int newIndex) {
    final providers =
        widget.state.visibleSnapshots
            .map((snapshot) => snapshot.provider)
            .toList(growable: true)
          ..sort(
            (a, b) =>
                _config.providerRank(a).compareTo(_config.providerRank(b)),
          );
    final moved = providers.removeAt(oldIndex);
    providers.insert(newIndex, moved);
    final ordered = <String>{
      for (final provider in providers) provider.wireName,
    };
    final rest = [
      for (final provider in ProviderId.values)
        if (!ordered.contains(provider.wireName)) provider.wireName,
    ];
    _apply(_config.copyWith(providerOrder: [...ordered, ...rest]));
  }

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final state = context.watch<AppState>();
    final snapshots = [...state.visibleSnapshots]
      ..sort(
        (a, b) => _config
            .providerRank(a.provider)
            .compareTo(_config.providerRank(b.provider)),
      );

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.panel,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Personalizar painel',
          style: TextStyle(
            color: palette.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (state.saving)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  'Salvando…',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: QdType.micro,
                  ),
                ),
              ),
            ),
          TextButton(
            key: const Key('customize-reset'),
            onPressed: _hasCustomization ? _reset : null,
            child: const Text('Restaurar padrão'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: snapshots.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.enabledProviderCount == 0
                            ? 'Nenhum provedor habilitado.'
                            : 'Aguardando dados dos provedores…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.text, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.enabledProviderCount == 0
                            ? 'Ative um provedor nas configurações ou rode o '
                                  'assistente para começar.'
                            : 'A personalização aparece assim que a primeira '
                                  'leitura terminar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: QdType.small,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => state.enabledProviderCount == 0
                            ? unawaited(showSettingsSheet(context))
                            : unawaited(state.refresh()),
                        child: Text(
                          state.enabledProviderCount == 0
                              ? 'Abrir configurações'
                              : 'Atualizar agora',
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Arraste para ordenar. Janelas "sob demanda" ficam atrás '
                      'de um botão; "ocultas" continuam sendo consultadas.',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: QdType.small,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: snapshots.length,
                      onReorderItem: _move,
                      buildDefaultDragHandles: false,
                      itemBuilder: (context, index) {
                        final snapshot = snapshots[index];
                        return _ProviderSection(
                          key: ValueKey(snapshot.provider.wireName),
                          index: index,
                          snapshot: snapshot,
                          config: _config,
                          onVisibility: (window, visibility) => _apply(
                            _config.withWindowVisibility(
                              snapshot.provider,
                              window.id,
                              visibility,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProviderSection extends StatefulWidget {
  const _ProviderSection({
    super.key,
    required this.index,
    required this.snapshot,
    required this.config,
    required this.onVisibility,
  });

  final int index;
  final ProviderSnapshot snapshot;
  final AppConfig config;
  final void Function(QuotaWindow window, WindowVisibility visibility)
  onVisibility;

  @override
  State<_ProviderSection> createState() => _ProviderSectionState();
}

class _ProviderSectionState extends State<_ProviderSection> {
  bool _expanded = false;

  Map<String?, List<QuotaWindow>> _groupedWindows(List<QuotaWindow> windows) {
    final groups = <String?, List<QuotaWindow>>{};
    for (final window in sortWindowsForDisplay(windows)) {
      groups.putIfAbsent(window.group, () => []).add(window);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final snapshot = widget.snapshot;
    final windows = snapshot.windows;
    final hidden = windows
        .where(
          (window) =>
              widget.config.visibilityFor(snapshot.provider, window.id) ==
              WindowVisibility.hidden,
        )
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(QdRadius.card),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: widget.index,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 2, 12),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: palette.dim,
                  ),
                ),
              ),
              ProviderAvatar(provider: snapshot.provider, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.provider.displayName,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      hidden == 0
                          ? '${windows.length} janela(s)'
                          : '${windows.length} janela(s) · $hidden oculta(s)',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: QdType.micro,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _expanded ? 'Recolher janelas' : 'Editar janelas',
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.tune,
                  size: 17,
                ),
              ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: [
                  if (windows.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Sem janelas de quota para este provedor.',
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: QdType.small,
                        ),
                      ),
                    )
                  else
                    for (final entry in _groupedWindows(windows).entries) ...[
                      if (entry.key != null && entry.key!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 2),
                          child: Align(
                            alignment: Alignment.centerLeft,
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
                        ),
                      for (final window in entry.value)
                        _WindowVisibilityRow(
                          window: window,
                          visibility: widget.config.visibilityFor(
                            snapshot.provider,
                            window.id,
                          ),
                          onChanged: (visibility) =>
                              widget.onVisibility(window, visibility),
                        ),
                    ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WindowVisibilityRow extends StatelessWidget {
  const _WindowVisibilityRow({
    required this.window,
    required this.visibility,
    required this.onChanged,
  });

  final QuotaWindow window;
  final WindowVisibility visibility;
  final ValueChanged<WindowVisibility> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              window.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted, fontSize: QdType.small),
            ),
          ),
          PopupMenuButton<WindowVisibility>(
            key: Key('window-visibility-${window.id}'),
            tooltip: 'Visibilidade da janela',
            initialValue: visibility,
            onSelected: onChanged,
            itemBuilder: (_) => [
              for (final option in WindowVisibility.values)
                PopupMenuItem(
                  value: option,
                  child: Row(
                    children: [
                      Icon(
                        option == visibility
                            ? Icons.check
                            : Icons.circle_outlined,
                        size: 14,
                        color: option == visibility
                            ? palette.green
                            : palette.dim,
                      ),
                      const SizedBox(width: 8),
                      Text(option.label),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: palette.panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    visibility.label,
                    style: TextStyle(
                      color: visibility == WindowVisibility.hidden
                          ? palette.dim
                          : palette.text,
                      fontSize: QdType.meta,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 14, color: palette.dim),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
