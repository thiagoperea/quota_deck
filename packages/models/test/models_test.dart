import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:test/test.dart';

void main() {
  group('ProviderSnapshot', () {
    test('json roundtrip', () {
      final snapshot = ProviderSnapshot(
        provider: ProviderId.opencode,
        account: const AccountInfo(label: 'OpenCode Go', plan: 'Go'),
        windows: [
          QuotaWindow(
            id: 'rolling',
            label: 'Rolling 5h',
            kind: WindowKind.rolling,
            usedPercent: 4.0,
            remainingPercent: 96.0,
            resetsAt: DateTime.utc(2026, 11, 8, 18, 45, 25),
            status: QuotaStatus.ok,
            source: SourceKind.api,
          ),
        ],
        source: 'opencode-usage-api',
        fetchedAt: DateTime.utc(2026, 11, 8, 14, 0, 0),
        confidence: Confidence.medium,
      );

      final json = snapshot.toJson();
      final decoded = ProviderSnapshot.fromJson(json);

      expect(decoded.provider, ProviderId.opencode);
      expect(decoded.account.label, 'OpenCode Go');
      expect(decoded.windows, hasLength(1));
      expect(decoded.windows.first.usedPercent, 4.0);
      expect(decoded.windows.first.remainingPercent, 96.0);
      expect(
        decoded.windows.first.resetsAt,
        DateTime.utc(2026, 11, 8, 18, 45, 25),
      );
      expect(decoded.confidence, Confidence.medium);
    });

    test('parse epoch seconds and milliseconds', () {
      expect(
        parseDate(1794163949),
        DateTime.fromMillisecondsSinceEpoch(1794163949000, isUtc: true),
      );
      expect(
        parseDate(1794163949000),
        DateTime.fromMillisecondsSinceEpoch(1794163949000, isUtc: true),
      );
    });

    test('worst window', () {
      final snapshot = ProviderSnapshot(
        provider: ProviderId.codex,
        account: const AccountInfo(label: 'Codex'),
        windows: [
          QuotaWindow(
            id: 'primary',
            label: '5h',
            kind: WindowKind.session,
            usedPercent: 10,
            remainingPercent: 90,
            status: QuotaStatus.ok,
            source: SourceKind.api,
          ),
          QuotaWindow(
            id: 'secondary',
            label: '7d',
            kind: WindowKind.weekly,
            usedPercent: 62,
            remainingPercent: 38,
            status: QuotaStatus.warning,
            source: SourceKind.api,
          ),
        ],
        source: 'test',
        fetchedAt: DateTime.utc(2026),
      );
      expect(snapshot.worstUsedPercent, 62);
      expect(snapshot.worstWindow?.id, 'secondary');
    });
  });

  group('AppConfig', () {
    test('defaults and partial json', () {
      final defaults = AppConfig.defaults();
      expect(defaults.providers['opencode'], isTrue);
      expect(defaults.refreshSeconds, 60);

      final parsed = AppConfig.fromJson({
        'providers': {'codex': false},
        'refreshSeconds': 30,
        'theme': 'dark',
      });
      expect(parsed.providers['codex'], isFalse);
      expect(parsed.providers['opencode'], isTrue);
      expect(parsed.refreshSeconds, 30);
      expect(parsed.theme, 'dark');
    });

    test('roundtrip', () {
      final config = AppConfig.defaults().copyWith(
        refreshSeconds: 120,
        warningThreshold: 75,
        theme: 'light',
      );
      final decoded = AppConfig.fromJson(config.toJson());
      expect(decoded.refreshSeconds, 120);
      expect(decoded.warningThreshold, 75);
      expect(decoded.theme, 'light');
    });
  });

  group('status', () {
    test('thresholds', () {
      expect(statusForUsed(0), QuotaStatus.ok);
      expect(statusForUsed(79.9), QuotaStatus.ok);
      expect(statusForUsed(80), QuotaStatus.warning);
      expect(statusForUsed(95), QuotaStatus.critical);
      expect(statusForUsed(100), QuotaStatus.limited);
      expect(statusForUsed(20, explicit: 'rate-limited'), QuotaStatus.limited);
    });

    test('labels and kinds', () {
      expect(labelForWindow('rolling'), 'Rolling 5h');
      expect(labelForWindow('seven_day_opus'), 'Semanal Opus');
      expect(kindForWindow('five_hour'), WindowKind.rolling);
      expect(kindForWindow('seven_day'), WindowKind.weekly);
      expect(kindForWindow('x', durationSeconds: 18000), WindowKind.session);
      expect(kindForWindow('x', durationSeconds: 604800), WindowKind.weekly);
    });

    test('relative time', () {
      final now = DateTime.utc(2026, 11, 8, 12);
      expect(relativeTime(now, now: now), 'agora');
      expect(
        relativeTime(now.add(const Duration(minutes: 30)), now: now),
        'em 30 min',
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 2)), now: now),
        'há 2 h',
      );
    });
  });

  group('redaction', () {
    test('redacts known token shapes', () {
      const input =
          'Authorization: Bearer oc_abcdefghijklmnopqrstuvwxyz '
          'token=sk-ant-abcdefghijklmnopqrstuvwxyz '
          'jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdef '
          'csrfToken=123e4567-e89b-12d3-a456-426614174000';
      final out = redact(input);
      expect(out, isNot(contains('oc_abcdefghijklmnopqrstuvwxyz')));
      expect(out, isNot(contains('sk-ant-abcdefghijklmnopqrstuvwxyz')));
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(out, contains('<redacted>'));
    });

    test('masks email', () {
      expect(maskEmail('user@example.com'), 'us***@e***.com');
      expect(maskEmail(null), '');
    });

    test('redacts quoted JSON credentials', () {
      const input =
          '{"access_token":"abc123secret","refreshToken":"rt_987","apiKey":"k-1"}';
      final out = redact(input);
      expect(out, isNot(contains('abc123secret')));
      expect(out, isNot(contains('rt_987')));
      expect(out, isNot(contains('k-1')));
      expect(out, contains('"access_token":"<redacted>"'));
      expect(out, contains('"refreshToken":"<redacted>"'));
      expect(out, contains('"apiKey":"<redacted>"'));
    });
  });
}
