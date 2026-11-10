import 'models.dart';

QuotaStatus statusForUsed(
  double used, {
  String? explicit,
  int warningThreshold = 80,
  int criticalThreshold = 95,
}) {
  final e = (explicit ?? '').toLowerCase().trim();
  if (e == 'rate-limited' ||
      e == 'rate_limited' ||
      e == 'limited' ||
      e == 'exhausted') {
    return QuotaStatus.limited;
  }
  if (e == 'warning' || e == 'near-limit' || e == 'critical') {
    return e == 'critical' ? QuotaStatus.critical : QuotaStatus.warning;
  }
  final u = clampPercent(used);
  if (u >= 100) return QuotaStatus.limited;
  if (u >= criticalThreshold) return QuotaStatus.critical;
  if (u >= warningThreshold) return QuotaStatus.warning;
  return QuotaStatus.ok;
}

String labelForWindow(String id, [String? fallback]) {
  const labels = {
    'rolling': '5 horas',
    'rolling-5h': '5 horas',
    '5h': '5 horas',
    'weekly': 'Semanal (7d)',
    '7d': 'Semanal (7d)',
    'monthly': 'Mensal (30d)',
    '30d': 'Mensal (30d)',
    'five_hour': '5 horas',
    'seven_day': 'Semanal (7d)',
    'seven_day_sonnet': 'Semanal Sonnet',
    'seven_day_opus': 'Semanal Opus',
    'primary': 'Janela primária',
    'secondary': 'Janela secundária',
    'primary-5h': '5 horas',
    'secondary-7d': 'Semanal (7d)',
  };
  return labels[id] ?? (fallback?.isNotEmpty == true ? fallback! : id);
}

WindowKind kindForWindow(String id, {int? durationSeconds}) {
  if (durationSeconds != null) {
    if (durationSeconds == 18000) return WindowKind.session;
    if (durationSeconds == 604800) return WindowKind.weekly;
  }
  switch (id) {
    case 'rolling':
    case 'rolling-5h':
    case '5h':
    case 'five_hour':
    case 'primary-5h':
      return WindowKind.rolling;
    case 'weekly':
    case '7d':
    case 'seven_day':
    case 'secondary-7d':
      return WindowKind.weekly;
    case 'monthly':
    case '30d':
      return WindowKind.monthly;
    case 'seven_day_sonnet':
    case 'seven_day_opus':
      return WindowKind.model;
    default:
      return WindowKind.unknown;
  }
}

int _displayRank(WindowKind kind) => switch (kind) {
  WindowKind.rolling => 0,
  WindowKind.session => 1,
  WindowKind.weekly => 2,
  WindowKind.monthly => 3,
  WindowKind.model => 4,
  WindowKind.credits => 5,
  WindowKind.unknown => 6,
};

/// Ordena janelas para leitura: curtas (5h) antes das longas (7d/30d),
/// mantendo a ordem original entre janelas do mesmo tipo.
List<QuotaWindow> sortWindowsForDisplay(Iterable<QuotaWindow> windows) {
  final entries = windows.toList().asMap().entries.toList();
  entries.sort((a, b) {
    final rank = _displayRank(a.value.kind)
        .compareTo(_displayRank(b.value.kind));
    return rank != 0 ? rank : a.key.compareTo(b.key);
  });
  return [for (final entry in entries) entry.value];
}

String durationLabel(int seconds) {
  if (seconds == 604800) return '7d';
  if (seconds % 86400 == 0) return '${seconds ~/ 86400}d';
  if (seconds % 3600 == 0) return '${seconds ~/ 3600}h';
  if (seconds % 60 == 0) return '${seconds ~/ 60}min';
  return '${seconds}s';
}

String relativeTime(DateTime? value, {DateTime? now}) {
  if (value == null) return '-';
  final n = (now ?? DateTime.now()).toUtc();
  final v = value.toUtc();
  final diff = v.difference(n);
  final past = diff.isNegative;
  final d = diff.abs();
  if (d.inSeconds < 45) return 'agora';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  final String amount;
  if (days > 0) {
    amount = hours > 0 ? '$days d $hours h' : '$days d';
  } else if (d.inHours > 0) {
    amount = minutes > 0 ? '${d.inHours} h $minutes min' : '${d.inHours} h';
  } else {
    amount = '${d.inMinutes} min';
  }
  return past ? 'há $amount' : 'em $amount';
}

String formatPercent(double value) {
  final v = clampPercent(value);
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(1);
}

String shortEmail(String? email) {
  if (email == null || email.isEmpty) return '';
  final at = email.indexOf('@');
  if (at <= 0) return email;
  final user = email.substring(0, at);
  final domain = email.substring(at + 1);
  final dot = domain.lastIndexOf('.');
  final tld = dot >= 0 ? domain.substring(dot) : '';
  return '${user.length > 2 ? user.substring(0, 2) : user}***@${domain.isEmpty ? '' : domain[0]}***$tld';
}
