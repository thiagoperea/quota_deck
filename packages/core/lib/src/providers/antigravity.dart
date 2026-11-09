import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:quota_deck_models/quota_deck_models.dart';

import '../errors.dart';
import '../paths.dart';
import '../provider.dart';

class AntigravityProvider implements ProviderAdapter {
  const AntigravityProvider();

  @override
  ProviderId get id => ProviderId.antigravity;

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async {
    final hub = _findHub(ctx);
    final installedDir = Directory(
      p.join(
        ctx.env['LOCALAPPDATA'] ?? ctx.env['HOME'] ?? '',
        'Programs',
        'antigravity',
      ),
    ).existsSync();
    final running = await ctx.discovery.isRunning(const [
      'antigravity',
      'language_server',
    ]);
    SurfaceState surface({
      required bool authenticated,
      String? reason,
      String? location,
    }) => SurfaceState(
      surface: ProviderSurface.desktop,
      installed: hub != null || installedDir || running,
      authenticated: authenticated,
      live: true,
      location: location,
      reason: reason,
      action: authenticated
          ? null
          : 'Abra o Antigravity, faça login e mantenha o app aberto.',
    );

    if (hub == null) {
      return DetectionResult.fromSurfaces(
        provider: id,
        surfaces: [
          surface(
            authenticated: false,
            reason: installedDir || running
                ? 'Antigravity instalado, sem daemon/hub ativo.'
                : 'Antigravity não encontrado.',
          ),
        ],
      );
    }
    final meta = _readHub(hub);
    if (meta == null) {
      return DetectionResult.fromSurfaces(
        provider: id,
        surfaces: [
          surface(
            authenticated: false,
            location: AppPaths.maskPath(hub.path, env: ctx.env),
            reason: 'hub do Antigravity ilegível.',
          ),
        ],
      );
    }
    final alive = await _pidAlive(ctx, meta.pid);
    return DetectionResult.fromSurfaces(
      provider: id,
      surfaces: [
        surface(
          authenticated: alive,
          location: AppPaths.maskPath(hub.path, env: ctx.env),
          reason: alive
              ? 'language_server/hub ativo.'
              : 'Antigravity não está em execução (pid ${meta.pid}).',
        ),
      ],
    );
  }

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    final hub = _findHub(ctx);
    if (hub == null) {
      throw QdeckException(
        code: QdeckErrorCode.providerNotRunning,
        provider: id,
        message: 'Daemon do Antigravity não encontrado. Abra o Antigravity.',
      );
    }
    final meta = _readHub(hub);
    if (meta == null) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'hub do Antigravity ilegível.',
      );
    }
    if (!await _pidAlive(ctx, meta.pid)) {
      throw QdeckException(
        code: QdeckErrorCode.providerNotRunning,
        provider: id,
        message: 'Antigravity não está em execução. Abra o Antigravity.',
      );
    }
    if (meta.csrfToken.isEmpty || (meta.httpPort == 0 && meta.httpsPort == 0)) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'hub do Antigravity sem porta/CSRF.',
      );
    }

    final response = await _postQuota(ctx, meta);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Resposta do Antigravity não é um objeto JSON.',
      );
    }

    final payload = decoded['response'] is Map<String, dynamic>
        ? decoded['response'] as Map<String, dynamic>
        : decoded;
    final groups = payload['groups'];
    if (groups is! List) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Resposta do Antigravity sem groups.',
      );
    }

    final windows = <QuotaWindow>[];
    for (final group in groups) {
      if (group is! Map) continue;
      final groupName = group['displayName']?.toString();
      final buckets = group['buckets'];
      if (buckets is! List) continue;
      for (final bucket in buckets) {
        if (bucket is! Map || bucket['disabled'] == true) continue;
        final remaining = _remainingFraction(bucket);
        if (remaining == null) continue;
        final used = clampPercent((1.0 - remaining) * 100.0);
        final window =
            bucket['window']?.toString() ??
            bucket['bucketId']?.toString() ??
            'unknown';
        final kind = switch (window) {
          '5h' => WindowKind.session,
          'weekly' => WindowKind.weekly,
          _ => WindowKind.unknown,
        };
        windows.add(
          QuotaWindow(
            id: bucket['bucketId']?.toString() ?? window,
            label: labelForWindow(window, bucket['displayName']?.toString()),
            kind: kind,
            group: groupName,
            usedPercent: used,
            remainingPercent: clampPercent(remaining * 100.0),
            resetsAt: parseDate(bucket['resetTime']),
            status: statusForUsed(used),
            source: SourceKind.rpc,
          ),
        );
      }
    }

    if (windows.isEmpty) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Antigravity respondeu sem buckets de quota.',
      );
    }

    return ProviderSnapshot(
      provider: id,
      account: const AccountInfo(label: 'Antigravity'),
      windows: windows,
      source: 'antigravity-language-server',
      sourceId: 'antigravity-language-server',
      surface: ProviderSurface.desktop,
      fetchedAt: ctx.now(),
      confidence: Confidence.high,
    );
  }

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async {
    final checks = <DoctorCheck>[];
    final hub = _findHub(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'hub',
        label: 'Daemon do Antigravity',
        status: hub == null ? DoctorStatus.fail : DoctorStatus.ok,
        message: hub == null
            ? 'hub_*.json não encontrado.'
            : 'Encontrado em ${AppPaths.maskPath(hub.path, env: ctx.env)}',
      ),
    );
    if (hub == null) return checks;

    final meta = _readHub(hub);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'pid',
        label: 'Processo',
        status: meta == null
            ? DoctorStatus.fail
            : await _pidAlive(ctx, meta.pid)
            ? DoctorStatus.ok
            : DoctorStatus.fail,
        message: meta == null
            ? 'hub ilegível.'
            : 'pid ${meta.pid}; http ${meta.httpPort}; https ${meta.httpsPort}',
      ),
    );
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'csrf',
        label: 'CSRF local',
        status: meta != null && meta.csrfToken.isNotEmpty
            ? DoctorStatus.ok
            : DoctorStatus.fail,
        message: meta != null && meta.csrfToken.isNotEmpty
            ? 'presente (não exposto).'
            : 'ausente.',
      ),
    );
    return checks;
  }

  File? _findHub(ProviderContext ctx) {
    final dir = AppPaths.antigravityDaemonDir(env: ctx.env);
    if (!dir.existsSync()) return null;
    final files = dir
        .listSync()
        .whereType<File>()
        .where(
          (f) => f.path.split(Platform.pathSeparator).last.startsWith('hub_'),
        )
        .toList(growable: false);
    if (files.isEmpty) return null;
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files.first;
  }

  _AntigravityHub? _readHub(File file) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      return _AntigravityHub(
        pid: asIntOrNull(decoded['pid']) ?? 0,
        httpPort: asIntOrNull(decoded['httpPort']) ?? 0,
        httpsPort: asIntOrNull(decoded['httpsPort']) ?? 0,
        csrfToken: decoded['csrfToken']?.toString() ?? '',
        version: decoded['lsVersion']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _pidAlive(ProviderContext ctx, int pid) async {
    if (pid <= 0) return false;
    try {
      if (Platform.isWindows) {
        final result = await ctx.process.run('tasklist', [
          '/FI',
          'PID eq $pid',
          '/NH',
        ], timeout: const Duration(seconds: 5));
        return result.ok && result.stdout.contains('$pid');
      }
      final result = await ctx.process.run('kill', [
        '-0',
        '$pid',
      ], timeout: const Duration(seconds: 3));
      return result.ok;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _postQuota(
    ProviderContext ctx,
    _AntigravityHub meta,
  ) async {
    final body = jsonEncode(const <String, dynamic>{});
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Connect-Protocol-Version': '1',
      'x-codeium-csrf-token': meta.csrfToken,
    };
    final path =
        '/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary';

    if (meta.httpPort > 0) {
      try {
        final response = await ctx.http
            .post(
              Uri.parse('http://127.0.0.1:${meta.httpPort}$path'),
              headers: headers,
              body: body,
            )
            .timeout(const Duration(seconds: 15));
        _checkStatus(response, meta);
        return response;
      } catch (e) {
        if (e is QdeckException) rethrow;
        ctx.log(
          'Antigravity: HTTP local falhou (${e.runtimeType}); tentando HTTPS.',
        );
      }
    }

    if (meta.httpsPort > 0) {
      final io = HttpClient()
        ..badCertificateCallback = (cert, host, port) =>
            host == '127.0.0.1' || host == 'localhost';
      final client = IOClient(io);
      try {
        final response = await client
            .post(
              Uri.parse('https://127.0.0.1:${meta.httpsPort}$path'),
              headers: headers,
              body: body,
            )
            .timeout(const Duration(seconds: 15));
        _checkStatus(response, meta);
        return response;
      } finally {
        client.close();
      }
    }

    throw QdeckException(
      code: QdeckErrorCode.providerNotRunning,
      provider: id,
      message: 'Antigravity sem porta HTTP/HTTPS disponível.',
    );
  }

  void _checkStatus(http.Response response, _AntigravityHub meta) {
    if (response.statusCode == 200) return;
    if (response.statusCode == 401) {
      throw QdeckException(
        code: QdeckErrorCode.authExpired,
        provider: id,
        message: 'Antigravity rejeitou o CSRF local. Abra o app novamente.',
      );
    }
    if (response.statusCode == 404) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message:
            'RPC do Antigravity não encontrado (versão ${meta.version ?? '?'}).',
      );
    }
    if (response.statusCode == 429) {
      throw QdeckException(
        code: QdeckErrorCode.rateLimited,
        provider: id,
        message: 'Rate limit no RPC local do Antigravity.',
      );
    }
    throw QdeckException(
      code: QdeckErrorCode.network,
      provider: id,
      message: 'Antigravity respondeu HTTP ${response.statusCode}.',
    );
  }

  double? _remainingFraction(Map bucket) {
    dynamic value = bucket['remainingFraction'];
    if (value == null) {
      final remaining = bucket['remaining'];
      if (remaining is Map) {
        value = remaining['remainingFraction'];
        if (value == null && remaining['case'] == 'remainingFraction') {
          value = remaining['value'];
        }
      }
    }
    if (value is num) return value.toDouble().clamp(0.0, 1.0).toDouble();
    return double.tryParse(value?.toString() ?? '')?.clamp(0.0, 1.0).toDouble();
  }
}

class _AntigravityHub {
  final int pid;
  final int httpPort;
  final int httpsPort;
  final String csrfToken;
  final String? version;

  const _AntigravityHub({
    required this.pid,
    required this.httpPort,
    required this.httpsPort,
    required this.csrfToken,
    this.version,
  });
}
