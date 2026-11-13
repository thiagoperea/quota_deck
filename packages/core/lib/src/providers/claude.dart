import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:quota_deck_models/quota_deck_models.dart';

import '../claude_desktop_auth.dart';
import '../errors.dart';
import '../paths.dart';
import '../process_runner.dart';
import '../provider.dart';

class ClaudeProvider implements ProviderAdapter {
  const ClaudeProvider();

  @override
  ProviderId get id => ProviderId.claude;

  static const _srcCli = 'claude-oauth-usage';
  static const _srcDesktop = 'claude-desktop-history';
  static const _srcDesktopOauth = 'claude-desktop-oauth';

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
    // Credencial sozinha (Keychain/arquivo antigo) não é instalação: sem
    // binário nem app, o Claude Code não existe nesta máquina. Override
    // explícito (`QDECK_CLAUDE_CREDS`) conta como instalação para CI/testes.
    final installed =
        binary != null || (ctx.env['QDECK_CLAUDE_CREDS'] ?? '').isNotEmpty;
    final authenticated =
        installed && creds != null && creds.accessToken.isNotEmpty && !expired;
    return SurfaceState(
      surface: ProviderSurface.cli,
      installed: installed,
      authenticated: authenticated,
      live: true,
      location: binary != null
          ? AppPaths.maskPath(binary, env: ctx.env)
          : (fileExists ? AppPaths.maskPath(file.path, env: ctx.env) : null),
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
    final token = await readClaudeDesktopToken(ctx);
    final appBundle = await ctx.discovery.hasAppBundle(const ['Claude']);
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
    // Histórico antigo sozinho não é "instalado": pode ser sobra de um app
    // desinstalado (foi o que mostrou "Desktop conectado" com 40 dias).
    // No macOS, diretório de dados é sobra de app desinstalado; o sinal
    // confiável é o bundle. Em Windows/Linux o diretório é o próprio instalador.
    final installed =
        appBundle || running || (!Platform.isMacOS && installedDir != null);
    // Token sozinho é sobra de login antigo (o app pode ter sido removido):
    // só conta como "conectado" se o app estiver instalado.
    final authenticated = installed && (token != null || usage != null);
    return SurfaceState(
      surface: ProviderSurface.desktop,
      installed: installed,
      authenticated: authenticated,
      live: token != null,
      location: historyFile == null
          ? installedDir
          : AppPaths.maskPath(historyFile.path, env: ctx.env),
      account: null,
      reason: token != null
          ? 'Sessão do Claude Desktop (app) encontrada; leitura ao vivo.'
          : !installed
          ? 'Claude Desktop não instalado.'
          : usage == null
          ? 'Claude Desktop detectado, sem histórico de uso legível.'
          : 'Histórico local do Claude Desktop (estimado, atualiza com o app aberto).',
      action: authenticated ? null : 'Abra o Claude Desktop e faça login; o QuotaDeck lê a sessão do app.',
    );
  }

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    var firstError = QdeckException(
      code: QdeckErrorCode.authMissing,
      provider: id,
      message: 'Claude sem sessão legível.',
    );

    // 1. Sessão da CLI, quando existir e estiver válida.
    try {
      final creds = await _readCredentials(ctx);
      if (creds == null || creds.accessToken.isEmpty) {
        firstError = QdeckException(
          code: QdeckErrorCode.authMissing,
          provider: id,
          message: 'Claude Code sem credencial utilizável.',
        );
      } else if (creds.expiresAt != null &&
          creds.expiresAt!.isBefore(ctx.now())) {
        firstError = QdeckException(
          code: QdeckErrorCode.authExpired,
          provider: id,
          message: 'Token do Claude Code expirado.',
          details: {'expiresAt': formatDate(creds.expiresAt)},
        );
      } else {
        return await _fetchUsage(
          ctx,
          accessToken: creds.accessToken,
          accountLabel: 'Claude Code',
          plan: creds.subscriptionType,
          surface: ProviderSurface.cli,
          source: _srcCli,
        );
      }
    } on QdeckException catch (error) {
      firstError = error;
    }

    // 2. Sessão OAuth do Claude Desktop (GUI). Mesma API, token do app.
    final desktopToken = await readClaudeDesktopToken(ctx);
    if (desktopToken != null) {
      try {
        return await _fetchUsage(
          ctx,
          accessToken: desktopToken.accessToken,
          accountLabel: 'Claude Desktop',
          plan: desktopToken.subscriptionType,
          surface: ProviderSurface.desktop,
          source: _srcDesktopOauth,
        );
      } on QdeckException catch (error) {
        firstError = error;
      }
    }

    // 3. Histórico local do Desktop: estimado, mas melhor que nada.
    final desktop = await _readDesktop(ctx);
    if (desktop != null) return desktop;

    final installed =
        await _findCliBinary(ctx) != null ||
        (ctx.env['QDECK_CLAUDE_CREDS'] ?? '').isNotEmpty ||
        await ctx.discovery.hasAppBundle(const ['Claude']) ||
        await ctx.discovery.isRunning(const ['claude']);
    throw QdeckException(
      code: installed ? firstError.code : QdeckErrorCode.notInstalled,
      provider: id,
      message: installed
          ? 'Claude encontrado, mas sem sessão legível. Abra o Claude Desktop e '
                'faça login; o QuotaDeck lê a sessão do app (o CLI é opcional).'
          : 'Claude não encontrado (nem Claude Desktop nem Claude Code).',
      details: {
        ...?firstError.details,
        'surfaces': ['desktop', 'cli'],
      },
    );
  }

  /// Consulta o endpoint OAuth de uso com um token já validado.
  Future<ProviderSnapshot> _fetchUsage(
    ProviderContext ctx, {
    required String accessToken,
    required String accountLabel,
    required ProviderSurface surface,
    required String source,
    String? plan,
  }) async {
    final response = await ctx.http
        .get(
          Uri.parse('https://api.anthropic.com/api/oauth/usage'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'anthropic-beta': 'oauth-2025-04-20',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 401) {
      throw QdeckException(
        code: QdeckErrorCode.authExpired,
        provider: id,
        message: 'Sessão do $accountLabel expirou. Abra o app e faça login.',
      );
    }
    if (response.statusCode == 429) {
      throw QdeckException(
        code: QdeckErrorCode.rateLimited,
        provider: id,
        message: 'Rate limit no endpoint de uso do $accountLabel.',
        details: rateLimitDetails(response.headers),
      );
    }
    if (response.statusCode != 200) {
      throw QdeckException(
        code: QdeckErrorCode.network,
        provider: id,
        message: '$accountLabel respondeu HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Resposta do $accountLabel não é um objeto JSON.',
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
        message: '$accountLabel respondeu sem janelas conhecidas.',
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
      account: AccountInfo(label: accountLabel, plan: plan),
      windows: windows,
      credits: credits,
      source: source,
      sourceId: source,
      surface: surface,
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
              : expires.isBefore(ctx.now())
              ? 'token expirado em ${formatDate(expires)}. '
                    'Abra o Claude Code para renovar.'
              : 'expira em ${formatDate(expires)}',
        ),
      );
    }

    final history = await _newestUsageFile(ctx);
    final usage = history == null ? null : await _readDesktopUsage(history);
    final desktopToken = await readClaudeDesktopToken(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'desktop-oauth',
        label: 'Claude Desktop (sessão do app)',
        status: desktopToken == null ? DoctorStatus.warn : DoctorStatus.ok,
        message: desktopToken == null
            ? 'Token da GUI não encontrado/decifrável.'
            : 'accessToken presente; plano=${desktopToken.subscriptionType ?? 'n/a'}; '
                  'expira em ${formatDate(desktopToken.expiresAt) ?? 'n/a'}.',
      ),
    );
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
        raw = await _readMacCredentials(ctx);
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

  /// macOS: Keychain padrão + arquivo, respeitando `CLAUDE_CONFIG_DIR`.
  ///
  /// Com diretório customizado o serviço do Keychain ganha um hash que não
  /// temos como calcular, então o arquivo é a fonte confiável.
  Future<Map<String, dynamic>?> _readMacCredentials(ProviderContext ctx) async {
    final configDir = (ctx.env['CLAUDE_CONFIG_DIR'] ?? '').trim();
    final file = AppPaths.claudeCredentials(env: ctx.env);
    if (configDir.isNotEmpty) {
      final fromFile = await _readCredentialFile(ctx, file);
      if (fromFile != null) return fromFile;
    }

    final result = await ctx.process.run('security', [
      'find-generic-password',
      '-s',
      'Claude Code-credentials',
      '-w',
    ], timeout: const Duration(seconds: 10));

    if (result.ok && result.stdout.trim().isNotEmpty) {
      final decoded = jsonDecode(result.stdout.trim());
      if (decoded is Map<String, dynamic>) return decoded;
      throw QdeckException(
        code: QdeckErrorCode.credentialUnreadable,
        provider: id,
        message: 'Item do Keychain do Claude sem JSON válido.',
      );
    }
    if (_isKeychainDenied(result)) {
      throw QdeckException(
        code: QdeckErrorCode.permissionDenied,
        provider: id,
        message:
            'O macOS negou acesso ao Keychain do Claude. '
            'Autorize o QuotaDeck (ou destrave o Keychain) e tente de novo.',
      );
    }
    // Item ausente: último recurso é o arquivo padrão (~/.claude).
    return _readCredentialFile(ctx, file);
  }

  Future<Map<String, dynamic>?> _readCredentialFile(
    ProviderContext ctx,
    File file,
  ) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('credencial sem objeto');
    } on QdeckException {
      rethrow;
    } catch (e) {
      ctx.log('Claude: credencial ilegível (${e.runtimeType}).');
      throw QdeckException(
        code: QdeckErrorCode.credentialUnreadable,
        provider: id,
        message:
            'Arquivo de credencial do Claude existe mas não pôde ser lido '
            '(${AppPaths.maskPath(file.path, env: ctx.env)}). '
            'Rode `claude` para autenticar de novo.',
      );
    }
  }

  bool _isKeychainDenied(ProcessResultData result) {
    // 51 = errSecAuthFailed, 45 = interação não permitida (Keychain travado).
    if (result.exitCode == 51 || result.exitCode == 45) return true;
    final err = result.stderr.toLowerCase();
    return err.contains('denied') ||
        err.contains('not authorized') ||
        err.contains('interaction is not allowed');
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
