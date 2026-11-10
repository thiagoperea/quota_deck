import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'paths.dart';
import 'provider.dart';
import 'safe_storage.dart';

/// Credencial OAuth que o app Claude Desktop (aba Code/Claude Code) mantém.
///
/// O token fica em `config.json` do Electron, cifrado pelo `safeStorage`
/// nativo (DPAPI no Windows, Keychain no macOS). É a mesma sessão usada pela
/// GUI; não é o arquivo `.credentials.json` da CLI.
class ClaudeDesktopToken {
  const ClaudeDesktopToken({
    required this.accessToken,
    required this.expiresAt,
    required this.subscriptionType,
    required this.scopes,
    required this.accountId,
  });

  final String accessToken;
  final DateTime? expiresAt;
  final String? subscriptionType;
  final Set<String> scopes;
  final String? accountId;

  bool get isExpired {
    final expires = expiresAt;
    return expires != null && expires.isBefore(DateTime.now().toUtc());
  }
}

/// Lê e decifra o token da sessão do Claude Desktop, se existir.
///
/// Retorna `null` em plataformas sem suporte a `safeStorage` ou quando o app
/// nunca fez login. Nunca lança: falha de leitura é tratada como ausência.
Future<ClaudeDesktopToken?> readClaudeDesktopToken(ProviderContext ctx) async {
  try {
    final config = await _newestConfig(ctx);
    if (config == null) return null;
    final decoded = jsonDecode(await config.readAsString());
    if (decoded is! Map) return null;

    final encoded =
        (decoded['oauth:tokenCacheV2'] ?? decoded['oauth:tokenCache'])
            ?.toString();
    if (encoded == null || encoded.isEmpty) return null;

    final clear = await decryptElectronSafeStorage(
      encoded,
      localStatePath: p.join(config.parent.path, 'Local State'),
    );
    if (clear == null) return null;

    final cache = jsonDecode(utf8.decode(clear));
    if (cache is! Map) return null;

    final now = ctx.now();
    final accountId = decoded['lastKnownAccountUuid']?.toString();
    final candidates = <_TokenCandidate>[];
    for (final entry in cache.entries) {
      final raw = entry.value;
      if (raw is! Map) continue;
      final token = (raw['token'] ?? raw['accessToken'])?.toString() ?? '';
      if (token.isEmpty) continue;
      final expiresAt = _parseExpiry(raw['expiresAt']);
      if (expiresAt != null && expiresAt.isBefore(now)) continue;

      final key = entry.key.toString();
      final scopes = _scopesFromKey(key);
      if (!scopes.contains('user:inference')) continue;

      candidates.add(
        _TokenCandidate(
          secret: ClaudeDesktopToken(
            accessToken: token,
            expiresAt: expiresAt,
            subscriptionType: raw['subscriptionType']?.toString(),
            scopes: scopes,
            accountId: _accountFromKey(key) ?? accountId,
          ),
          hasClaudeCode: scopes.any((scope) => scope.endsWith('claude_code')),
        ),
      );
    }
    if (candidates.isEmpty) return null;

    // Prefere a sessão da aba Code; depois a que expira mais tarde.
    candidates.sort((a, b) {
      if (a.hasClaudeCode != b.hasClaudeCode) {
        return a.hasClaudeCode ? -1 : 1;
      }
      final aExp = a.secret.expiresAt;
      final bExp = b.secret.expiresAt;
      if (aExp == null && bExp == null) return 0;
      if (aExp == null) return 1;
      if (bExp == null) return -1;
      return bExp.compareTo(aExp);
    });
    return candidates.first.secret;
  } catch (error) {
    ctx.log(
      'Claude Desktop: token da GUI indisponível (${error.runtimeType}).',
    );
    return null;
  }
}

class _TokenCandidate {
  const _TokenCandidate({required this.secret, required this.hasClaudeCode});

  final ClaudeDesktopToken secret;
  final bool hasClaudeCode;
}

Future<File?> _newestConfig(ProviderContext ctx) async {
  File? newest;
  DateTime? newestAt;
  for (final dir in AppPaths.claudeDesktopDirs(env: ctx.env)) {
    final file = File(p.join(dir.path, 'config.json'));
    if (!await file.exists()) continue;
    final stat = await file.stat();
    if (newestAt == null || stat.modified.isAfter(newestAt)) {
      newest = file;
      newestAt = stat.modified;
    }
  }
  return newest;
}

Set<String> _scopesFromKey(String key) {
  // acct:<uuid>|<client>:<org>:https://api.anthropic.com:<escopos>
  final host = RegExp(r'https?://[^:]+:').firstMatch(key);
  final index = host?.end ?? key.lastIndexOf(':') + 1;
  if (index <= 0 || index >= key.length) return const {};
  return key
      .substring(index)
      .split(' ')
      .where((scope) => scope.trim().isNotEmpty)
      .toSet();
}

String? _accountFromKey(String key) {
  // acct:<uuid>|<client-id>:<org>:...:scopes
  const prefix = 'acct:';
  if (!key.startsWith(prefix)) return null;
  final pipe = key.indexOf('|');
  if (pipe <= prefix.length) return null;
  return key.substring(prefix.length, pipe);
}

DateTime? _parseExpiry(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) {
    var ms = raw.toDouble();
    if (ms < 10000000000) ms *= 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  }
  final numeric = int.tryParse(raw.toString());
  if (numeric != null) {
    var ms = numeric.toDouble();
    if (ms < 10000000000) ms *= 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
  }
  return DateTime.tryParse(raw.toString())?.toUtc();
}
