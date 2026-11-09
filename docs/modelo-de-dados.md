# Modelo de dados

O modelo é o contrato entre providers, core, CLI, app Flutter, histórico e testes. Ele deve ser **estável**, **tolerante a campos novos** e **explícito sobre incerteza**.

Implementação real: `packages/models` (`quota_deck_models`). É Dart puro — sem `dart:io`, `sqlite3` ou Flutter — para ser importado pelo app e pela CLI.

---

## 1. Tipos (Dart)

```dart
enum ProviderId { opencode, antigravity, codex, claude }

enum WindowKind {
  rolling,
  session,
  weekly,
  monthly,
  model,
  credits,
  unknown,
}

enum QuotaStatus { ok, warning, critical, limited, unknown }

enum Confidence { high, medium, low, none }

enum SourceKind { api, rpc, appServer, cli, headers, log, cache }
```

Wire names:

| Enum | JSON |
|---|---|
| `ProviderId` | `opencode`, `antigravity`, `codex`, `claude` |
| `SourceKind.appServer` | `app-server` |
| `SourceKind.cli` | `cli` |
| `QuotaStatus` | `ok`, `warning`, `critical`, `limited`, `unknown` |

---

## 2. Snapshot

```dart
class ProviderSnapshot {
  final int schemaVersion;          // 1
  final ProviderId provider;
  final AccountInfo account;
  final List<QuotaWindow> windows;  // pode ser vazio em erro
  final CreditsInfo? credits;
  final String source;
  final DateTime fetchedAt;         // UTC
  final bool stale;
  final Confidence confidence;
  final List<QdeckErrorInfo> errors;
}

class AccountInfo {
  final String label;
  final String? plan;
  final String? maskedEmail;
}

class QuotaWindow {
  final String id;
  final String label;
  final WindowKind kind;
  final String? group;
  final double usedPercent;       // 0..100
  final double remainingPercent;  // 0..100
  final DateTime? resetsAt;       // UTC
  final QuotaStatus status;
  final SourceKind source;
}

class CreditsInfo {
  final bool hasCredits;
  final bool unlimited;
  final double? balance;
  final String? currency;
  final String? note;
}

class QdeckErrorInfo {
  final String code;
  final String message;
  final bool retryable;
  final Map<String, dynamic>? details;
}
```

### 2.1 Envelope

```dart
class SnapshotEnvelope {
  final int schemaVersion; // 1
  final DateTime generatedAt;
  final List<ProviderSnapshot> results;
  final List<QdeckErrorInfo> errors;
}
```

O envelope é o que o `LocalQuotaApi`/core retorna para a UI e o que a CLI serializa em `qdeck json`.

---

## 3. Contrato JSON

```json
{
  "schemaVersion": 1,
  "provider": "opencode",
  "account": {
    "label": "OpenCode Go",
    "plan": "Go",
    "maskedEmail": null
  },
  "windows": [
    {
      "id": "rolling",
      "label": "Rolling 5h",
      "kind": "rolling",
      "group": null,
      "usedPercent": 4.0,
      "remainingPercent": 96.0,
      "resetsAt": "2026-11-08T18:45:25Z",
      "status": "ok",
      "source": "api"
    }
  ],
  "credits": null,
  "source": "opencode-usage-api",
  "fetchedAt": "2026-11-08T15:00:00Z",
  "stale": false,
  "confidence": "medium",
  "errors": []
}
```

### 3.1 Parsing

`fromJson` deve:

- aceitar campos desconhecidos (ignorar);
- converter `usedPercent`/`remainingPercent` com `clampPercent`;
- converter `resetsAt`/`fetchedAt` com `parseDate` (ISO 8601, epoch segundos ou ms);
- omitir janelas com `null`/sem dados;
- manter `windows` vazio quando o provider falhou, com `errors` preenchido;
- nunca lançar por causa de um campo opcional.

`formatDate` sempre emite UTC ISO 8601 (`...Z`).

---

## 4. Regras de normalização

| Regra | Detalhe |
|---|---|
| Percentuais | 0–100, 1 casa decimal, clamp |
| `remainingPercent` | sempre `100 - usedPercent` |
| `status` | `ok` <80; `warning` >=80; `critical` >=95; `limited` >=100 ou flag |
| `resetsAt` | UTC; epoch s/ms convertido; `null` se ausente |
| `kind` | semântica da janela, não nome do provider |
| `group` | string exata da fonte (Antigravity) ou `null` |
| `source` | `api` HTTP interno; `rpc` language server/app-server; `cli` statusline; `headers`/`log` passivo |
| `confidence` | `high` RPC/app-server; `medium` HTTP interno; `low` header/log; `none` erro |
| `stale` | `true` somente se veio de cache após falha |
| `errors` | vazio em sucesso; erro global fica no envelope |

---

## 5. Histórico

SQLite em `history.db`:

```sql
CREATE TABLE snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  provider TEXT NOT NULL,
  window_id TEXT NOT NULL,
  used_percent REAL NOT NULL,
  fetched_at TEXT NOT NULL,
  stale INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_snapshots_provider_time
  ON snapshots(provider, fetched_at);
CREATE INDEX idx_snapshots_window_time
  ON snapshots(provider, window_id, fetched_at);
```

- Retenção: 30 dias (config).
- Amostragem: 5 min ou delta >= 1%.
- `stale` não é gravado por padrão.
- Export: **roadmap** (CSV `provider,window_id,used_percent,fetched_at`). Hoje há `qdeck history` em texto/JSON.

### 5.1 Burn rate

```dart
double burnRatePerHour(List<HistorySample> samples) {
  if (samples.length < 3) return 0;

  final pts = samples
      .where((s) => !s.stale)
      .map((s) => (
            x: s.fetchedAt.millisecondsSinceEpoch / 3600000.0,
            y: s.usedPercent,
          ))
      .toList();

  if (pts.length < 3) return 0;

  final n = pts.length.toDouble();
  final sx = pts.fold<double>(0, (a, p) => a + p.x);
  final sy = pts.fold<double>(0, (a, p) => a + p.y);
  final sxx = pts.fold<double>(0, (a, p) => a + p.x * p.x);
  final sxy = pts.fold<double>(0, (a, p) => a + p.x * p.y);
  final denom = n * sxx - sx * sx;
  if (denom.abs() < 1e-9) return 0;

  final slope = (n * sxy - sx * sy) / denom;
  if (slope.isNaN || slope.isInfinite) return 0;
  return slope < 0 ? 0 : slope;
}

double? etaHours(double usedPercent, double burnPerHour) {
  if (burnPerHour <= 0.01) return null;
  final eta = (100 - usedPercent) / burnPerHour;
  return eta.isFinite && eta >= 0 ? eta : null;
}
```

Implementação real: `packages/core/lib/src/history.dart`.

---

## 6. Config

```dart
class AppConfig {
  final int schemaVersion;          // 1
  final Map<String, bool> providers;
  final int refreshSeconds;         // default 60
  final int cacheTtlSeconds;        // default 60
  final bool historyEnabled;
  final int retentionDays;          // default 30
  final bool notificationsEnabled;
  final int warningThreshold;       // default 80
  final int criticalThreshold;      // default 95
  final int resetSoonMinutes;       // default 15
  final String theme;               // system|dark|light
  final bool launchAtLogin;
  final bool allowProbe;            // default false
  final bool allowOAuthRefresh;     // default false
}
```

Paths:

| SO | Data dir |
|---|---|
| macOS | `~/Library/Application Support/QuotaDeck` |
| Linux | `$XDG_DATA_HOME/quota-deck` ou `~/.local/share/quota-deck` |
| Windows | `%APPDATA%\QuotaDeck` |
| Override | `QDECK_DATA_DIR` |

Arquivos: `cache.json`, `history.db`, `config.json`, `session.json`, `quota-deck.log`.
Permissões: diretório `0700`; arquivos `0600` quando possível.

---

## 7. Migrações

- `schemaVersion` inteiro; migração sequencial.
- Schema mais novo que o app: **roadmap** (modo somente leitura + aviso); hoje o parse é tolerante e cai no default.
- Mudança de provider: normalizar no adapter; manter o modelo estável.
- Fixtures versionadas por `schemaVersion`.

---

## 8. Contratos de teste

- `ProviderSnapshot.fromJson(snapshot.toJson())` preserva campos.
- `remainingPercent == 100 - usedPercent` (tolerância 0.1).
- `status` consistente com `usedPercent`, exceto quando a API manda `limited`.
- `resetsAt` parseável ou `null`.
- Nenhum campo com token/segredo.
- JSON serializável e estável.

Fixtures: `docs/pesquisa/fixtures/` e `packages/core/test/fixtures/`.
