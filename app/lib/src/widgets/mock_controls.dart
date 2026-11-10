import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/mock_api.dart';
import '../desktop/window_mode.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Botão de desenvolvimento para trocar o cenário do mock e o tamanho da janela.
///
/// Não renderiza nada fora do modo `QDECK_MOCK=1`.
class MockControlsButton extends StatelessWidget {
  const MockControlsButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.mockApi == null) return const SizedBox.shrink();
    final palette = QdPalette.of(context);
    final size = compact ? 36.0 : 38.0;
    return Tooltip(
      message: 'Cenários de mock',
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          key: const Key('mock-controls'),
          onPressed: () => unawaited(showMockControls(context, state)),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: palette.panel2,
            side: BorderSide(color: palette.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          icon: Icon(
            Icons.science_outlined,
            size: compact ? 16 : 18,
            color: palette.yellow,
          ),
        ),
      ),
    );
  }
}

Future<void> showMockControls(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _MockSheet(state: state),
  );
}

class _MockSheet extends StatefulWidget {
  const _MockSheet({required this.state});

  final AppState state;

  @override
  State<_MockSheet> createState() => _MockSheetState();
}

class _MockSheetState extends State<_MockSheet> {
  late MockScenario _selected =
      widget.state.mockApi?.scenario ?? MockScenario.normal;
  bool _busy = false;

  Future<void> _apply(MockScenario scenario) async {
    if (_busy) return;
    setState(() {
      _selected = scenario;
      _busy = true;
    });
    await widget.state.applyMockScenario(scenario);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  void _openWindow(Future<void> Function(AppState state) open) {
    Navigator.of(context).pop();
    unawaited(open(widget.state));
  }

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: const Key('mock-sheet'),
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: palette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
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
              padding: const EdgeInsets.fromLTRB(18, 12, 10, 4),
              child: Row(
                children: [
                  Icon(Icons.science_outlined, size: 18, color: palette.yellow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cenários de mock',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Só aparece com --dart-define=QDECK_MOCK=1',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: QdType.micro,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                children: [
                  for (final scenario in MockScenario.values)
                    _ScenarioTile(
                      scenario: scenario,
                      selected: scenario == _selected,
                      busy: _busy && scenario == _selected,
                      onTap: () => unawaited(_apply(scenario)),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'TAMANHO DA JANELA',
                    style: TextStyle(
                      color: palette.dim,
                      fontSize: QdType.micro,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SizeButton(
                          key: const Key('mock-size-mini'),
                          icon: Icons.picture_in_picture_alt_outlined,
                          label: 'Mini',
                          onPressed: () =>
                              _openWindow((state) => openMiniWindow(state)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SizeButton(
                          key: const Key('mock-size-compact'),
                          icon: Icons.view_agenda_outlined,
                          label: 'Compacto',
                          onPressed: () =>
                              _openWindow((state) => openCompactWindow(state)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SizeButton(
                          key: const Key('mock-size-dashboard'),
                          icon: Icons.open_in_full,
                          label: 'Dashboard',
                          onPressed: () => _openWindow(
                            (state) => openDashboardWindow(state),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({
    required this.scenario,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final MockScenario scenario;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? palette.yellow.withValues(alpha: 0.08)
            : palette.panel2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected
                ? palette.yellow.withValues(alpha: 0.45)
                : palette.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('mock-scenario-${scenario.name}'),
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scenario.label,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        scenario.description,
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: QdType.micro,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (busy)
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.yellow,
                    ),
                  )
                else
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 17,
                    color: selected ? palette.yellow : palette.dim,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeButton extends StatelessWidget {
  const _SizeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.text,
        side: BorderSide(color: palette.border),
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(
          fontSize: QdType.meta,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }
}
