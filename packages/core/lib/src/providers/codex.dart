import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quota_deck_models/quota_deck_models.dart';

import '../errors.dart';
import '../paths.dart';
import '../provider.dart';

class CodexProvider implements ProviderAdapter {
  const CodexProvider();

  @override
  ProviderId get id => ProviderId.codex;

  String get _executable => Platform.isWindows ? 'codex.cmd' : 'codex';

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async {
    final auth = AppPaths.codexAuth(env: ctx.env);
    final hasAuth = await auth.exists();
    final binary = await ctx.discovery.firstBinary(const [
      'codex',
      'codex.cmd',
    ]);
    final running = await ctx.discovery.isRunning(const ['codex']);
    final desktopDir = _desktopDir(ctx);
    final desktopInstalled = desktopDir != null || running;
    return DetectionResult.fromSurfaces(
      provider: id,
      surfaces: [
        SurfaceState(
          surface: ProviderSurface.desktop,
          installed: desktopInstalled,
          authenticated: hasAuth,
          live: true,
          location: desktopDir == null
              ? (running ? 'processo codex' : null)
              : AppPaths.maskPath(desktopDir, env: ctx.env),
          reason: hasAuth
              ? 'Sessão em auth.json compartilhada com o app desktop.'
              : 'Codex Desktop detectado, sem auth.json.',
          action: hasAuth ? null : 'Abra o Codex e faça login.',
        ),
        SurfaceState(
          surface: ProviderSurface.cli,
          installed: binary != null || hasAuth,
          authenticated: hasAuth,
          live: true,
          location: binary,
          reason: hasAuth
              ? 'CLI usa o mesmo auth.json.'
              : 'CLI detectada; auth.json ausente (pode estar no keyring).',
          action: hasAuth ? null : 'Rode codex no terminal e faça login.',
        ),
      ],
    );
  }

  String? _desktopDir(ProviderContext ctx) {
    final local = ctx.env['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return null;
    final dir = Directory(p.join(local, 'OpenAI', 'Codex'));
    return dir.existsSync() ? dir.path : null;
  }

  Future<ProviderSurface> _surfaceOf(ProviderContext ctx) async {
    if (_desktopDir(ctx) != null ||
        await ctx.discovery.isRunning(const ['codex'])) {
      return ProviderSurface.desktop;
    }
    return ProviderSurface.cli;
  }

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    if (await _binaryAvailable(ctx)) {
      try {
        return await _readAppServer(ctx);
      } on QdeckException catch (e) {
        ctx.log(
          'Codex app-server indisponível (${e.code.wireName}); usando fallback.',
        );
      } catch (e) {
        ctx.log('Codex app-server falhou (${e.runtimeType}); usando fallback.');
      }
    }
    return _readWham(ctx);
  }

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async {
    final checks = <DoctorCheck>[];
    final authFile = AppPaths.codexAuth(env: ctx.env);
    final exists = await authFile.exists();
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'auth',
        label: 'auth.json',
        status: exists ? DoctorStatus.ok : DoctorStatus.warn,
        message: exists
            ? 'Encontrado em ${AppPaths.maskPath(authFile.path, env: ctx.env)}'
            : 'Não encontrado (pode estar no keyring).',
      ),
    );
    final auth = await _readAuth(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'auth-mode',
        label: 'Modo de autenticação',
        status: auth == null
            ? DoctorStatus.warn
            : auth.mode == 'chatgpt'
            ? DoctorStatus.ok
            : DoctorStatus.warn,
        message: auth == null
            ? 'Sem auth.json legível.'
            : 'auth_mode=${auth.mode}; tokens=${auth.token != null ? 'presentes' : 'ausentes'}; last_refresh=${auth.lastRefresh ?? 'n/a'}',
      ),
    );
    final binary = await _binaryAvailable(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'binary',
        label: 'Binário codex',
        status: binary ? DoctorStatus.ok : DoctorStatus.warn,
        message: binary
            ? 'Disponível; app-server será tentado primeiro.'
            : 'Não encontrado; usando wham/usage.',
      ),
    );
    return checks;
  }

  Future<bool> _binaryAvailable(ProviderContext ctx) async {
    try {
      final result = await ctx.process.run(_executable, [
        '--version',
      ], timeout: const Duration(seconds: 3));
      return result.ok;
    } catch (_) {
      return false;
    }
  }

  Future<_CodexAuth?> _readAuth(ProviderContext ctx) async {
    final file = AppPaths.codexAuth(env: ctx.env);
    if (!await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final tokens = raw['tokens'];
      final token = tokens is Map ? tokens['access_token']?.toString() : null;
      final accountId = tokens is Map ? tokens['account_id']?.toString() : null;
      final email = tokens is Map
          ? tokens['email']?.toString()
          : raw['email']?.toString();
      return _CodexAuth(
        mode: (raw['auth_mode'] ?? 'unknown').toString(),
        token: token,
        accountId: accountId,
        email: email,
        lastRefresh: raw['last_refresh']?.toString(),
      );
    } catch (e) {
      ctx.log('Codex: auth.json ilegível (${e.runtimeType}).');
      return null;
    }
  }

  Future<ProviderSnapshot> _readWham(ProviderContext ctx) async {
    final auth = await _readAuth(ctx);
    if (auth == null || auth.token == null || auth.token!.isEmpty) {
      final installed =
          await _binaryAvailable(ctx) ||
          _desktopDir(ctx) != null ||
          await ctx.discovery.isRunning(const ['codex']);
      throw QdeckException(
        code: installed
            ? QdeckErrorCode.authMissing
            : QdeckErrorCode.notInstalled,
        provider: id,
        message: installed
            ? 'Codex sem auth.json/keyring com access_token. Abra o Codex para autenticar.'
            : 'Codex não encontrado nesta máquina.',
      );
    }
    if (auth.mode == 'apikey') {
      throw QdeckException(
        code: QdeckErrorCode.apiKeyMode,
        provider: id,
        message:
            'Codex em auth_mode=apikey; limites de assinatura não disponíveis.',
      );
    }

    final headers = <String, String>{
      'Authorization': 'Bearer ${auth.token}',
      'Accept': 'application/json',
      'User-Agent': 'codex-cli',
    };
    if (auth.accountId != null && auth.accountId!.isNotEmpty) {
      headers['chatgpt-account-id'] = auth.accountId!;
    }

    final response = await ctx.http
        .get(
          Uri.parse('https://chatgpt.com/backend-api/wham/usage'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 401) {
      throw QdeckException(
        code: QdeckErrorCode.authExpired,
        provider: id,
        message: 'Codex retornou 401. Abra o Codex para renovar o login.',
      );
    }
    if (response.statusCode == 429) {
      throw QdeckException(
        code: QdeckErrorCode.rateLimited,
        provider: id,
        message: 'Rate limit no endpoint de uso do Codex.',
      );
    }
    if (response.statusCode != 200) {
      throw QdeckException(
        code: QdeckErrorCode.network,
        provider: id,
        message: 'Codex respondeu HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Resposta do Codex não é um objeto JSON.',
      );
    }
    final rateLimit = decoded['rate_limit'];
    if (rateLimit is! Map) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Resposta do Codex sem rate_limit.',
      );
    }

    final windows = <QuotaWindow>[];
    for (final key in const ['primary_window', 'secondary_window']) {
      final item = rateLimit[key];
      if (item is! Map) continue;
      final usedRaw = asDoubleOrNull(item['used_percent']);
      if (usedRaw == null) continue;
      final used = clampPercent(usedRaw);
      final seconds = asIntOrNull(item['limit_window_seconds']) ?? 0;
      final duration = seconds > 0 ? durationLabel(seconds) : null;
      final windowId = switch (seconds) {
        18000 => 'primary-5h',
        604800 => 'secondary-7d',
        _ => duration == null ? key : '$key-$duration',
      };
      windows.add(
        QuotaWindow(
          id: windowId,
          label: switch (seconds) {
            18000 => '5 horas',
            604800 => 'Semanal (7d)',
            _ => duration == null ? key : 'Janela de $duration',
          },
          kind: kindForWindow(windowId, durationSeconds: seconds),
          usedPercent: used,
          remainingPercent: clampPercent(100 - used),
          resetsAt: parseDate(item['reset_at']),
          status: statusForUsed(
            used,
            explicit:
                rateLimit['limit_reached'] == true ||
                    rateLimit['allowed'] == false
                ? 'limited'
                : null,
          ),
          source: SourceKind.api,
        ),
      );
    }
    if (windows.isEmpty) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Codex respondeu sem janelas de rate limit.',
      );
    }

    final credits = decoded['credits'];
    final resetCredits = decoded['rate_limit_reset_credits'];
    CreditsInfo? creditsInfo;
    if (credits is Map) {
      final resetCount = resetCredits is Map
          ? _intOrNull(resetCredits['available_count'])
          : null;
      creditsInfo = CreditsInfo(
        hasCredits: credits['has_credits'] == true,
        unlimited: credits['unlimited'] == true,
        balance: _doubleOrNull(credits['balance']),
        note: resetCount == null ? null : '$resetCount créditos de reset',
      );
    }

    final rawEmail = decoded['email']?.toString();
    final email = rawEmail != null && rawEmail.contains('@')
        ? rawEmail
        : auth.email;
    return ProviderSnapshot(
      provider: id,
      account: AccountInfo(
        label: 'Codex',
        plan: decoded['plan_type']?.toString(),
        maskedEmail: maskEmail(email),
      ),
      windows: windows,
      credits: creditsInfo,
      source: 'codex-wham-usage',
      sourceId: 'codex-wham-usage',
      surface: await _surfaceOf(ctx),
      fetchedAt: ctx.now(),
      confidence: Confidence.medium,
    );
  }

  Future<ProviderSnapshot> _readAppServer(ProviderContext ctx) async {
    final session = await ctx.process.start(_executable, ['app-server']);
    try {
      final completer = Completer<Map<String, dynamic>>();
      late StreamSubscription<String> sub;
      sub = session.stdoutLines.listen((line) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic> && decoded['id'] == 1) {
            if (!completer.isCompleted) completer.complete(decoded);
          }
        } catch (_) {}
      });

      session.writeLine(
        jsonEncode({
          'method': 'initialize',
          'id': 0,
          'params': {
            'clientInfo': {
              'name': 'quotadeck',
              'title': 'QuotaDeck',
              'version': '0.1.0',
            },
          },
        }),
      );
      session.writeLine(jsonEncode({'method': 'initialized', 'params': {}}));
      session.writeLine(
        jsonEncode({'method': 'account/rateLimits/read', 'id': 1}),
      );

      Map<String, dynamic> response;
      try {
        response = await completer.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        throw QdeckException(
          code: QdeckErrorCode.network,
          provider: id,
          message: 'Codex app-server não respondeu em 5s.',
        );
      } finally {
        await sub.cancel();
      }

      final result = response['result'];
      if (result is! Map) {
        throw QdeckException(
          code: QdeckErrorCode.schemaChanged,
          provider: id,
          message: 'Codex app-server respondeu sem result.',
        );
      }
      Map? rateLimits;
      if (result['rateLimits'] is Map) {
        rateLimits = result['rateLimits'] as Map;
      } else if (result['rateLimitsByLimitId'] is Map) {
        final byId = result['rateLimitsByLimitId'] as Map;
        if (byId['codex'] is Map) rateLimits = byId['codex'] as Map;
      }
      if (rateLimits == null) {
        throw QdeckException(
          code: QdeckErrorCode.schemaChanged,
          provider: id,
          message: 'Codex app-server respondeu sem rateLimits.',
        );
      }

      final windows = <QuotaWindow>[];
      for (final key in const ['primary', 'secondary']) {
        final item = rateLimits[key];
        if (item is! Map) continue;
        final usedRaw = asDoubleOrNull(item['usedPercent']);
        if (usedRaw == null) continue;
        final used = clampPercent(usedRaw);
        final mins = asIntOrNull(item['windowDurationMins']) ?? 0;
        final seconds = mins * 60;
        final windowId = switch (mins) {
          300 => 'primary-5h',
          10080 => 'secondary-7d',
          _ => '$key-${durationLabel(seconds)}',
        };
        windows.add(
          QuotaWindow(
            id: windowId,
            label: switch (mins) {
              300 => '5 horas',
              10080 => 'Semanal (7d)',
              _ => 'Janela de ${durationLabel(seconds)}',
            },
            kind: kindForWindow(windowId, durationSeconds: seconds),
            usedPercent: used,
            remainingPercent: clampPercent(100 - used),
            resetsAt: parseDate(item['resetsAt']),
            status: statusForUsed(
              used,
              explicit: rateLimits['rateLimitReachedType'] == null
                  ? null
                  : 'limited',
            ),
            source: SourceKind.appServer,
          ),
        );
      }
      if (windows.isEmpty) {
        throw QdeckException(
          code: QdeckErrorCode.schemaChanged,
          provider: id,
          message: 'Codex app-server sem janelas.',
        );
      }

      final resetCredits = result['rateLimitResetCredits'];
      final resetCount = resetCredits is Map
          ? _intOrNull(resetCredits['availableCount'])
          : null;

      return ProviderSnapshot(
        provider: id,
        account: AccountInfo(
          label: 'Codex',
          plan: result['planType']?.toString(),
        ),
        windows: windows,
        credits: resetCount == null
            ? null
            : CreditsInfo(
                hasCredits: false,
                unlimited: false,
                note: '$resetCount créditos de reset',
              ),
        source: 'codex-app-server',
        sourceId: 'codex-app-server',
        surface: await _surfaceOf(ctx),
        fetchedAt: ctx.now(),
        confidence: Confidence.high,
      );
    } finally {
      await session.close();
    }
  }
}

double? _doubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _intOrNull(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

class _CodexAuth {
  final String mode;
  final String? token;
  final String? accountId;
  final String? email;
  final String? lastRefresh;

  const _CodexAuth({
    required this.mode,
    required this.token,
    required this.accountId,
    required this.email,
    required this.lastRefresh,
  });
}
