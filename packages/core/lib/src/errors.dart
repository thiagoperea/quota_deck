import 'package:quota_deck_models/quota_deck_models.dart';

enum QdeckErrorCode {
  authMissing,
  authExpired,
  permissionDenied,
  providerNotRunning,
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
