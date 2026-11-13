import 'dart:convert';
import 'dart:io';

import 'package:local_notifier/local_notifier.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

/// Mensagem pronta para o sistema operacional.
class NotificationMessage {
  const NotificationMessage({required this.title, required this.body});

  final String title;
  final String body;
}

/// Contrato mínimo para permitir um fake nos testes.
abstract class Notifier {
  Future<void> show(NotificationMessage message);
}

/// Notificações nativas via local_notifier (Windows/macOS/Linux).
class LocalNotificationService implements Notifier {
  bool _ready = false;

  /// Chamado quando o usuário clica numa notificação.
  void Function()? onTap;

  Future<void> initialize() async {
    try {
      await localNotifier.setup(
        appName: 'QuotaDeck',
        // Windows: cria o atalho com AUMID para o toast funcionar.
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _ready = true;
    } catch (_) {
      // Sem notificações o app continua funcionando.
      _ready = false;
    }
  }

  /// No local_notifier a permissão do macOS é pedida pelo próprio sistema
  /// na primeira notificação; mantido para o contrato do AppState.
  Future<void> requestPermission() async {}

  @override
  Future<void> show(NotificationMessage message) async {
    if (!_ready) return;
    try {
      final notification = LocalNotification(
        title: message.title,
        body: message.body,
      );
      notification.onClick = () => onTap?.call();
      await notification.show();
    } catch (_) {
      // Entrega best-effort: nunca derruba o painel.
    }
  }
}

/// Decide quando notificar, com histerese e dedupe por janela.
///
/// Uma travessia = uma notificação. O aviso re-arma quando o uso cai 5 pontos
/// abaixo do limiar ou quando o reset muda mais de 90 minutos (janela nova).
class NotificationPolicy {
  NotificationPolicy({Map<String, dynamic>? state}) {
    if (state != null) _restore(state);
  }

  final Map<String, _SeenWindow> _state = {};

  static String _key(ProviderSnapshot snapshot, QuotaWindow window) =>
      '${snapshot.provider.wireName}|${window.id}';

  List<NotificationMessage> evaluate({
    required SnapshotEnvelope envelope,
    required AppConfig config,
  }) {
    if (!config.notificationsEnabled) return const [];
    final crossed = <_Crossing>[];

    for (final snapshot in envelope.results) {
      if (!config.isEnabled(snapshot.provider)) continue;
      if (snapshot.stale || snapshot.errors.isNotEmpty) continue;
      for (final window in snapshot.windows) {
        final visibility = config.visibilityFor(snapshot.provider, window.id);
        if (visibility == WindowVisibility.hidden) continue;

        final key = _key(snapshot, window);
        var seen = _state[key] ?? _SeenWindow();
        final reset = window.resetsAt;
        if (reset != null &&
            seen.resetAt != null &&
            reset.difference(seen.resetAt!).abs() >
                const Duration(minutes: 90)) {
          seen = _SeenWindow();
        }

        final used = window.usedPercent;
        if (used < config.warningThreshold - 5) seen.warned = false;
        if (used < config.criticalThreshold - 5) {
          seen.criticalNotified = false;
        }
        if (reset != null) seen.resetAt = reset;

        if (!seen.criticalNotified && used >= config.criticalThreshold) {
          seen.criticalNotified = true;
          seen.warned = true;
          crossed.add(_Crossing(snapshot, window, used, critical: true));
        } else if (!seen.warned && used >= config.warningThreshold) {
          seen.warned = true;
          crossed.add(_Crossing(snapshot, window, used, critical: false));
        }
        _state[key] = seen;
      }
    }
    return _buildMessages(crossed, config);
  }

  /// Um toast por avaliação: várias janelas cruzando juntas viram uma
  /// mensagem só, em vez de uma rajada de notificações.
  List<NotificationMessage> _buildMessages(
    List<_Crossing> crossed,
    AppConfig config,
  ) {
    if (crossed.isEmpty) return const [];
    if (crossed.length == 1) {
      final item = crossed.first;
      return [
        _message(
          item.snapshot,
          item.window,
          critical: item.critical,
          used: item.used,
          config: config,
        ),
      ];
    }
    final criticalCount = crossed.where((item) => item.critical).length;
    final title = criticalCount > 0
        ? '$criticalCount ${criticalCount == 1 ? 'janela' : 'janelas'} no limite'
        : '${crossed.length} janelas acima de ${config.warningThreshold}%';
    final body = [
      for (final item in crossed.take(4))
        '${item.snapshot.provider.displayName} ${item.window.label}: '
            '${formatPercent(item.used)}%',
      if (crossed.length > 4) '+${crossed.length - 4} outras janelas',
    ].join('\n');
    return [NotificationMessage(title: title, body: body)];
  }

  NotificationMessage _message(
    ProviderSnapshot snapshot,
    QuotaWindow window, {
    required bool critical,
    required double used,
    required AppConfig config,
  }) {
    final provider = snapshot.provider.displayName;
    final percent = formatPercent(used);
    final reset = window.resetsAt;
    final resetText = reset == null ? '' : ' · reset ${relativeTime(reset)}';
    if (critical) {
      return NotificationMessage(
        title: '$provider no limite ($percent%)',
        body: '${window.label} atingiu ${config.criticalThreshold}%$resetText',
      );
    }
    return NotificationMessage(
      title: '$provider em $percent%',
      body: '${window.label} passou de ${config.warningThreshold}%$resetText',
    );
  }

  Map<String, dynamic> toJson() => {
    for (final entry in _state.entries)
      entry.key: {
        'warned': entry.value.warned,
        'critical': entry.value.criticalNotified,
        'resetAt': entry.value.resetAt?.toUtc().toIso8601String(),
      },
  };

  void _restore(Map<String, dynamic> raw) {
    for (final entry in raw.entries) {
      final item = entry.value;
      if (item is! Map) continue;
      _state[entry.key] = _SeenWindow(
        warned: item['warned'] == true,
        criticalNotified: item['critical'] == true,
        resetAt: DateTime.tryParse(item['resetAt']?.toString() ?? ''),
      );
    }
  }
}

class _SeenWindow {
  _SeenWindow({
    this.warned = false,
    this.criticalNotified = false,
    this.resetAt,
  });

  bool warned;
  bool criticalNotified;
  DateTime? resetAt;
}

class _Crossing {
  const _Crossing(
    this.snapshot,
    this.window,
    this.used, {
    required this.critical,
  });

  final ProviderSnapshot snapshot;
  final QuotaWindow window;
  final double used;
  final bool critical;
}

/// Lê/grava o estado de dedupe sem nunca derrubar o app.
class NotificationStateStore {
  const NotificationStateStore(this.file);

  final File? file;

  Future<NotificationPolicy> load() async {
    final f = file;
    if (f == null || !await f.exists()) return NotificationPolicy();
    try {
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map<String, dynamic>) {
        return NotificationPolicy(state: decoded);
      }
    } catch (_) {}
    return NotificationPolicy();
  }

  Future<void> save(NotificationPolicy policy) async {
    final f = file;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(policy.toJson()), flush: true);
      if (await f.exists()) {
        await f.delete();
      }
      await tmp.rename(f.path);
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['600', f.path]);
        } catch (_) {}
      }
    } catch (_) {}
  }
}
