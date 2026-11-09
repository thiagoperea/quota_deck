import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quota_deck_core/quota_deck_core.dart';
import 'package:quota_deck_models/quota_deck_models.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qdeck_surfaces_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('opencode: XDG no Windows é candidato antes do legado', () {
    final env = {
      'HOME': r'C:\Users\me',
      'USERPROFILE': r'C:\Users\me',
      'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
      'APPDATA': r'C:\Users\me\AppData\Roaming',
    };
    final files = AppPaths.openCodeDbs(env: env)
        .map((f) => f.path.replaceAll('\\', '/'))
        .toList();
    final xdgIndex = files.indexWhere(
      (path) => path.endsWith('.local/share/opencode/opencode.db'),
    );
    final legacyIndex = files.indexWhere(
      (path) => path.endsWith('AppData/Local/opencode/opencode.db'),
    );
    expect(xdgIndex, greaterThanOrEqualTo(0));
    expect(legacyIndex, greaterThan(xdgIndex));
  });

  test('opencode: detecta e lê credencial no caminho XDG', () async {
    final home = Directory('${temp.path}/home');
    final dataDir = Directory('${home.path}/.local/share/opencode');
    await dataDir.create(recursive: true);
    final db = File('${dataDir.path}/opencode.db');
    final database = sqlite3.open(db.path);
    database.execute(
      'CREATE TABLE credential (id TEXT, integration_id TEXT, label TEXT, '
      'value TEXT, active INTEGER)',
    );
    database.execute('INSERT INTO credential VALUES (?, ?, ?, ?, ?)', [
      'cred_1',
      'opencode',
      'Default',
      jsonEncode({
        'type': 'oauth',
        'access': 'oauth-token',
        'metadata': {'orgID': 'wrk_1', 'email': 'dev@example.com'},
      }),
      1,
    ]);
    database.close();

    final env = {'HOME': home.path, 'USERPROFILE': home.path};
    final ctx = ProviderContext(
      paths: AppPaths(temp),
      http: MockClient((request) async {
        expect(request.headers['x-opencode-org-id'], 'wrk_1');
        return http.Response(
          File('test/fixtures/opencode-go-usage.json').readAsStringSync(),
          200,
        );
      }),
      process: FakeProcessRunner(),
      env: env,
      now: () => DateTime.utc(2026, 11, 9, 12),
      log: (_) {},
    );

    final detection = await const OpenCodeProvider().detect(ctx);
    expect(detection.detected, isTrue);
    expect(
      detection.surfaces.where((s) => s.authenticated),
      isNotEmpty,
      reason: 'a credencial do banco XDG precisa ser reconhecida',
    );

    final snapshot = await const OpenCodeProvider().read(ctx);
    expect(snapshot.surface, ProviderSurface.cli);
    expect(snapshot.sourceId, 'opencode-db');
    expect(snapshot.account.maskedEmail, contains('***'));
  });

  test('claude: cai para o histórico do desktop quando não há CLI', () async {
    final localAppData = Directory('${temp.path}/local');
    final dataDir = Directory(
      '${localAppData.path}${Platform.pathSeparator}Claude-Data'
      '${Platform.pathSeparator}claude_test',
    );
    await dataDir.create(recursive: true);
    File('${dataDir.path}/plan-usage-history.json').writeAsStringSync(
      jsonEncode({
        'version': 2,
        'samples': [
          {
            't': DateTime.utc(2026, 11, 9, 10).millisecondsSinceEpoch,
            'u': {'fh': 3, 'sd': 8},
          },
          {
            't': DateTime.utc(2026, 11, 9, 11, 30).millisecondsSinceEpoch,
            'u': {'fh': 42, 'sd': 17},
          },
        ],
      }),
    );

    final env = {
      'HOME': Directory('${temp.path}/home').path,
      'USERPROFILE': Directory('${temp.path}/home').path,
      'LOCALAPPDATA': localAppData.path,
      'QDECK_CLAUDE_CREDS': '${temp.path}/missing-credentials.json',
    };
    final ctx = ProviderContext(
      paths: AppPaths(temp),
      http: MockClient((_) async => http.Response('{}', 500)),
      process: FakeProcessRunner(),
      env: env,
      now: () => DateTime.utc(2026, 11, 9, 12),
      log: (_) {},
    );

    final detection = await const ClaudeProvider().detect(ctx);
    final desktop = detection.surfaces.firstWhere(
      (s) => s.surface == ProviderSurface.desktop,
    );
    expect(desktop.installed, isTrue);
    expect(desktop.authenticated, isTrue);
    expect(desktop.live, isFalse);

    final snapshot = await const ClaudeProvider().read(ctx);
    expect(snapshot.surface, ProviderSurface.desktop);
    expect(snapshot.source, 'claude-desktop-history');
    expect(snapshot.confidence, Confidence.low);
    expect(snapshot.windows, hasLength(2));
    expect(snapshot.windows[0].usedPercent, 42);
    expect(snapshot.windows[1].usedPercent, 17);
    expect(snapshot.windows[0].resetsAt, isNull);
    expect(
      snapshot.errors.map((e) => e.code),
      contains('AUTH_MISSING'),
      reason: 'o fallback precisa carregar o erro original do CLI',
    );
    expect(snapshot.stale, isFalse);
  });

  test('percentual ausente não vira 0%', () async {
    final home = Directory('${temp.path}/home2');
    final dataDir = Directory('${home.path}/.local/share/opencode');
    await dataDir.create(recursive: true);
    final db = File('${dataDir.path}/opencode.db');
    final database = sqlite3.open(db.path);
    database.execute(
      'CREATE TABLE credential (id TEXT, integration_id TEXT, label TEXT, '
      'value TEXT, active INTEGER)',
    );
    database.execute('INSERT INTO credential VALUES (?, ?, ?, ?, ?)', [
      'cred_2',
      'opencode',
      'Default',
      jsonEncode({'type': 'key', 'key': 'k'}),
      1,
    ]);
    database.close();

    final ctx = ProviderContext(
      paths: AppPaths(temp),
      http: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'usage': {
              'rolling': {'resetsAt': '2026-11-09T15:00:00Z'},
              'weekly': {'percent': 20},
            },
          }),
          200,
        ),
      ),
      process: FakeProcessRunner(),
      env: {'HOME': home.path, 'USERPROFILE': home.path},
      now: () => DateTime.utc(2026, 11, 9, 12),
      log: (_) {},
    );

    final snapshot = await const OpenCodeProvider().read(ctx);
    expect(snapshot.windows, hasLength(1));
    expect(snapshot.windows.single.id, 'weekly');
    expect(snapshot.windows.single.usedPercent, 20);
  });

  test('detection: serialize surfaces', () {
    final result = DetectionResult.fromSurfaces(
      provider: ProviderId.claude,
      surfaces: const [
        SurfaceState(
          surface: ProviderSurface.desktop,
          installed: true,
          authenticated: true,
          live: false,
        ),
        SurfaceState(surface: ProviderSurface.cli, installed: false),
      ],
    );
    final json = result.toJson();
    expect(json['detected'], isTrue);
    expect((json['surfaces'] as List), hasLength(2));
    final decoded = SurfaceState.fromJson(
      (json['surfaces'] as List).first as Map<String, dynamic>,
    );
    expect(decoded.surface, ProviderSurface.desktop);
    expect(decoded.authenticated, isTrue);
  });
}
