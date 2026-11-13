import 'dart:convert';
import 'dart:io';

/// Dados da última release publicada no GitHub.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.url, this.notes});

  /// Versão sem o prefixo `v` (ex.: `0.7.0`).
  final String version;

  /// Página da release no GitHub.
  final String url;

  /// Notas da release (limitadas a 2000 caracteres).
  final String? notes;
}

/// Consulta a última release do QuotaDeck no GitHub.
///
/// Nunca lança: falhas de rede, timeout, status diferente de 200 ou JSON
/// inválido resultam em `null`.
class UpdateService {
  /// Só abrimos/aceitamos links de release do repositório oficial.
  static const _allowedHosts = {'github.com', 'www.github.com'};
  static const _releasePathPrefix = '/thiagoperea/quota_deck/';

  UpdateService({HttpClient? client, Uri? endpoint})
    // Parâmetro público, campo privado.
    // ignore: prefer_initializing_formals
    : _client = client,
      _endpoint = endpoint ?? defaultEndpoint;

  /// Endpoint público das releases (GET).
  static final Uri defaultEndpoint = Uri.parse(
    'https://api.github.com/repos/thiagoperea/quota_deck/releases/latest',
  );

  /// Limite das notas guardadas em [UpdateInfo.notes].
  static const int _notesLimit = 2000;

  final HttpClient? _client;
  final Uri _endpoint;

  /// Retorna a release mais recente se for mais nova que [currentVersion].
  Future<UpdateInfo?> check({
    required String currentVersion,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = _client ?? HttpClient();
    try {
      client.connectionTimeout = timeout;
      final request = await client.getUrl(_endpoint).timeout(timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'QuotaDeck/$currentVersion');

      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _parse(body, currentVersion);
    } catch (_) {
      return null;
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  UpdateInfo? _parse(String body, String currentVersion) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;

    final tag = decoded['tag_name'];
    final url = decoded['html_url'];
    if (tag is! String || url is! String || url.trim().isEmpty) return null;

    final safeUrl = validReleaseUrl(url);
    if (safeUrl == null) return null;

    final latest = _normalizeVersion(tag);
    if (latest.isEmpty || !isNewer(latest, currentVersion)) return null;

    final rawNotes = decoded['body'];
    final notes = rawNotes is String && rawNotes.trim().isNotEmpty
        ? _truncate(rawNotes.trim())
        : null;
    return UpdateInfo(version: latest, url: safeUrl, notes: notes);
  }

  /// Aceita apenas `https://github.com/thiagoperea/quota_deck/...`.
  ///
  /// A resposta do GitHub (e qualquer proxy no caminho) não deve conseguir
  /// abrir URL arbitrária no SO — no Windows isso ia para o `cmd /c start`.
  static String? validReleaseUrl(String? raw) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'https') return null;
    if (!_allowedHosts.contains(uri.host.toLowerCase())) return null;
    if (!uri.path.startsWith(_releasePathPrefix)) return null;
    if (uri.userInfo.isNotEmpty) return null;
    return uri.toString();
  }

  static String _truncate(String value) =>
      value.length <= _notesLimit ? value : value.substring(0, _notesLimit);

  /// Remove espaços e o prefixo `v`/`V` de uma tag (ex.: `v0.7.0` → `0.7.0`).
  static String _normalizeVersion(String tag) {
    final trimmed = tag.trim();
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return trimmed.substring(1).trim();
    }
    return trimmed;
  }

  /// `true` quando [candidate] é mais nova que [current].
  bool isNewer(String candidate, String current) =>
      compareVersions(candidate, current) > 0;

  /// Compara versões por segmentos numéricos: `1.10.0 > 1.9.9`.
  ///
  /// Ignora prefixo `v`, sufixos (`-beta`, `-rc.1`) e build metadata (`+8`).
  /// Entradas vazias ou inválidas não lançam; são tratadas como `0`.
  int compareVersions(String a, String b) {
    final left = _numbers(a);
    final right = _numbers(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  static List<int> _numbers(String version) {
    var core = _normalizeVersion(version);
    // Descarta build metadata e pré-release antes de comparar.
    core = core.split('+').first.split('-').first;
    return core.split('.').map(_leadingNumber).toList(growable: false);
  }

  static int _leadingNumber(String segment) {
    final match = RegExp(r'\d+').firstMatch(segment);
    if (match == null) return 0;
    return int.tryParse(match.group(0)!) ?? 0;
  }

  /// Abre [url] no navegador padrão do sistema.
  ///
  /// Retorna `true` se o processo foi iniciado.
  Future<bool> openExternal(String url) async {
    final target = validReleaseUrl(url);
    if (target == null) return false;
    try {
      if (Platform.isWindows) {
        // `rundll32` abre no navegador padrão sem passar por um shell, então
        // metacaracteres da URL não viram comando.
        await Process.start('rundll32', [
          'url.dll,FileProtocolHandler',
          target,
        ]);
        return true;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [target]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [target]);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
