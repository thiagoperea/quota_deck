# quota_deck_core

Core Dart do QuotaDeck: providers, cache, histórico, config e orquestração.

Roda no Dart VM (CLI e app). Usa `dart:io`, `sqlite3` e `Process`.

## Providers

| Provider | Fonte | Fallback |
|---|---|---|
| OpenCode Go | `GET https://opencode.ai/zen/go/v1/usage` + SQLite `credential` | API local experimental, cache |
| Antigravity | RPC local `RetrieveUserQuotaSummary` (hub/CSRF) | cache; statusline oficial (alternativa) |
| Codex | `codex app-server` (`account/rateLimits/read`) | `GET /backend-api/wham/usage`, cache |
| Claude Code | Keychain/arquivo + `GET /api/oauth/usage` | cache; headers passivos (alternativa) |

## Uso

```dart
final service = await DefaultQuotaService.create();
try {
  final envelope = await service.snapshot();
  print(envelope.toJson());
} finally {
  await service.dispose();
}
```

Filtros:

```dart
await service.snapshot(providers: {ProviderId.codex}, noCache: true);
await service.refresh(provider: ProviderId.opencode);
```

## Estrutura

- `lib/src/providers/` — adapters por provedor.
- `lib/src/cache.dart` — cache em disco com TTL/stale.
- `lib/src/history.dart` — SQLite de snapshots, burn rate/ETA.
- `lib/src/quota_service.dart` — registry + orquestração + fallback.
- `lib/src/paths.dart` — paths por SO.
- `lib/src/process_runner.dart` — wrapper de `Process` para testes.
- `lib/src/errors.dart` — taxonomia de erros.

## Testes

```bash
dart test
QDECK_INTEGRATION=1 dart test test/integration_test.dart
dart run tool/probe.dart
dart run tool/bench.dart
```

Fixtures em `test/fixtures/` (reais anonimizadas + sintéticas).
