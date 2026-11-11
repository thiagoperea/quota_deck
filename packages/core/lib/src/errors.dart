import 'package:quota_deck_models/quota_deck_models.dart';

enum QdeckErrorCode {
  authMissing,
  authExpired,
  permissionDenied,
  providerNotRunning,
  notInstalled,
  credentialUnreadable,
  noSubscription,
  apiKeyMode,
  network,
  rateLimited,
  schemaChanged,
  clockSkew,
  unknown;

  String get wireName => switch (this) {
    QdeckErrorCode.authMissing => 'AUTH_MISSING',
    QdeckErrorCode.authExpired => 'AUTH_EXPIRED',
    QdeckErrorCode.permissionDenied => 'PERMISSION_DENIED',
    QdeckErrorCode.providerNotRunning => 'PROVIDER_NOT_RUNNING',
    QdeckErrorCode.notInstalled => 'NOT_INSTALLED',
    QdeckErrorCode.credentialUnreadable => 'CREDENTIAL_UNREADABLE',
    QdeckErrorCode.noSubscription => 'NO_SUBSCRIPTION',
    QdeckErrorCode.apiKeyMode => 'API_KEY_MODE',
    QdeckErrorCode.network => 'NETWORK',
    QdeckErrorCode.rateLimited => 'RATE_LIMITED',
    QdeckErrorCode.schemaChanged => 'SCHEMA_CHANGED',
    QdeckErrorCode.clockSkew => 'CLOCK_SKEW',
    QdeckErrorCode.unknown => 'UNKNOWN',
  };

  bool get retryable =>
      this == QdeckErrorCode.network ||
      this == QdeckErrorCode.rateLimited ||
      this == QdeckErrorCode.providerNotRunning ||
      this == QdeckErrorCode.clockSkew;
}

class QdeckException implements Exception {
  final QdeckErrorCode code;
  final ProviderId provider;
  final String message;
  final Map<String, dynamic>? details;

  const QdeckException({
    required this.code,
    required this.provider,
    required this.message,
    this.details,
  });

  QdeckErrorInfo toInfo() => QdeckErrorInfo(
    code: code.wireName,
    message: message,
    retryable: code.retryable,
    details: details,
  );

  @override
  String toString() => '${code.wireName}: $message';
}

/// `Retry-After` em segundos, aceitando também uma data HTTP (RFC 7231).
int? retryAfterSecondsFromHeaders(Map<String, String> headers) {
  String? raw;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'retry-after') {
      raw = entry.value;
      break;
    }
  }
  if (raw == null) return null;
  final trimmed = raw.trim();
  final seconds = int.tryParse(trimmed);
  if (seconds != null) return seconds < 0 ? 0 : seconds;
  final date = DateTime.tryParse(trimmed);
  if (date == null) return null;
  final diff = date.toUtc().difference(DateTime.now().toUtc()).inSeconds;
  return diff < 0 ? 0 : diff;
}

/// Detalhes padronizados para erros 429 consumidos pelo backoff do core.
Map<String, dynamic>? rateLimitDetails(Map<String, String> headers) {
  final seconds = retryAfterSecondsFromHeaders(headers);
  if (seconds == null) return null;
  return {
    'retryAfterSeconds': seconds,
    'retryAt': DateTime.now()
        .toUtc()
        .add(Duration(seconds: seconds))
        .toIso8601String(),
  };
}
