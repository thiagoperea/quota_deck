import 'dart:io';
import 'dart:math' as math;

import 'package:quota_deck_models/quota_deck_models.dart';

const _reset = '\x1b[0m';
const _bold = '\x1b[1m';
const _dim = '\x1b[2m';
const _green = '\x1b[32m';
const _yellow = '\x1b[33m';
const _red = '\x1b[31m';
const _barWidth = 20;
final _ansiPattern = RegExp(r'\x1B\[[0-9;]*m');

/// Renderiza o envelope de snapshot como tabela humana.
String formatSnapshot(
  SnapshotEnvelope envelope, {
  bool color = false,
  DateTime? now,
}) {
  final buffer = StringBuffer();
  final rows = <List<String>>[];

  for (final result in envelope.results) {
    final account = _accountLabel(result.account);
    if (result.windows.isEmpty) {
      final status = result.hasError ? 'erro' : 'sem dados';
      rows.add([
        result.provider.displayName,
        account,
        '-',
        '-',
        '-',
        result.stale ? '${result.source} (stale)' : result.source,
        _style(status, result.hasError ? _red : _dim, color),
      ]);
      continue;
    }

    for (final window in result.windows) {
      final windowLabel = window.group == null
          ? window.label
          : '${window.label} · ${window.group}';
      rows.add([
        result.provider.displayName,
        account,
        windowLabel,
        _usedCell(window.usedPercent, window.status, color),
        relativeTime(window.resetsAt, now: now),
        result.stale
            ? '${window.source.wireName} (stale)'
            : window.source.wireName,
        _style(window.status.wireName, _statusColor(window.status), color),
      ]);
    }
  }

  if (rows.isEmpty) {
    buffer.writeln('Nenhum provedor habilitado ou detectado.');
  } else {
    const header = [
      'Provedor',
      'Conta',
      'Janela',
      'Uso',
      'Reset',
      'Fonte',
      'Status',
    ];
    final widths = List<int>.filled(header.length, 0);
    for (var index = 0; index < header.length; index++) {
      widths[index] = header[index].length;
    }
    for (final row in rows) {
      for (var index = 0; index < row.length; index++) {
        widths[index] = math.max(widths[index], _visibleLength(row[index]));
      }
    }

    String line(List<String> cells) {
      final padded = <String>[];
      for (var index = 0; index < cells.length; index++) {
        padded.add(_pad(cells[index], widths[index]));
      }
      return padded.join('  ');
    }

    buffer.writeln(
      line([for (final title in header) _style(title, _bold, color)]),
    );
    buffer.writeln(line([for (final width in widths) '-' * width]));
    for (final row in rows) {
      buffer.writeln(line(row));
    }
  }

  _writeErrors(buffer, envelope, color);
  return buffer.toString().trimRight();
}

/// Linha compacta para statusline/scripts.
String formatStatusline(SnapshotEnvelope envelope) {
  final parts = <String>[];
  for (final result in envelope.results) {
    final code = switch (result.provider) {
      ProviderId.opencode => 'OC',
      ProviderId.antigravity => 'AG',
      ProviderId.codex => 'CX',
      ProviderId.claude => 'CL',
    };
    final window = result.worstWindow;
    if (window == null) {
      parts.add('$code ${result.hasError ? '!' : '-'}');
    } else {
      parts.add('$code ${formatPercent(window.usedPercent)}%');
    }
  }
  return parts.join(' · ');
}

/// Renderiza os checks do doctor como tabela humana.
String formatDoctor(List<DoctorCheck> checks, {bool color = false}) {
  if (checks.isEmpty) return 'Nenhum check de diagnóstico disponível.';

  const header = ['Provedor', 'Check', 'Status', 'Mensagem'];
  final rows = [
    for (final check in checks)
      [
        check.provider.displayName,
        check.label,
        _style(check.status.wireName, _doctorColor(check.status), color),
        _maskHome(redact(check.message)),
      ],
  ];

  final widths = List<int>.filled(header.length, 0);
  for (var index = 0; index < header.length; index++) {
    widths[index] = header[index].length;
  }
  for (final row in rows) {
    for (var index = 0; index < row.length; index++) {
      widths[index] = math.max(widths[index], _visibleLength(row[index]));
    }
  }

  String line(List<String> cells) {
    final padded = <String>[];
    for (var index = 0; index < cells.length; index++) {
      padded.add(_pad(cells[index], widths[index]));
    }
    return padded.join('  ');
  }

  final buffer = StringBuffer();
  buffer.writeln(
    line([for (final title in header) _style(title, _bold, color)]),
  );
  buffer.writeln(line([for (final width in widths) '-' * width]));
  for (final row in rows) {
    buffer.writeln(line(row));
  }
  return buffer.toString().trimRight();
}

/// Renderiza um resumo de histórico.
String formatHistory(HistorySummary summary, {bool color = false}) {
  final buffer = StringBuffer();
  buffer.writeln(
    _style(
      'Histórico: ${summary.provider.displayName} / ${summary.windowId}',
      _bold,
      color,
    ),
  );

  final burn = summary.burnRatePerHour.toStringAsFixed(1);
  final eta = summary.etaHours == null
      ? 'sem consumo'
      : '${summary.etaHours!.toStringAsFixed(1)} h';
  buffer.writeln('Burn rate: $burn%/h   ETA: $eta');

  if (summary.samples.isEmpty) {
    buffer.writeln('Sem amostras no período.');
    return buffer.toString().trimRight();
  }

  buffer.writeln();
  buffer.writeln('${_pad('Horário', 20)}  ${_pad('Uso', 8)}  Stale');
  for (final sample in summary.samples) {
    buffer.writeln(
      '${_pad(_formatTimestamp(sample.fetchedAt), 20)}  '
      '${_pad('${formatPercent(sample.usedPercent)}%', 8)}  '
      '${sample.stale ? 'sim' : 'não'}',
    );
  }
  return buffer.toString().trimRight();
}

/// Renderiza a configuração como texto humano.
String formatSettings(AppConfig config) {
  final providers = config.providers.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final providerList = providers
      .map((entry) => '${entry.key}=${entry.value ? 'on' : 'off'}')
      .join(', ');

  final buffer = StringBuffer()
    ..writeln('Provedores: $providerList')
    ..writeln('Atualização: ${config.refreshSeconds}s')
    ..writeln('Cache: ${config.cacheTtlSeconds}s')
    ..writeln(
      'Histórico: ${config.historyEnabled ? 'on' : 'off'} '
      '(retenção ${config.retentionDays} dias)',
    )
    ..writeln(
      'Notificações: ${config.notificationsEnabled ? 'on' : 'off'} '
      '(aviso ${config.warningThreshold}%, crítico ${config.criticalThreshold}%)',
    )
    ..writeln('Reset próximo: ${config.resetSoonMinutes} min')
    ..writeln('Tema: ${config.theme}')
    ..writeln('Iniciar no login: ${config.launchAtLogin ? 'on' : 'off'}')
    ..writeln('Probe: ${config.allowProbe ? 'on' : 'off'}')
    ..writeln('OAuth refresh: ${config.allowOAuthRefresh ? 'on' : 'off'}');
  return buffer.toString().trimRight();
}

String _accountLabel(AccountInfo account) {
  final plan = account.plan?.trim();
  if (plan == null || plan.isEmpty) return account.label;
  return '${account.label} ($plan)';
}

String _usedCell(double used, QuotaStatus status, bool color) {
  final value = clampPercent(used);
  final filled = ((value / 100 * _barWidth).round())
      .clamp(0, _barWidth)
      .toInt();
  final bar = '${'█' * filled}${'░' * (_barWidth - filled)}';
  final plain = '[$bar] ${formatPercent(value)}%';
  return _style(plain, _statusColor(status), color);
}

String _statusColor(QuotaStatus status) => switch (status) {
  QuotaStatus.ok => _green,
  QuotaStatus.warning => _yellow,
  QuotaStatus.critical || QuotaStatus.limited => _red,
  QuotaStatus.unknown => _dim,
};

String _doctorColor(DoctorStatus status) => switch (status) {
  DoctorStatus.ok => _green,
  DoctorStatus.warn => _yellow,
  DoctorStatus.fail => _red,
};

String _style(String value, String code, bool color) =>
    color ? '$code$value$_reset' : value;

int _visibleLength(String value) => value.replaceAll(_ansiPattern, '').length;

String _pad(String value, int width) =>
    value + ' ' * math.max(0, width - _visibleLength(value));

String _maskHome(String value) {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null || home.isEmpty) return value;
  return value.replaceAll(home, '~');
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

void _writeErrors(StringBuffer buffer, SnapshotEnvelope envelope, bool color) {
  final resultMessages = <String>[
    for (final result in envelope.results)
      for (final error in result.errors)
        '${result.provider.displayName} ${error.code}: '
            '${_maskHome(redact(error.message))}',
  ];
  final messages = resultMessages.isNotEmpty
      ? resultMessages
      : [
          for (final error in envelope.errors)
            '${error.code}: ${_maskHome(redact(error.message))}',
        ];
  if (messages.isEmpty) return;

  buffer.writeln();
  buffer.writeln(_style('Avisos:', _bold, color));
  for (final message in messages) {
    buffer.writeln('  - $message');
  }
}
