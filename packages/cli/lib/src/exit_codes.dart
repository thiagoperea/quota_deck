import 'package:quota_deck_models/quota_deck_models.dart';

/// Códigos de saída documentados da CLI.
class QdeckExitCode {
  static const int ok = 0;
  static const int auth = 2;
  static const int network = 3;
  static const int rateLimited = 4;
  static const int partial = 5;
  static const int usage = 64;
}

/// Mapeia os erros de um envelope para o código de saída da CLI.
int exitCodeForEnvelope(SnapshotEnvelope envelope) {
  final errors = <QdeckErrorInfo>[
    ...envelope.errors,
    for (final result in envelope.results) ...result.errors,
  ];
  if (errors.isEmpty) return QdeckExitCode.ok;

  final hasSuccess = envelope.results.any(
    (result) => result.errors.isEmpty && result.windows.isNotEmpty,
  );
  if (hasSuccess) return QdeckExitCode.partial;

  final codes = errors.map((error) => error.code.toUpperCase()).toSet();

  if (codes.length == 1) {
    return _exitForCode(codes.first);
  }
  if (codes.every(_isAuthCode)) return QdeckExitCode.auth;
  if (codes.every((code) => code == 'NETWORK')) {
    return QdeckExitCode.network;
  }
  if (codes.every((code) => code == 'RATE_LIMITED')) {
    return QdeckExitCode.rateLimited;
  }
  return QdeckExitCode.partial;
}

/// Mapeia um código de erro (`AUTH_MISSING`, `NETWORK`, ...) para exit code.
int exitCodeForErrorCode(String code) => _exitForCode(code.toUpperCase());

int _exitForCode(String code) {
  if (_isAuthCode(code)) return QdeckExitCode.auth;
  if (code == 'NETWORK') return QdeckExitCode.network;
  if (code == 'RATE_LIMITED') return QdeckExitCode.rateLimited;
  return QdeckExitCode.partial;
}

bool _isAuthCode(String code) =>
    code == 'AUTH_MISSING' ||
    code == 'AUTH_EXPIRED' ||
    code == 'PERMISSION_DENIED';
