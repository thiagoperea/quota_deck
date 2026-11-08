import 'dart:convert';

import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:sqlite3/sqlite3.dart';

import '../errors.dart';
import '../paths.dart';
import '../provider.dart';

class OpenCodeProvider implements ProviderAdapter {
  const OpenCodeProvider();

  @override
  ProviderId get id => ProviderId.opencode;

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async {
    final db = AppPaths.openCodeDb(env: ctx.env);
    if (!await db.exists()) {
      return const DetectionResult(
        provider: ProviderId.opencode,
        detected: false,
        reason: 'Banco do OpenCode não encontrado.',
      );
    }
    final cred = _readCredential(ctx);
    if (cred == null) {
      return const DetectionResult(
        provider: ProviderId.opencode,
        detected: false,
        reason: 'Credencial opencode-go/opencode não encontrada.',
      );
    }
    return DetectionResult(
      provider: ProviderId.opencode,
      detected: true,
      reason: 'Credencial ${cred.type} encontrada.',
    );
  }

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    final cred = _readCredential(ctx);
    if (cred == null) {
      throw QdeckException(
        code: QdeckErrorCode.authMissing,
        provider: id,
        message:
            'Credencial do OpenCode Go não encontrada. Faça login no OpenCode.',
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
        message: 'OpenCode Go rejeitou a credencial. Reautentique no OpenCode.',
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

    return ProviderSnapshot(
      provider: id,
      account: const AccountInfo(label: 'OpenCode Go', plan: 'Go'),
      windows: windows,
      source: 'opencode-usage-api',
      fetchedAt: ctx.now(),
      confidence: Confidence.medium,
    );
  }

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async {
    final checks = <DoctorCheck>[];
    final db = AppPaths.openCodeDb(env: ctx.env);
    final exists = await db.exists();
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'db',
        label: 'Banco do OpenCode',
        status: exists ? DoctorStatus.ok : DoctorStatus.fail,
        message: exists
            ? 'Encontrado'
            : 'Não encontrado em ${AppPaths.maskPath(db.path, env: ctx.env)}',
      ),
    );
    if (!exists) return checks;

    final cred = _readCredential(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'credential',
        label: 'Credencial',
        status: cred == null ? DoctorStatus.fail : DoctorStatus.ok,
        message: cred == null
            ? 'Nenhuma credencial opencode-go/opencode ativa.'
            : 'Tipo ${cred.type}; org ${cred.orgId == null ? 'n/a' : 'presente'}; token presente.',
      ),
    );
    return checks;
  }

  _OpenCodeCredential? _readCredential(ProviderContext ctx) {
    final db = AppPaths.openCodeDb(env: ctx.env);
    if (!db.existsSync()) return null;
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
      if (rows.isEmpty) return null;
      final raw = rows.first['value'];
      if (raw == null) return null;
      final decoded = jsonDecode(raw.toString());
      if (decoded is! Map) return null;

      final type = (decoded['type'] ?? 'key').toString();
      String? token;
      String? orgId;
      final metadata = decoded['metadata'];
      if (metadata is Map) {
        orgId = metadata['orgID']?.toString() ?? metadata['orgId']?.toString();
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
      if (token == null || token.isEmpty) return null;
      return _OpenCodeCredential(token: token, orgId: orgId, type: type);
    } catch (e) {
      ctx.log('OpenCode: falha ao ler credencial (${e.runtimeType}).');
      return null;
    } finally {
      database?.close();
    }
  }
}

class _OpenCodeCredential {
  final String token;
  final String? orgId;
  final String type;

  const _OpenCodeCredential({
    required this.token,
    required this.orgId,
    required this.type,
  });
}
