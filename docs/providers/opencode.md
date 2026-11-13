# Provider: OpenCode Go

**Status:** validado em 08/11/2026 no macOS, OpenCode Desktop 2.2.6.
**Confiança:** alta (endpoint interno estável + credencial local).
**Custo de quota:** zero (endpoint de leitura de uso).

---

> **Implementado hoje:** SQLite `credential` em modo somente leitura (caminho
> `XDG_DATA_HOME`/`~/.local/share/opencode/opencode.db`, com override
> `QDECK_OPENCODE_DB`), integração `opencode-go`/`opencode`. Os fallbacks
> `auth.json` e `OPENCODE_API_KEY` descritos abaixo **não** estão implementados.

## 1. Onde está a credencial

O OpenCode 2.x guarda credenciais no SQLite do servidor local:

```text
~/.local/share/opencode/opencode.db
```

Respeitar `XDG_DATA_HOME` e `OPENCODE_DB`. Para imprimir o caminho oficial:

```bash
opencode debug paths db
```

### 1.1 Tabela `credential`

| Coluna | Exemplo | Observação |
|---|---|---|
| `id` | `cred_...` | id interno |
| `integration_id` | `opencode-go` / `opencode` | filtro |
| `label` | `OpenCode Go` | exibição |
| `value` | JSON | credencial |
| `active` | `1` | boolean |

Formatos de `value`:

```json
{"type":"key","key":"oc_sk_..."}
```

```json
{
  "type": "oauth",
  "methodID": "device",
  "refresh": "rt_...",
  "access": "st_...",
  "expires": 1793948786727,
  "metadata": { "orgID": "wrk_...", "orgName": "..." }
}
```

```json
{"type":"external","methodID":"...","metadata":{}}
```

- `opencode-go` é usado para API key do Go (inclusive importada do `auth.json` legado).
- `opencode` é usado pelo login OAuth do Console.
- **Não assuma um único ID**: consultar ambos e priorizar `active=1`.
- O prefixo observado de chaves novas é `oc_sk_...`; chaves antigas podiam ser `sk-...`. Não validar por prefixo.
- Leitura segura:

```bash
sqlite3 "file:$HOME/.local/share/opencode/opencode.db?mode=ro" \
  "SELECT integration_id, label, active, json_extract(value,'$.type') AS type
     FROM credential;"
```

- A documentação oficial diz para **não editar o banco** para gerenciar credenciais; usar `/connect` ou comandos `auth`.
- O banco é um secret store: abrir `mode=ro`, não logar `value`, não copiar.

### 1.2 Versões antigas

Algumas versões usam `~/.local/share/opencode/auth.json` ou `~/.config/opencode/auth.json` com um mapa de providers. O adapter deve tentar, nesta ordem:

1. SQLite `credential` (`integration_id` = `opencode-go` ou `opencode`, `active=1`);
2. `auth.json` (`opencode-go` / `opencode`);
3. variável `OPENCODE_API_KEY` (opt-in, para CI/testes).

> **Estado atual:** apenas o item 1 existe no código (`packages/core/lib/src/providers/opencode.dart`).

---

## 2. Endpoint

```http
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <key>
Accept: application/json
```

Para OAuth/Console, o cliente oficial também envia:

```http
x-opencode-org-id: <wrk_...>
```

Testado com sucesso: HTTP 200.

### 2.1 Resposta real (fixture)

```json
{
  "usage": {
    "rolling": {
      "status": "ok",
      "percent": 2,
      "resetsAt": "2026-11-08T18:45:25.000Z"
    },
    "weekly": {
      "status": "ok",
      "percent": 20,
      "resetsAt": "2026-11-09T00:00:00.000Z"
    },
    "monthly": {
      "status": "ok",
      "percent": 16,
      "resetsAt": "2026-11-21T12:59:42.000Z"
    }
  }
}
```

Fixture: [`../../packages/core/test/fixtures/opencode-go-usage.json`](../../packages/core/test/fixtures/opencode-go-usage.json).

### 2.2 Semântica

- `rolling` = janela de 5h; `weekly` = semanal; `monthly` = 30 dias.
- `percent` é **usado** (0–100), não restante.
- `status`: `ok` ou `rate-limited`.
- `resetsAt` é ISO 8601.
- Limites oficiais do Go: 5h = 20% do mensal; weekly = 50%; monthly = 100%.
- `403` indica workspace sem assinatura Go; tratar como “sem allowance”, não retry.
- `?group=model` e outros parâmetros não mudam a resposta; não há endpoint de histórico.
- A mesma API key serve Go e Zen; o endpoint é específico de Go.

---

## 3. API local experimental (alternativa)

O servidor local do OpenCode expõe:

```http
GET /api/experimental/usage/limits
```

Resposta:

```json
{
  "workspace": {},
  "go": {
    "rolling": { "percent": 2, "limited": false, "resetsAt": 1794163949000 },
    "weekly":  { "percent": 20, "limited": false, "resetsAt": 1794182400000 },
    "monthly": { "percent": 16, "limited": false, "resetsAt": 1795265982000 }
  },
  "budgets": {}
}
```

- `resetsAt` em **milissegundos** Unix (diferente do endpoint HTTP, que usa ISO).
- Retorna `null` se não houver Console assinado.
- É explicitamente experimental; usar como alternativa, não como única fonte.
- Exige auth do servidor local.

---

## 4. Normalização

| Campo da API | `id` normalizado | `label` | `kind` |
|---|---|---|---|
| `rolling` | `rolling-5h` | Rolling 5h | `rolling` |
| `weekly` | `weekly` | Semanal (7d) | `weekly` |
| `monthly` | `monthly` | Mensal (30d) | `monthly` |

- `percent` é usado; `remaining = 100 - percent`.
- `status` da API tem prioridade sobre o threshold local.
- Se `percent` vier ausente, marcar `unknown` e confidence `low`; não inventar zero.
- `limited: true` (API local) → `status: limited`.

---

## 5. Pseudocódigo do adapter

```ts
async function readOpenCode(ctx: ProviderContext): Promise<ProviderSnapshot> {
  const db = findOpenCodeDb(ctx.platform); // opencode debug paths db
  const cred = readOpenCodeCredential(db); // read-only, sem log
  if (!cred) throw new AuthMissing("OpenCode Go não autenticado");

  const headers: Record<string, string> = {
    Authorization: `Bearer ${cred.token}`,
  };
  if (cred.orgId) headers["x-opencode-org-id"] = cred.orgId;

  const res = await ctx.http.get("https://opencode.ai/zen/go/v1/usage", {
    headers,
    timeoutMs: 20_000,
  });

  const parsed = OpenCodeUsageSchema.parse(res.json);
  return normalizeOpenCode(parsed, { fetchedAt: ctx.now() });
}
```

---

## 6. Erros e fallback

| Situação | Código | Ação |
|---|---|---|
| DB não existe | `AUTH_MISSING` | “OpenCode não encontrado” |
| Credencial ausente | `AUTH_MISSING` | “Faça login no OpenCode Go” |
| 401 | `AUTH_EXPIRED` | “Reautentique no OpenCode” |
| 403 | `AUTH_MISSING` | “Sem assinatura Go” |
| 429 | `RATE_LIMITED` | Backoff + cache |
| 5xx/timeout | `NETWORK` | Cache stale |
| JSON sem `usage` | `SCHEMA_CHANGED` | Cache + issue com diagnóstico |

Cache TTL: 60 s. Em falha, usar último snapshot até 24 h, `stale: true`.

---

## 7. Segurança

- Abrir o SQLite com `mode=ro`; nunca escrever.
- Não copiar a chave para cache, config, histórico ou logs.
- Redaction: padrão `oc_[A-Za-z0-9_-]+`, `sk-[A-Za-z0-9_-]+`, campos `key|token|secret`.
- Em `doctor`, mostrar apenas `key presente: sim/não`, `type` e `len`.
- Não segurar locks; leitura curta.

---

## 8. Testes

- Fixture de sucesso (acima).
- Fixture com `rate-limited`.
- Fixture com campo novo (deve ignorar).
- Fixture sem `monthly` (deve normalizar os outros).
- Fixture de credencial `oauth` (`.access` + `metadata.orgID`).
- Fixture de credencial `key` (`.key`).
- Teste de 403.
- Teste de segurança: saída JSON não contém `oc_`/`sk-`.
- Integração opt-in: `QDECK_INTEGRATION=1` lê a credencial real.

---

## 9. Referências

- Plugins da comunidade: `@slkiser/opencode-quota`, `@npv12/opencode-quota`, `@leo000001/opencode-quota-sidebar`, `@whosydd/opencode-quota`.
- Documentação: [OpenCode Go](https://opencode.ai/v2/docs/console/go/), [API](https://opencode.ai/v2/docs/api), [Providers/Storage](https://opencode.ai/docs/cli/providers/#storage).
- Endpoint descoberto por engenharia reversa; não é API pública documentada.
