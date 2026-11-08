# Provider: Codex (OpenAI)

**Status:** endpoint validado em 08/11/2026 no macOS; `app-server` documentado e recomendado.
**Confiança:** alta no `app-server` (documentado); média no `wham/usage` (rota interna).
**Custo de quota:** zero em ambos (leitura de uso).

---

## 1. Onde está a credencial

```text
$CODEX_HOME/auth.json   # padrão: ~/.codex/auth.json
```

Estrutura (sem valores):

```json
{
  "auth_mode": "chatgpt",
  "OPENAI_API_KEY": null,
  "last_refresh": "2026-11-08T12:00:00Z",
  "tokens": {
    "access_token": "<jwt>",
    "access_token_expires_at": 1794163949,
    "account_id": "<uuid>",
    "id_token": "<jwt>",
    "refresh_token": "<opaque>"
  }
}
```

- `auth_mode`: `chatgpt`, `apikey` ou `chatgptAuthTokens`.
- `tokens.access_token` é o Bearer.
- `tokens.account_id` é o header `ChatGPT-Account-Id` (case-insensitive).
- `last_refresh` ajuda o `doctor`.
- O armazenamento é configurável por `cli_auth_credentials_store`: `file`, `keyring`, `auto` ou `ephemeral`. Em `keyring`/`auto`, o `auth.json` pode não existir.
- `OPENAI_API_KEY` não é o access token do ChatGPT; se `auth_mode=apikey`, os limites de assinatura não estão disponíveis.

---

## 2. Fonte primária: `codex app-server`

O app-server é a superfície **documentada** e mantém o OAuth dentro do Codex. Fala JSON-RPC 2.0 sobre stdio (newline-delimited JSON; o campo `"jsonrpc":"2.0"` é omitido no wire).

### 2.1 Handshake

```json
{"method":"initialize","id":0,"params":{"clientInfo":{"name":"quotadeck","title":"QuotaDeck","version":"0.1.0"}}}
{"method":"initialized","params":{}}
{"method":"account/rateLimits/read","id":1}
```

- `initialize` é obrigatório.
- `initialized` é uma notificação (sem `id`).
- `account/rateLimits/read` retorna os limites da conta ChatGPT.

### 2.2 Resposta

```json
{
  "id": 1,
  "result": {
    "rateLimits": {
      "limitId": "codex",
      "limitName": null,
      "primary": {
        "usedPercent": 25,
        "windowDurationMins": 300,
        "resetsAt": 1730947200
      },
      "secondary": {
        "usedPercent": 62,
        "windowDurationMins": 10080,
        "resetsAt": 1731552000
      },
      "rateLimitReachedType": null
    },
    "rateLimitsByLimitId": {
      "codex": { "...": "mesma estrutura" }
    },
    "rateLimitResetCredits": {
      "availableCount": 2,
      "credits": null
    }
  }
}
```

Campos:

| Campo | Significado | Unidade |
|---|---|---|
| `usedPercent` | uso da janela (não restante) | 0–100 |
| `windowDurationMins` | duração da janela | minutos |
| `resetsAt` | próximo reset | Unix **segundos** |
| `planType` | plano ChatGPT, quando presente | string |
| `rateLimitReachedType` | estado de limite atingido | enum/string |
| `rateLimitResetCredits.availableCount` | resets ganhos disponíveis | inteiro |

Notas:

- `rateLimits` é a visão single-bucket retrocompatível; `rateLimitsByLimitId` é multi-bucket (ex.: `codex`, `codex_other`). Preferir `codex` quando existir.
- `rateLimitResetCredits.credits` pode ser `null`; `availableCount` é autoritativo.
- `account/rateLimits/updated` é notificação esparsa; refazer `read` periodicamente.
- Para forçar renovação, usar `account/read` com `{"refreshToken": true}` em vez de manipular `auth.json`.
- Gerar o schema da versão instalada:

```bash
codex app-server generate-json-schema --out ./schemas
```

Isso vira fixture de contrato no CI.

### 2.3 Quando usar

- Se o binário `codex` existir e o `app-server` iniciar em <5 s.
- Se o `auth.json` estiver em `keyring`/`auto` (o app-server resolve o auth).
- Se o usuário quiser o caminho mais estável.

Fallback: endpoint `wham/usage` (abaixo) quando o app-server não estiver disponível.

### 2.4 Ciclo de vida do processo

1. Detectar o binário (`which codex` / `codex --version`).
2. `spawn("codex", ["app-server"], { stdio: ["pipe","pipe","pipe"] })` sem shell.
3. Escrever `initialize` + `initialized` + `account/rateLimits/read` (newline-delimited JSON).
4. Ler a resposta com timeout de 5 s; se não vier, matar o processo e cair no endpoint.
5. Matar o processo ao final (ou manter vivo com idle timeout de 60 s).
6. Redigir stderr; nunca logar o payload bruto se contiver token.
7. Se `codex` não existir ou a versão não suportar `app-server`, usar o fallback sem erro visível.

---

## 3. Fallback: `GET /backend-api/wham/usage`

Rota interna usada pelo Codex CLI; **não documentada** como API pública.

```http
GET https://chatgpt.com/backend-api/wham/usage
Authorization: Bearer <access_token>
ChatGPT-Account-Id: <account_id>
User-Agent: codex-cli
Accept: application/json
```

Testado com sucesso: HTTP 200.

### 3.1 Resposta real (resumida, anonimizada)

```json
{
  "user_id": "<redacted>",
  "account_id": "<redacted>",
  "email": "<redacted>",
  "plan_type": "plus",
  "rate_limit": {
    "allowed": true,
    "limit_reached": false,
    "primary_window": {
      "used_percent": 0,
      "limit_window_seconds": 18000,
      "reset_after_seconds": 18000,
      "reset_at": 1794163949
    },
    "secondary_window": {
      "used_percent": 2,
      "limit_window_seconds": 604800,
      "reset_after_seconds": 371972,
      "reset_at": 1794517920
    }
  },
  "credits": {
    "has_credits": false,
    "unlimited": false,
    "overage_limit_reached": false,
    "balance": "0"
  },
  "rate_limit_reset_credits": {
    "available_count": 2,
    "applicable_available_count": 0
  }
}
```

Fixture: [`../../packages/core/test/fixtures/codex-wham-usage.json`](../../packages/core/test/fixtures/codex-wham-usage.json).

### 3.2 Caveats

- `primary_window` **não é sempre 5h**; use `limit_window_seconds` para rotular.
- `secondary_window` pode ser `null`.
- `used_percent` pode passar de 100 em casos de borda; clamp.
- `reset_at` é epoch **segundos**; `reset_after_seconds` é relativo.
- `allowed: false` bloqueia independentemente do percentual.
- `plan_type` é enum aberto (`free`, `plus`, `pro`, `team`, `enterprise`, Go, Business, Edu...).
- `additional_rate_limits` e `code_review_rate_limit` podem existir.
- O CLI faz polling dessa rota a cada ~60 s durante sessões ativas.

---

## 4. Normalização

| Origem | `id` | `label` | `kind` |
|---|---|---|---|
| `primary` (300 min) | `primary-5h` | 5 horas | `session` |
| `secondary` (10080 min) | `secondary-7d` | Semanal (7d) | `weekly` |

- Derivar `id`/`label` de `windowDurationMins`/`limit_window_seconds`, não da posição.
- `usedPercent` direto; `remaining = 100 - used`.
- `resetsAt` epoch segundos → ISO UTC.
- `rateLimitReachedType != null` ou `limit_reached: true` → `status: limited`.
- `rateLimitResetCredits.availableCount` vai para `credits.note` (“2 resets disponíveis”).
- `credits.balance` pode ser string; converter para número quando possível.

---

## 5. Token e refresh

- O Codex CLI renova o token sozinho. O QuotaDeck **não** deve rotacionar `refresh_token`.
- A documentação de CI/CD diz explicitamente para não chamar a API de refresh por conta própria; deixe o Codex renovar.
- Se o endpoint retornar 401:
  1. marcar `AUTH_EXPIRED`;
  2. orientar “abra o Codex e faça login novamente”;
  3. usar cache stale se existir.
- Se for absolutamente necessário renovar (opt-in):
  - `POST https://auth.openai.com/oauth/token` com `Content-Type: application/json`;
  - body `{"client_id":"app_EMoamEEZ73f0CkXaXp7hrann","grant_type":"refresh_token","refresh_token":"..."}`;
  - assumir rotação; persistir atomicamente; lock entre processos;
  - no máximo 1 refresh + 1 retry.
- Nunca logar `access_token`, `id_token` ou `refresh_token` (JWT tem 3 partes; redaction por `eyJ`).

---

## 6. Erros e fallback

| Situação | Código | Ação |
|---|---|---|
| `auth.json` ausente e keyring indisponível | `AUTH_MISSING` | “Codex não autenticado” |
| `auth_mode=apikey` | `AUTH_MISSING` | “Use login ChatGPT para ver limites” |
| `codex` não instalado | — | Usar `wham/usage` |
| app-server não inicia | `PROVIDER_NOT_RUNNING` | Fallback endpoint |
| 401 | `AUTH_EXPIRED` | Reabrir Codex |
| 429 | `RATE_LIMITED` | Backoff + cache |
| 5xx/timeout | `NETWORK` | Cache stale |
| Sem `rate_limit`/`rateLimits` | `SCHEMA_CHANGED` | Cache + issue |

---

## 7. Segurança

- Ler `auth.json` com permissão do usuário; não copiar.
- Redaction: `eyJ...` (JWT), `Bearer`, campos `token|account_id`.
- Não enviar `account_id` para lugar nenhum além do header exigido.
- `doctor` mostra `auth_mode`, `last_refresh`, storage e presença de tokens — nunca valores.
- Preferir `app-server` para não manipular o token.

---

## 8. Testes

- Fixture real anonimizada do `wham/usage`.
- Fixture do `app-server` (schema gerado).
- Teste de `limit_reached: true`.
- Teste de janela ausente/`null`.
- Teste de `primary` com duração diferente de 5h.
- Teste de `used_percent > 100`.
- Teste de epoch segundos vs ms.
- Teste de 401 e de app-server indisponível.
- Mock HTTP/MSW + mock JSON-RPC.
- Integração opt-in.

---

## 9. Referências

- Documentação oficial: [Codex App Server](https://learn.chatgpt.com/docs/app-server), [Codex auth](https://developers.openai.com/codex/auth), [CI/CD auth](https://learn.chatgpt.com/docs/auth/ci-cd-auth).
- `codex-cli-usage` (app-server + fallback wham; sem licença declarada).
- `codex-statusline` (statusline local; não lê auth).
- `wham/usage` é rota interna; não é API pública documentada.
