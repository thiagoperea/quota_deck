import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:sqlite3/sqlite3.dart';

import '../errors.dart';
import '../paths.dart';
import '../provider.dart';

class OpenCodeProvider implements ProviderAdapter {
  const OpenCodeProvider();

  @override
  ProviderId get id => ProviderId.opencode;

  static const _sourceId = 'opencode-db';

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async {
    final db = _existingDb(ctx);
    final cred = _readCredential(ctx);
    final running = await ctx.discovery.isRunning(const [
      'opencode',
      'opencode-cli',
    ]);
    final cliBinary =
        await ctx.discovery.firstBinary(const ['opencode', 'opencode-cli']) ??
        _bundledCli(ctx);
    final desktopDir = _desktopDir(ctx);
    final desktopInstalled = db != null || running || desktopDir != null;
    final cliInstalled = cliBinary != null || db != null;
    final version = desktopDir == null ? null : _versionOf(ctx, desktopDir);

    final seenAccount = cred?.email;
    return DetectionResult.fromSurfaces(
      provider: id,
      surfaces: [
        SurfaceState(
          surface: ProviderSurface.desktop,
          installed: desktopInstalled,
          authenticated: cred != null,
          live: true,
          version: version,
          location: db == null
              ? desktopDir
              : AppPaths.maskPath(db.path, env: ctx.env),
          account: seenAccount,
          reason: cred == null
              ? 'OpenCode Desktop detectado, mas sem credencial legível.'
              : 'Credencial ${cred.type} do OpenCode Desktop.',
          action: cred == null
              ? 'Abra o OpenCode Desktop e faça login; rode "Verificar agora".'
              : null,
        ),
        SurfaceState(
          surface: ProviderSurface.cli,
          installed: cliInstalled,
          authenticated: cred != null,
          live: true,
          version: version,
          location: cliBinary,
          account: seenAccount,
          reason: cred == null
              ? 'CLI detectada; mesmo banco do desktop sem credencial ativa.'
              : 'Credencial ${cred.type} compartilhada com o desktop.',
          action: cred == null
              ? 'Rode opencode no terminal e faça login.'
              : null,
        ),
      ],
    );
  }

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    final cred = _readCredential(ctx);
    if (cred == null) {
      final db = _existingDb(ctx);
      final tried = AppPaths.openCodeDbs(env: ctx.env)
          .map((f) => AppPaths.maskPath(f.path, env: ctx.env))
          .join(', ');
      throw QdeckException(
        code: QdeckErrorCode.authMissing,
        provider: id,
        message: db == null
            ? 'OpenCode não encontrado. Procurei em: $tried.'
            : 'OpenCode encontrado em ${AppPaths.maskPath(db.path, env: ctx.env)}, '
                  'mas sem credencial ativa. Faça login no OpenCode.',
      );
    }

    final headers = <String, String>{
      'Authorization': 'Bearer ${cred.token}',
      'Accept': 'application/json',
    };
    if (cred.orgId != null && cred.orgId!.isNotEmpty) {
      headers['x-opencode-org-id'] = cred.orgId!;
    }

    final response = await ctx.http
        .get(Uri.parse('https://opencode.ai/zen/go/v1/usage'), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      throw QdeckException(
        code: QdeckErrorCode.authExpired,
        provider: id,
        message: 'OpenCode rejeitou a credencial. Reautentique no app ou CLI.',
      );
    }
    if (response.statusCode == 403) {
      throw QdeckException(
        code: QdeckErrorCode.authMissing,
        provider: id,
        message: 'Workspace sem assinatura OpenCode Go.',
      );
    }
    if (response.statusCode == 429) {
      throw QdeckException(
        code: QdeckErrorCode.rateLimited,
        provider: id,
        message: 'Rate limit no endpoint de uso do OpenCode.',
      );
    }
    if (response.statusCode != 200) {
      throw QdeckException(
        code: QdeckErrorCode.network,
        provider: id,
        message: 'OpenCode respondeu HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Resposta do OpenCode não é um objeto JSON.',
      );
    }
    final usage = decoded['usage'];
    if (usage is! Map) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'Resposta do OpenCode sem campo usage.',
      );
    }

    final windows = <QuotaWindow>[];
    for (final key in const ['rolling', 'weekly', 'monthly']) {
      final item = usage[key];
      if (item is! Map) continue;
      final used = clampPercent(asDouble(item['percent']));
      final status = statusForUsed(used, explicit: item['status']?.toString());
      windows.add(
        QuotaWindow(
          id: key,
          label: labelForWindow(key),
          kind: kindForWindow(key),
          usedPercent: used,
          remainingPercent: clampPercent(100 - used),
          resetsAt: parseDate(item['resetsAt']),
          status: status,
          source: SourceKind.api,
        ),
      );
    }

    if (windows.isEmpty) {
      throw QdeckException(
        code: QdeckErrorCode.schemaChanged,
        provider: id,
        message: 'OpenCode respondeu sem janelas conhecidas.',
      );
    }

    final desktop =
        _desktopDir(ctx) != null ||
        await ctx.discovery.isRunning(const ['opencode']);
    return ProviderSnapshot(
      provider: id,
      account: AccountInfo(
        label: 'OpenCode',
        plan: cred.plan,
        maskedEmail: cred.email == null ? null : maskEmail(cred.email!),
      ),
      windows: windows,
      source: 'opencode-usage-api',
      sourceId: _sourceId,
      surface: desktop ? ProviderSurface.desktop : ProviderSurface.cli,
      fetchedAt: ctx.now(),
      confidence: Confidence.medium,
    );
  }

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async {
    final checks = <DoctorCheck>[];
    final dbs = AppPaths.openCodeDbs(env: ctx.env);
    final found = _existingDb(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'db',
        label: 'Banco do OpenCode',
        status: found == null ? DoctorStatus.fail : DoctorStatus.ok,
        message: found == null
            ? 'Não encontrado. Caminhos: '
                  '${dbs.map((f) => AppPaths.maskPath(f.path, env: ctx.env)).join(', ')}'
            : 'Encontrado em ${AppPaths.maskPath(found.path, env: ctx.env)}',
      ),
    );
    final cred = _readCredential(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'credential',
        label: 'Credencial',
        status: cred == null ? DoctorStatus.fail : DoctorStatus.ok,
        message: cred == null
            ? 'Nenhuma credencial opencode-go/opencode ativa.'
            : 'Tipo ${cred.type}; org ${cred.orgId == null ? 'n/a' : 'presente'}; '
                  'token presente.',
      ),
    );
    final running = await ctx.discovery.isRunning(const [
      'opencode',
      'opencode-cli',
    ]);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'desktop',
        label: 'OpenCode Desktop',
        status: running ? DoctorStatus.ok : DoctorStatus.warn,
        message: running ? 'Em execução.' : 'Não está rodando agora.',
      ),
    );
    return checks;
  }

  File? _existingDb(ProviderContext ctx) {
    for (final file in AppPaths.openCodeDbs(env: ctx.env)) {
      if (file.existsSync()) return file;
    }
    return null;
  }

  String? _desktopDir(ProviderContext ctx) {
    final env = ctx.env;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    final candidates = <String>[
      if ((env['APPDATA'] ?? '').isNotEmpty)
        p.join(env['APPDATA']!, 'ai.opencode.desktop'),
      if ((env['LOCALAPPDATA'] ?? '').isNotEmpty)
        p.join(env['LOCALAPPDATA']!, 'Programs', 'ai.opencode.desktop'),
      if (home.isNotEmpty) p.join(home, '.config', 'ai.opencode.desktop'),
      if (home.isNotEmpty)
        p.join(home, 'AppData', 'Roaming', 'ai.opencode.desktop'),
    ];
    for (final candidate in candidates) {
      if (FileSystemEntity.isDirectorySync(candidate)) return candidate;
    }
    return null;
  }

  String? _bundledCli(ProviderContext ctx) {
    final appData = ctx.env['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    final cliRoot = Directory(p.join(appData, 'ai.opencode.desktop', 'cli'));
    if (!cliRoot.existsSync()) return null;
    for (final version in cliRoot.listSync(followLinks: false)) {
      if (version is! Directory) continue;
      for (final name in const ['opencode-cli.exe', 'opencode.exe']) {
        final file = File(p.join(version.path, name));
        if (file.existsSync()) return file.path;
      }
    }
    return null;
  }

  String? _versionOf(ProviderContext ctx, String dir) {
    final appData = ctx.env['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    final file = File(p.join(appData, 'ai.opencode.desktop', 'Preferences'));
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        final version = decoded['version'];
        if (version is String) return version;
      }
    } catch (_) {}
    return null;
  }

  _OpenCodeCredential? _readCredential(ProviderContext ctx) {
    final db = _existingDb(ctx);
    if (db == null) return null;
    Database? database;
    try {
      database = sqlite3.open(db.path, mode: OpenMode.readOnly);
      ResultSet rows;
      try {
        rows = database.select(
          "SELECT value FROM credential "
          "WHERE integration_id IN ('opencode-go','opencode') AND active = 1 "
          "ORDER BY CASE WHEN integration_id = 'opencode-go' THEN 0 ELSE 1 END "
          "LIMIT 1",
        );
      } on SqliteException {
        rows = database.select(
          "SELECT value FROM credential "
          "WHERE integration_id IN ('opencode-go','opencode') LIMIT 1",
        );
      }
      if (rows.isEmpty) return _readAccount(database);
      final raw = rows.first['value'];
      if (raw == null) return _readAccount(database);
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return _readAccount(database);

      final type = (decoded['type'] ?? 'key').toString();
      String? token;
      String? orgId;
      String? email;
      String? orgName;
      final metadata = decoded['metadata'];
      if (metadata is Map) {
        orgId = metadata['orgID']?.toString() ?? metadata['orgId']?.toString();
        email = metadata['email']?.toString();
        orgName = metadata['orgName']?.toString();
      }
      if (type == 'oauth') {
        token = decoded['access']?.toString();
      } else {
        token = decoded['key']?.toString();
      }
      token ??=
          decoded['access_token']?.toString() ??
          decoded['token']?.toString() ??
          decoded['key']?.toString();
      if (token == null || token.isEmpty) return _readAccount(database);
      return _OpenCodeCredential(
        token: token,
        orgId: orgId,
        type: type,
        email: email,
        plan: orgName,
      );
    } catch (e) {
      ctx.log('OpenCode: falha ao ler credencial (${e.runtimeType}).');
      return null;
    } finally {
      database?.close();
    }
  }

  _OpenCodeCredential? _readAccount(Database database) {
    try {
      final rows = database.select(
        'SELECT email, access_token FROM account LIMIT 1',
      );
      if (rows.isEmpty) return null;
      final token = rows.first['access_token']?.toString();
      if (token == null || token.isEmpty) return null;
      return _OpenCodeCredential(
        token: token,
        orgId: null,
        type: 'account',
        email: rows.first['email']?.toString(),
        plan: null,
      );
    } catch (_) {
      return null;
    }
  }
}

class _OpenCodeCredential {
  final String token;
  final String? orgId;
  final String type;
  final String? email;
  final String? plan;

  const _OpenCodeCredential({
    required this.token,
    required this.orgId,
    required this.type,
    this.email,
    this.plan,
  });
}
