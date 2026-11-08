import 'dart:convert';
import 'dart:io';

import 'package:quota_deck_models/quota_deck_models.dart';

import '../errors.dart';
import '../paths.dart';
import '../provider.dart';

class ClaudeProvider implements ProviderAdapter {
  const ClaudeProvider();

  @override
  ProviderId get id => ProviderId.claude;

  @override
  Future<DetectionResult> detect(ProviderContext ctx) async {
    if (Platform.isMacOS) {
      try {
        final result = await ctx.process.run('security', [
          'find-generic-password',
          '-s',
          'Claude Code-credentials',
        ], timeout: const Duration(seconds: 5));
        if (result.ok) {
          return const DetectionResult(
            provider: ProviderId.claude,
            detected: true,
            reason: 'Item do Keychain encontrado.',
          );
        }
      } catch (_) {}
    }
    final file = AppPaths.claudeCredentials(env: ctx.env);
    if (await file.exists()) {
      return DetectionResult(
        provider: ProviderId.claude,
        detected: true,
        reason: 'Credenciais em ${AppPaths.maskPath(file.path, env: ctx.env)}.',
      );
    }
    return const DetectionResult(
      provider: ProviderId.claude,
      detected: false,
      reason: 'Credenciais do Claude Code não encontradas.',
    );
  }

  @override
  Future<ProviderSnapshot> read(ProviderContext ctx) async {
    final creds = await _readCredentials(ctx);
    if (creds == null || creds.accessToken.isEmpty) {
      throw QdeckException(
        code: QdeckErrorCode.authMissing,
        provider: id,
        message:
            'Claude Code não autenticado. Abra o Claude Code para fazer login.',
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
      final used = clampPercent(asDouble(item['utilization']));
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
      source: 'claude-oauth-usage',
      fetchedAt: ctx.now(),
      confidence: Confidence.high,
    );
  }

  @override
  Future<List<DoctorCheck>> doctor(ProviderContext ctx) async {
    final checks = <DoctorCheck>[];
    final creds = await _readCredentials(ctx);
    checks.add(
      DoctorCheck(
        provider: id,
        id: 'credentials',
        label: 'Credenciais',
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
    return checks;
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
