# Provider: Claude Code (Anthropic)

**Status:** schema e tratamento implementados; token local expirado em 08/11/2026 (HTTP 401).
**Confiança:** alta no endpoint OAuth; média em headers passivos.
**Custo de quota:** zero no endpoint de uso; probe mínima só com opt-in.

---

## 1. Onde está a credencial

### macOS

Keychain, serviço `Claude Code-credentials`:

```bash
security find-generic-password -s "Claude Code-credentials" -w
```

O valor é JSON:

```json
{
  "claudeAiOauth": {
    "accessToken": "<token>",
    "refreshToken": "<token>",
    "expiresAt": 1782791603444,
    "scopes": ["user:inference", "user:profile", "..."],
    "subscriptionType": "pro",
    "rateLimitTier": "..."
  }
}
```

- `expiresAt` é epoch **milissegundos**.
- `subscriptionType` é `pro`, `max`, etc.
- No ambiente de validação, `expiresAt` já havia passado → 401.

### Linux/Windows

```text
~/.claude/.credentials.json
```

Mesma estrutura `claudeAiOauth`.

Com `CLAUDE_CONFIG_DIR` customizado, o serviço do Keychain vira `Claude Code-credentials-<hash>` e o arquivo fica em `<CLAUDE_CONFIG_DIR>/.credentials.json`. Buscar pelo serviço (sem account fixo) é mais robusto.

---

## 2. Fonte preferida quando integrado: statusline oficial

O Claude Code documenta o payload de statusline com `rate_limits`:

```json
{
  "rate_limits": {
    "five_hour": { "used_percentage": 12.0, "resets_at": 1794163949 },
    "seven_day": { "used_percentage": 40.0, "resets_at": 1794517920 }
  }
}
```

- `used_percentage` é 0–100.
- `resets_at` é epoch **segundos**.
- Só aparece para assinantes Pro/Max/Ultra, após a primeira resposta da API.
- Não faz rede e não usa token.

Se o QuotaDeck for usado como statusline do Claude Code, essa é a fonte mais barata e estável. Para o app standalone, usar o endpoint OAuth abaixo.

---

## 3. Endpoint OAuth de uso

```http
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
Accept: application/json
```

Resposta esperada (schema observado, não oficial):

```json
{
  "five_hour": {
    "utilization": 12.0,
    "resets_at": "2026-11-08T18:00:00.123456+00:00"
  },
  "seven_day": {
    "utilization": 40.0,
    "resets_at": "2026-11-15T12:00:00+00:00"
  },
  "seven_day_oauth_apps": null,
  "seven_day_sonnet": {
    "utilization": 25.0,
    "resets_at": "2026-11-15T12:00:00+00:00"
  },
  "seven_day_opus": null,
  "extra_usage": {
    "is_enabled": true,
    "monthly_limit": 100.0,
    "used_credits": 12.5,
    "utilization": 12.5
  }
}
```

- `utilization` é usado (0–100).
- `resets_at` é RFC 3339 com offset (às vezes microssegundos); parsear com biblioteca robusta.
- Qualquer bucket pode ser `null` ou ausente; não tratar ausência como erro.
- `seven_day_oauth_apps`, `seven_day_cowork` e chaves internas podem aparecer; ignorar desconhecidas.
- `extra_usage` é crédito pay-as-you-go; mapear para `credits` quando presente.
- O header `anthropic-beta: oauth-2025-04-20` é obrigatório na prática; sem ele, 401.

---

## 4. Normalização

| Campo | `id` | `label` | `kind` |
|---|---|---|---|
| `five_hour` | `five-hour` | 5 horas | `session` |
| `seven_day` | `seven-day` | Semanal (7d) | `weekly` |
| `seven_day_sonnet` | `seven-day-sonnet` | Semanal Sonnet | `model` |
| `seven_day_opus` | `seven-day-opus` | Semanal Opus | `model` |

- `usedPercent = utilization`.
- `status`: `ok` <80, `warning` >=80, `critical` >=95, `limited` >=100.
- `subscriptionType` vai para `account.plan`.
- `extra_usage` vira `credits` (`hasCredits`, `balance = monthly_limit - used_credits`, `note = utilization`).
- Buckets `null` são omitidos; não criar janela com 0%.

---

## 5. Token expirado e refresh

### Comportamento padrão

1. Ler `expiresAt`.
2. Se `expiresAt < now`, retornar `AUTH_EXPIRED` **sem chamar a rede**.
3. Mensagem: “Token do Claude expirado; abra o Claude Code para renovar.”
4. Usar cache stale se existir.

### Por que não renovar automaticamente

O refresh token pode rotacionar. Se o QuotaDeck renovar e não persistir o novo token corretamente, o Claude Code do usuário pode ser deslogado. O risco não compensa no fluxo padrão.

### Se você for implementar

Se implementar:

- usar o client_id público do Claude Code: `9d1c250a-e61b-44d9-88ed-5944d1962f5e`;
- `POST https://platform.claude.com/v1/oauth/token` com `Content-Type: application/json` e body `{"grant_type":"refresh_token","refresh_token":"...","client_id":"..."}`;
- assumir que cada refresh **rotaciona** o refresh token e invalida o anterior;
- persistir o novo par atomicamente no Keychain/arquivo;
- coordenar para não rodar em paralelo com o Claude Code;
- detectar falha e orientar novo login.

O `expires_in` observado é ~28800 s (8h). O endpoint `console.anthropic.com/v1/oauth/token` aparece em fontes antigas; o atual observado é `platform.claude.com`.

---

## 6. Headers passivos (alternativa)

As respostas da API da Anthropic trazem headers de limite unificado:

```text
anthropic-ratelimit-unified-5h-utilization
anthropic-ratelimit-unified-5h-reset
anthropic-ratelimit-unified-5h-status
anthropic-ratelimit-unified-7d-utilization
anthropic-ratelimit-unified-7d-reset
anthropic-ratelimit-unified-7d-status
anthropic-ratelimit-unified-7d_sonnet-utilization
anthropic-ratelimit-unified-status
anthropic-ratelimit-unified-reset
anthropic-ratelimit-unified-representative-claim
anthropic-ratelimit-unified-fallback-percentage
anthropic-ratelimit-unified-overage-status
```

**Unidades:** headers usam fração 0–1; multiplique por 100. Resets são epoch segundos. O JSON do endpoint usa 0–100 e RFC 3339. Não misture.

**Status:** os valores observados (`allowed`, `active`, `warning`, `rate_limited`, `exceeded`) não são um enum oficial; não construa máquina de estados crítica sobre eles. `representative-claim` indica a janela gargalo, mas trate como dica.

Estratégia:

- ler headers de respostas recentes do Claude Code (log/proxy local);
- ou um proxy local opt-in que só observa headers;
- nunca fazer proxy de conteúdo por padrão.

### Probe mínima (opt-in)

Se não houver tráfego recente, uma chamada barata com modelo Haiku e `max_tokens: 1` retorna headers. Só com `--probe` explícito, com aviso de consumo e rate limit. **Desligado por padrão.**

---

## 7. Erros e fallback

| Situação | Código | Ação |
|---|---|---|
| Keychain sem item | `AUTH_MISSING` | “Claude Code não autenticado” |
| Keychain negado | `PERMISSION_DENIED` | Instruções de permissão |
| `expiresAt` no passado | `AUTH_EXPIRED` | Abrir Claude Code |
| 401 | `AUTH_EXPIRED` | Abrir Claude Code |
| 429 | `RATE_LIMITED` | Backoff + cache |
| Sem janelas | `SCHEMA_CHANGED` | Cache + issue |

Cache TTL: 60 s. Endpoint OAuth tem rate limit próprio; não martelar.

---

## 8. Segurança

- Nunca imprimir o JSON do Keychain.
- Redaction: `sk-ant-`, `eyJ`, `Bearer`, `refreshToken`, `accessToken`.
- No macOS, o acesso ao Keychain pode exigir autorização do usuário; tratar negação.
- Não persistir tokens; ler em memória e descartar.
- `doctor` mostra `expiresAt` (data), `subscriptionType` e presença — nunca token.
- Buscar o item do Keychain pelo serviço, não por account fixo.
- Se `CLAUDE_CONFIG_DIR` existir, usar o serviço/arquivo correspondente.

---

## 9. Testes

- Fixture sintética com as 4 janelas.
- Fixture sem `seven_day_opus`.
- Teste de `expiresAt` no passado (não deve chamar rede).
- Teste de 401.
- Teste de Keychain negado (mock).
- Integração opt-in com token válido.
- Teste de bucket `null` e de `extra_usage`.
- Teste de `resets_at` com microssegundos/offset.

---

## 10. Referências

- `ccusage`, `cc-usage-cli`, `claude-limits-bar`, `claude-spillway`, `claude-limit-statusline`, `claude-code-statusline`.
- Statusline oficial: `rate_limits` no stdin, `used_percentage` 0–100, `resets_at` epoch.
- Endpoint OAuth interno; não é API pública documentada.
- Refresh: `platform.claude.com/v1/oauth/token`, client_id público, rotação de refresh token.
