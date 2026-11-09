import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quota_deck_models/quota_deck_models.dart';

import '../errors.dart';
import '../paths.dart';
import '../provider.dart';

class ClaudeProvider implements ProviderAdapter {
  const ClaudeProvider();

  @override
  ProviderId get id => ProviderId.claude;

  static const _srcCli = 'claude-oauth-usage';
  static const _srcDesktop = 'claude-desktop-history';

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async {
    final cli = await _probeCli(ctx);
    final desktop = await _probeDesktop(ctx);
    return DetectionResult.fromSurfaces(provider: id, surfaces: [cli, desktop]);
  }

  Future<SurfaceState> _probeCli(ProviderContext ctx) async {
    _ClaudeCredentials? creds;
    try {
      creds = await _readCredentials(ctx);
    } on QdeckException {
      creds = null;
    }
    final file = AppPaths.claudeCredentials(env: ctx.env);
    final fileExists = await file.exists();
    final binary = await _findCliBinary(ctx);
    final expired =
        creds?.expiresAt != null && creds!.expiresAt!.isBefore(ctx.now());
    final authenticated =
        creds != null && creds.accessToken.isNotEmpty && !expired;
    final installed = fileExists || binary != null || creds != null;
    return SurfaceState(
      surface: ProviderSurface.cli,
      installed: installed,
      authenticated: authenticated,
      live: true,
      location:
          binary ??
          (fileExists ? AppPaths.maskPath(file.path, env: ctx.env) : null),
      account: null,
      reason: authenticated
          ? 'Token OAuth do Claude Code presente.'
          : expired
          ? 'Token do Claude Code expirado.'
          : installed
          ? 'Claude Code instalado, sem login ativo.'
          : 'Claude Code não encontrado.',
      action: authenticated ? null : 'Rode claude no terminal (ou o claude.exe embutido no Claude Desktop) e faça login.',
    );
  }

  Future<SurfaceState> _probeDesktop(ProviderContext ctx) async {
    final dirs = AppPaths.claudeDesktopDirs(env: ctx.env);
    final historyFile = await _newestUsageFile(ctx);
    String? installedDir;
    for (final dir in dirs) {
      if (dir.existsSync()) {
        installedDir = dir.path;
        break;
      }
    }
    final running = await ctx.discovery.isRunning(const ['claude']);
    final usage = historyFile == null
        ? null
        : await _readDesktopUsage(historyFile);
    return SurfaceState(
      surface: ProviderSurface.desktop,
      installed: installedDir != null || running || usage != null,
      authenticated: usage != null,
      live: false,
      location: historyFile == null
          ? installedDir
          : AppPaths.maskPath(historyFile.path, env: ctx.env),
      account: null,
      reason: usage == null
          ? 'Claude Desktop detectado, sem histórico de uso legível.'
          : 'Histórico local do Claude Desktop (estimado, atualiza com o app aberto).',
      action: usage == null
          ? null
          : 'Para dados ao vivo com reset, faça login no Claude Code.',
    );
  }

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    try {
      return await _readCli(ctx);
    } on QdeckException catch (error) {
      if (error.code != QdeckErrorCode.authMissing &&
          error.code != QdeckErrorCode.authExpired) {
        rethrow;
      }
      final desktop = await _readDesktop(ctx);
      if (desktop != null) {
        return desktop.copyWith(errors: [error.toInfo()]);
      }
      if (error.code == QdeckErrorCode.authExpired) rethrow;
      final installed =
          await _findCliBinary(ctx) != null ||
          AppPaths.claudeDesktopDirs(env: ctx.env).any((d) => d.existsSync());
      throw QdeckException(
        code: installed ? error.code : QdeckErrorCode.notInstalled,
        provider: id,
        message: installed
            ? '${error.message} Nenhum histórico local do Claude Desktop foi encontrado.'
            : 'Claude não encontrado (nem Claude Code nem Claude Desktop).',
        details: {
          ...?error.details,
          'surfaces': ['cli', 'desktop'],
        },
      );
    }
  }

  Future<ProviderSnapshot> _readCli(ProviderContext ctx) async {
    final creds = await _readCredentials(ctx);
    if (creds == null || creds.accessToken.isEmpty) {
      throw QdeckException(
        code: QdeckErrorCode.authMissing,
        provider: id,
        message:
            'Claude sem credencial utilizável. Faça login no Claude Code '
            '(CLI) para leitura ao vivo.',
      );
    }
    final expiresAt = creds.expiresAt;
    if (expiresAt != null && expiresAt.isBefore(ctx.now())) {
      throw QdeckException(
        code: QdeckErrorCode.authExpired,
        provider: id,
        message:
            'Token do Claude Code expirado. Abra o Claude Code para renovar.',
        details: {'expiresAt': formatDate(expiresAt)},
      );
    }

    final response = await ctx.http
        .get(
          Uri.parse('https://api.anthropic.com/api/oauth/usage'),
          headers: {
            'Authorization': 'Bearer ${creds.accessToken}',
            'anthropic-beta': 'oauth-2025-04-20',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 401) {
      throw QdeckException(
        code: QdeckErrorCode.authExpired,
        provider: id,
        message: 'Claude Code retornou 401. Abra o Claude Code para renovar.',
      );
    }
    if (response.statusCode == 429) {
      throw QdeckException(
        code: QdeckErrorCode.rateLimited,
        provider: id,
        message: 'Rate limit no endpoint de uso do Claude Code.',
      );
    }
    if (response.statusCode != 200) {
      throw QdeckException(
        code: QdeckErrorCode.network,
        provider: id,
        message: 'Claude Code respondeu HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Resposta do Claude Code não é um objeto JSON.',
      );
    }

    final windows = <QuotaWindow>[];
    for (final key in const [
      'five_hour',
      'seven_day',
      'seven_day_sonnet',
      'seven_day_opus',
    ]) {
      final item = decoded[key];
      if (item is! Map) continue;
      final usedRaw = asDoubleOrNull(item['utilization']);
      if (usedRaw == null) continue;
      final used = clampPercent(usedRaw);
      final kind = switch (key) {
        'five_hour' => WindowKind.session,
        'seven_day' => WindowKind.weekly,
        _ => WindowKind.model,
      };
      windows.add(
        QuotaWindow(
          id: key,
          label: labelForWindow(key),
          kind: kind,
          usedPercent: used,
          remainingPercent: clampPercent(100 - used),
          resetsAt: parseDate(item['resets_at']),
          status: statusForUsed(used),
          source: SourceKind.api,
        ),
      );
    }
    if (windows.isEmpty) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Claude Code respondeu sem janelas conhecidas.',
      );
    }

    final extra = decoded['extra_usage'];
    CreditsInfo? credits;
    if (extra is Map) {
      final limit = asDoubleOrNull(extra['monthly_limit']);
      final used = asDoubleOrNull(extra['used_credits']);
      credits = CreditsInfo(
        hasCredits: extra['is_enabled'] == true,
        unlimited: false,
        balance: limit != null && used != null ? limit - used : null,
        note: extra['utilization'] == null
            ? null
            : 'utilization ${extra['utilization']}%',
      );
    }

    return ProviderSnapshot(
      provider: id,
      account: AccountInfo(label: 'Claude Code', plan: creds.subscriptionType),
      windows: windows,
      credits: credits,
      source: _srcCli,
      sourceId: _srcCli,
      surface: ProviderSurface.cli,
      fetchedAt: ctx.now(),
      confidence: Confidence.high,
    );
  }

  Future<ProviderSnapshot?> _readDesktop(ProviderContext ctx) async {
    final file = await _newestUsageFile(ctx);
    if (file == null) return null;
    final usage = await _readDesktopUsage(file);
    if (usage == null) return null;
    final age = ctx.now().difference(usage.seenAt);
    final windows = <QuotaWindow>[];
    if (usage.fiveHour != null) {
      final used = clampPercent(usage.fiveHour!);
      windows.add(
        QuotaWindow(
          id: 'desktop_five_hour',
          label: '5 horas',
          kind: WindowKind.session,
          usedPercent: used,
          remainingPercent: clampPercent(100 - used),
          status: statusForUsed(used),
          source: SourceKind.log,
        ),
      );
    }
    if (usage.sevenDay != null) {
      final used = clampPercent(usage.sevenDay!);
      windows.add(
        QuotaWindow(
          id: 'desktop_seven_day',
          label: 'Semanal (7d)',
          kind: WindowKind.weekly,
          usedPercent: used,
          remainingPercent: clampPercent(100 - used),
          status: statusForUsed(used),
          source: SourceKind.log,
        ),
      );
    }
    if (windows.isEmpty) return null;
    return ProviderSnapshot(
      provider: id,
      account: const AccountInfo(label: 'Claude Desktop'),
      windows: windows,
      source: _srcDesktop,
      sourceId: _srcDesktop,
      surface: ProviderSurface.desktop,
      fetchedAt: usage.seenAt,
      stale: age > const Duration(minutes: 45),
      confidence: Confidence.low,
    );
  }

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async {
    final checks = <DoctorCheck>[];
    final creds = await _safeCreds(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'cli-credentials',
        label: 'Claude Code (CLI)',
        status: creds == null ? DoctorStatus.fail : DoctorStatus.ok,
        message: creds == null
            ? 'Keychain/arquivo não encontrado.'
            : 'accessToken presente; plano=${creds.subscriptionType ?? 'n/a'}.',
      ),
    );
    if (creds != null) {
      final expires = creds.expiresAt;
      checks.add(
        DoctorCheck(
          provider: id,
          id: 'expiry',
          label: 'Expiração do token',
          status: expires == null
              ? DoctorStatus.warn
              : expires.isBefore(ctx.now())
              ? DoctorStatus.fail
              : DoctorStatus.ok,
          message: expires == null
              ? 'expiresAt ausente.'
              : 'expira em ${formatDate(expires)}',
        ),
      );
    }

    final history = await _newestUsageFile(ctx);
    final usage = history == null ? null : await _readDesktopUsage(history);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'desktop-history',
        label: 'Claude Desktop (histórico)',
        status: usage == null ? DoctorStatus.warn : DoctorStatus.ok,
        message: usage == null
            ? 'Sem plan-usage-history.json legível.'
            : 'Amostra de ${formatDate(usage.seenAt)}; '
                  'fh=${usage.fiveHour} sd=${usage.sevenDay}.',
      ),
    );

    final binary = await _findCliBinary(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'cli-binary',
        label: 'Binário do Claude Code',
        status: binary == null ? DoctorStatus.warn : DoctorStatus.ok,
        message: binary == null
            ? 'Não encontrado no PATH nem no Claude Desktop.'
            : AppPaths.maskPath(binary, env: ctx.env),
      ),
    );
    return checks;
  }

  Future<_ClaudeCredentials?> _safeCreds(ProviderContext ctx) async {
    try {
      return await _readCredentials(ctx);
    } on QdeckException {
      return null;
    }
  }

  Future<String?> _findCliBinary(ProviderContext ctx) async {
    final onPath = await ctx.discovery.firstBinary(const ['claude']);
    if (onPath != null) return onPath;
    for (final file in AppPaths.bundledClaudeBinaries(env: ctx.env)) {
      if (await file.exists()) return file.path;
    }
    return null;
  }

  Future<File?> _newestUsageFile(ProviderContext ctx) async {
    File? newest;
    DateTime? newestAt;
    for (final file in AppPaths.claudeDesktopUsageFiles(env: ctx.env)) {
      if (!p.basename(file.path).startsWith('plan-usage')) continue;
      if (!await file.exists()) continue;
      final stat = await file.stat();
      if (newestAt == null || stat.modified.isAfter(newestAt)) {
        newest = file;
        newestAt = stat.modified;
      }
    }
    return newest;
  }

  Future<_ClaudeDesktopUsage?> _readDesktopUsage(File file) async {
    if (!p.basename(file.path).startsWith('plan-usage')) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final samples = decoded['samples'];
      if (samples is! List || samples.isEmpty) return null;
      Map? best;
      num? bestT;
      for (final raw in samples) {
        if (raw is! Map) continue;
        final t = raw['t'];
        if (t is! num) continue;
        if (bestT == null || t > bestT) {
          best = raw;
          bestT = t;
        }
      }
      if (best == null || bestT == null) return null;
      final u = best['u'];
      if (u is! Map) return null;
      final fh = asDoubleOrNull(u['fh']);
      final sd = asDoubleOrNull(u['sd']);
      if (fh == null && sd == null) return null;
      return _ClaudeDesktopUsage(
        seenAt: DateTime.fromMillisecondsSinceEpoch(bestT.round(), isUtc: true),
        fiveHour: fh,
        sevenDay: sd,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_ClaudeCredentials?> _readCredentials(ProviderContext ctx) async {
    try {
      Map<String, dynamic>? raw;
      final override = ctx.env['QDECK_CLAUDE_CREDS'];
      if (override != null && override.isNotEmpty) {
        final file = File(override);
        if (!await file.exists()) return null;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) raw = decoded;
      } else if (Platform.isMacOS) {
        final result = await ctx.process.run('security', [
          'find-generic-password',
          '-s',
          'Claude Code-credentials',
          '-w',
        ], timeout: const Duration(seconds: 10));
        if (!result.ok || result.stdout.trim().isEmpty) {
          throw QdeckException(
            code: QdeckErrorCode.authMissing,
            provider: id,
            message: 'Item do Keychain não encontrado.',
          );
        }
        final decoded = jsonDecode(result.stdout.trim());
        if (decoded is Map<String, dynamic>) raw = decoded;
      } else {
        final file = AppPaths.claudeCredentials(env: ctx.env);
        if (!await file.exists()) return null;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) raw = decoded;
      }
      if (raw == null) return null;
      final oauth = raw['claudeAiOauth'] is Map<String, dynamic>
          ? raw['claudeAiOauth'] as Map<String, dynamic>
          : raw;
      final accessToken =
          (oauth['accessToken'] ?? oauth['access_token'])?.toString() ?? '';
      final expiresRaw = oauth['expiresAt'] ?? oauth['expires_at'];
      DateTime? expiresAt;
      if (expiresRaw is num) {
        var ms = expiresRaw.toDouble();
        if (ms < 10000000000) ms *= 1000;
        expiresAt = DateTime.fromMillisecondsSinceEpoch(
          ms.round(),
          isUtc: true,
        );
      } else if (expiresRaw != null) {
        final numeric = int.tryParse(expiresRaw.toString());
        if (numeric != null) {
          var ms = numeric.toDouble();
          if (ms < 10000000000) ms *= 1000;
          expiresAt = DateTime.fromMillisecondsSinceEpoch(
            ms.round(),
            isUtc: true,
          );
        } else {
          expiresAt = parseDate(expiresRaw);
        }
      }
      return _ClaudeCredentials(
        accessToken: accessToken,
        expiresAt: expiresAt,
        subscriptionType: oauth['subscriptionType']?.toString(),
      );
    } on QdeckException {
      rethrow;
    } catch (e) {
      ctx.log('Claude: falha ao ler credenciais (${e.runtimeType}).');
      return null;
    }
  }
}

class _ClaudeCredentials {
  final String accessToken;
  final DateTime? expiresAt;
  final String? subscriptionType;

  const _ClaudeCredentials({
    required this.accessToken,
    required this.expiresAt,
    required this.subscriptionType,
  });
}

class _ClaudeDesktopUsage {
  final DateTime seenAt;
  final double? fiveHour;
  final double? sevenDay;

  const _ClaudeDesktopUsage({
    required this.seenAt,
    this.fiveHour,
    this.sevenDay,
  });
}
