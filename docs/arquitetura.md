# Arquitetura

O QuotaDeck é um app Flutter desktop + CLI. O desktop é **single-process**: a
UI fala com um worker Dart (`Isolate`) que executa o core. Não existe daemon nem
porta HTTP; há apenas o socket de instância única (`127.0.0.1:47831`), que serve
para trazer a janela da instância existente à frente.

## Módulos

```text
app/ (Flutter)
  ├── UI (dashboard, compacto, settings)
  ├── TrayService (tray_manager + window_manager)
  └── LocalQuotaApi ──► worker Isolate ──► packages/core

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

- `TrayService` registra o ícone e o menu (Abrir mini, Dashboard completo,
  Personalizar painel, Detectar provedores, Configurações, Atualizar agora, Sair).
- Clique esquerdo alterna a janela mini (380×500).
- Dashboard completo abre em 1100×800; a janela inicial (não-mini) usa 420×760.
- Fechar a janela esconde para a bandeja (o runner do macOS não encerra o app);
  “Sair” encerra o processo.
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

### Backoff de 429

O próprio `cache.json` guarda `backoff: {provider: até}`. Quando um adapter
devolve `RATE_LIMITED`, o serviço grava 5 min (ou o `Retry-After` do endpoint) e
as próximas leituras devolvem o último snapshot bom marcado como `stale`, sem
chamar a rede. Refresh manual também respeita o bloqueio.

## Notificações

- `NotificationPolicy` decide o que notificar: um aviso por travessia, histerese
  de 5 pontos e re-arme quando o `resetsAt` muda mais de 90 min.
- `LocalNotificationService` entrega via `local_notifier` (Windows/macOS/Linux).
- Estado de dedupe em `notifications.json` no diretório de dados.
- Com a janela oculta, o timer continua rodando em intervalos de 5 min apenas
  quando as notificações estão ligadas.

## Personalização

`AppConfig` guarda `providerOrder` e `windowVisibility` (`provider|windowId` →
`always` / `onDemand` / `hidden`). O dashboard e o mini filtram as janelas; o
core continua consultando todas, inclusive as ocultas.

## Atualização

`UpdateService` consulta `releases/latest` no GitHub no start e a cada 24 h,
compara SemVer com `appVersion` e expõe um banner com link para a release. Não
baixa nem executa nada; pode ser desligado por `checkUpdates`.

## Erros

Cada provider pode falhar sem derrubar os outros. Os erros são tipados (`AUTH_MISSING`, `AUTH_EXPIRED`, `PERMISSION_DENIED`, `CREDENTIAL_UNREADABLE`, `NETWORK`, `RATE_LIMITED`, `SCHEMA_CHANGED`, `PROVIDER_NOT_RUNNING`) e aparecem no card com uma ação (“Abrir Claude Code”, “Tentar novamente” etc.). Em `RATE_LIMITED`, o card mostra a contagem até a próxima tentativa e esconde o botão “Tentar”.

## Decisões

- **Flutter** para uma única base de UI em macOS, Windows e Linux.
- **Desktop em um processo só, com worker** (isolate persistente) para tirar a
  coleta da UI sem adicionar daemon. A única porta é o socket de instância
  única em `127.0.0.1:47831`.
- **CLI no mesmo core** para scripts e statusline.
- **Sem refresh OAuth automático** para não rotacionar refresh token do usuário.
- **Read-only** em credenciais e endpoints de uso.

## Segurança

O desktop lê credenciais locais como a CLI. No macOS, o App Sandbox é desligado para acessar `~/.codex`, `~/.claude`, SQLite do OpenCode e o hub do Antigravity. Ver [`seguranca.md`](seguranca.md).
