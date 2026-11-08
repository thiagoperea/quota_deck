# Arquitetura

O QuotaDeck é um app Flutter desktop + CLI. O desktop é **single-process**: a UI chama o core Dart no mesmo processo. Não existe daemon, porta HTTP, cookie ou token.

## Módulos

```text
app/ (Flutter)
  ├── UI (dashboard, compacto, settings)
  ├── TrayService (tray_manager + window_manager)
  └── LocalQuotaApi ──► packages/core

packages/models   DTOs, config, status, redaction (Dart puro)
packages/core     providers, cache, histórico SQLite, paths, doctor
packages/cli      qdeck (usa o core diretamente)
```

- `packages/models` é Dart puro e sem `dart:io`; é importado por todos.
- `packages/core` usa `dart:io`, `sqlite3`, `http` e processos.
- `app` importa o core diretamente (desktop).
- `packages/cli` é um binário Dart independente da UI.

## Fluxo desktop

```text
main()
  ├── windowManager.ensureInitialized()
  ├── cria AppState(LocalQuotaApi)
  ├── TrayService.initialize()
  ├── runApp(...)
  └── windowManager.waitUntilReadyToShow()
```

Na primeira carga, `AppState.initialize()` chama `LocalQuotaApi.fetchSummary()`:

```text
LocalQuotaApi
  └── DefaultQuotaService.create()
        ├── AppPaths.forPlatform()
        ├── ConfigStore / SnapshotCache / HistoryStore
        └── adapters: OpenCode, Antigravity, Codex, Claude
```

Cada adapter lê a credencial local e consulta a fonte mais barata. O resultado é normalizado em `ProviderSnapshot` e renderizado nos cards.

## Bandeja e janela

- `TrayService` registra o ícone e o menu (Abrir, Dashboard, Atualizar, Sair).
- Clique esquerdo alterna a janela compacta (420×760).
- Dashboard abre em 1100×800.
- Fechar a janela esconde para a bandeja; “Sair” encerra o processo.
- macOS usa ícone template (monocromático); Windows/Linux usam o ícone colorido.

## Providers

| Provider | Fonte principal | Fallback |
|---|---|---|
| OpenCode | `GET /zen/go/v1/usage` + SQLite `credential` | cache |
| Antigravity | RPC local `RetrieveUserQuotaSummary` | cache |
| Codex | `codex app-server` → `account/rateLimits/read` | `wham/usage` |
| Claude Code | `GET /api/oauth/usage` + Keychain/arquivo | cache |

Cada adapter implementa:

```dart
abstract class ProviderAdapter {
  ProviderId get id;
  Future<DetectionResult> detect(ProviderContext ctx);
  Future<ProviderSnapshot> read(ProviderContext ctx);
  Future<List<DoctorCheck>> doctor(ProviderContext ctx);
}
```

Detalhes em [`providers/`](providers/).

## Cache e histórico

- Cache em JSON com TTL de 60 s e fallback `stale` de até 24 h.
- Histórico em SQLite (`history.db`), amostras a cada 5 min ou delta ≥ 1%.
- Burn rate por regressão linear; ETA = `(100 - usado) / burnRate`.
- Retenção de 30 dias.

## Erros

Cada provider pode falhar sem derrubar os outros. Os erros são tipados (`AUTH_MISSING`, `AUTH_EXPIRED`, `NETWORK`, `RATE_LIMITED`, `SCHEMA_CHANGED`, `PROVIDER_NOT_RUNNING`) e aparecem no card com uma ação (“Abrir Claude Code”, “Tentar novamente” etc.).

## Decisões

- **Flutter** para uma única base de UI em macOS, Windows e Linux.
- **Desktop single-process** para eliminar daemon, porta, token e lifecycle.
- **CLI no mesmo core** para scripts e statusline.
- **Sem refresh OAuth automático** para não rotacionar refresh token do usuário.
- **Read-only** em credenciais e endpoints de uso.

## Segurança

O desktop lê credenciais locais como a CLI. No macOS, o App Sandbox é desligado para acessar `~/.codex`, `~/.claude`, SQLite do OpenCode e o hub do Antigravity. Ver [`seguranca.md`](seguranca.md).
