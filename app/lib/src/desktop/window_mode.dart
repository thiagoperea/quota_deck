// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:nativeapi_flutter/nativeapi_flutter.dart'
    show PointToOffset, RectangleToRect, NativeSizeToSize;
import 'package:window_manager/legacy.dart';

import '../state/app_state.dart';

/// Tamanhos da janela única do app.
const miniWindowSize = Size(380, 500);
const dashboardWindowSize = Size(1100, 800);
const compactWindowSize = Size(420, 760);

const _compactMinSize = Size(320, 400);
const _dashboardMinSize = Size(900, 600);

/// Canto da janela mini na área útil do monitor do cursor.
const _miniAlignment = Alignment(0.985, 0.985);

/// Popover pequeno aberto pelo clique no ícone da bandeja.
Future<void> openMiniWindow(AppState state) async {
  state.setMiniMode(true);
  state.setWindowActive(true);
  await _lockToMiniSize();
  await windowManager.setSize(miniWindowSize);
  await _placeMini();
  await windowManager.show();
  await windowManager.focus();
}

/// Mini é um popover: tamanho fixo, sem alças de redimensionamento.
Future<void> _lockToMiniSize() async {
  await windowManager.setMaximumSize(const Size(10000, 10000));
  await windowManager.setMinimumSize(miniWindowSize);
  await windowManager.setMaximumSize(miniWindowSize);
  await windowManager.setResizable(false);
}

/// Devolve o redimensionamento livre para dashboard e modo compacto.
Future<void> _unlockSize(Size minimum) async {
  await windowManager.setMaximumSize(const Size(10000, 10000));
  await windowManager.setMinimumSize(minimum);
  await windowManager.setResizable(true);
}

/// Janela completa, com todos os cards, histórico e resets.
Future<void> openDashboardWindow(AppState state) async {
  state.setMiniMode(false);
  state.setWindowActive(true);
  await _unlockSize(_dashboardMinSize);
  await _fitWindow(dashboardWindowSize);
  await _raise();
}

/// Traz a janela para frente, inclusive sobre janelas em tela cheia.
Future<void> _raise() async {
  try {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAlwaysOnTop(false);
  } catch (_) {
    await windowManager.show();
    await windowManager.focus();
  }
}

/// Layout compacto de 420px (usado em telas pequenas e no primeiro start).
Future<void> openCompactWindow(AppState state) async {
  state.setMiniMode(false);
  state.setWindowActive(true);
  await _unlockSize(_compactMinSize);
  await _fitWindow(compactWindowSize);
  await _raise();
}

Future<void> hideToTray(AppState state) async {
  state.setWindowActive(false);
  await windowManager.hide();
}

/// Posiciona o mini no canto da bandeja.
///
/// `calcWindowPosition` devolve coordenadas inválidas quando o plugin de
/// displays ainda não respondeu (área útil 0x0), o que jogava a janela para
/// fora da tela. Aqui validamos o resultado e caímos no centro como último
/// recurso.
Future<void> _placeMini() async {
  final position = await _miniPosition(miniWindowSize);
  if (position != null) {
    await windowManager.setPosition(position);
    return;
  }
  await windowManager.center();
  await ensureWindowOnScreen();
}

Future<Offset?> _miniPosition(Size windowSize) async {
  try {
    final manager = nativeapi.DisplayManager.instance;
    final displays = manager.getAll();
    final cursor = manager.getCursorPosition().toOffset();
    nativeapi.Display? target;
    for (final display in displays) {
      final bounds = display.position.toOffset() & display.size.toSize();
      if (bounds.contains(cursor)) {
        target = display;
        break;
      }
    }
    target ??= manager.getPrimary();
    if (target == null) return null;

    var work = target.workArea.toRect();
    if (work.width <= 0 || work.height <= 0) {
      work = target.position.toOffset() & target.size.toSize();
    }
    if (work.width <= 0 || work.height <= 0) return null;

    double place(double start, double extent, double size, double alignment) {
      final raw = start + (extent - size) * (alignment + 1) / 2;
      final maxStart = start + (extent - size);
      final minEdge = start < maxStart ? start : maxStart;
      final maxEdge = start < maxStart ? maxStart : start;
      return raw.clamp(minEdge, maxEdge);
    }

    return Offset(
      place(work.left, work.width, windowSize.width, _miniAlignment.x),
      place(work.top, work.height, windowSize.height, _miniAlignment.y),
    );
  } catch (_) {
    return null;
  }
}

/// Se a janela ficou fora de todos os monitores, traz para o centro.
Future<void> ensureWindowOnScreen() async {
  try {
    final bounds = await windowManager.getBounds();
    final displays = nativeapi.DisplayManager.instance.getAll();
    for (final display in displays) {
      final work = _workArea(display);
      if (work.width <= 0 || work.height <= 0) continue;
      if (!work.overlaps(bounds)) continue;
      // Além de caber na tela, a janela precisa caber na área útil: em
      // 1366×768 o dashboard de 1100×800 nascia com o rodapé fora da tela.
      final size = Size(
        bounds.width.clamp(320.0, work.width),
        bounds.height.clamp(320.0, work.height),
      );
      final maxLeft = work.left + (work.width - size.width);
      final maxTop = work.top + (work.height - size.height);
      final left = bounds.left.clamp(work.left, maxLeft);
      final top = bounds.top.clamp(work.top, maxTop);
      if (size.width != bounds.width || size.height != bounds.height) {
        await windowManager.setSize(size);
      }
      if (left != bounds.left || top != bounds.top) {
        await windowManager.setPosition(Offset(left, top));
      }
      return;
    }
    await windowManager.center();
  } catch (_) {
    // Sem displays ou sem plugin: mantém onde está.
  }
}

Rect _workArea(nativeapi.Display display) {
  var work = display.workArea.toRect();
  if (work.width <= 0 || work.height <= 0) {
    work = display.position.toOffset() & display.size.toSize();
  }
  return work;
}

/// Abre a janela com o tamanho desejado, preso à área útil do monitor
/// principal e centralizado nela.
Future<void> _fitWindow(Size desired) async {
  try {
    final manager = nativeapi.DisplayManager.instance;
    final display = manager.getPrimary();
    if (display == null) return;
    final work = _workArea(display);
    if (work.width <= 0 || work.height <= 0) return;
    final size = Size(
      desired.width.clamp(320.0, work.width),
      desired.height.clamp(320.0, work.height),
    );
    await windowManager.setSize(size);
    await windowManager.setPosition(
      Offset(
        work.left + (work.width - size.width) / 2,
        work.top + (work.height - size.height) / 2,
      ),
    );
  } catch (_) {
    await windowManager.setSize(desired);
    await windowManager.center();
  }
}
