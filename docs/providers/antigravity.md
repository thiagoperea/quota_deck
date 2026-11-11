# Provider: Antigravity

**Status:** validado em 08/11/2026 no macOS, Antigravity 2.29.0.
**Confiança:** alta quando o app está aberto (RPC local ou statusline oficial); média no fallback OAuth direto.
**Custo de quota:** zero no statusline oficial e no RPC local.

---

## 1. Arquitetura do Antigravity

O Antigravity é um app Electron com um processo auxiliar Go: `language_server`.

```text
Antigravity.app (Electron)
  ├── renderer (UI)
  ├── main process
  └── Resources/bin/language_server
        ├── HTTP/HTTPS local (Connect/gRPC-Web)
        ├── fala com daily-cloudcode-pa.googleapis.com
        └── usa OAuth do usuário
```

O `language_server` expõe métodos protobuf/Connect, incluindo:

- `RetrieveUserQuotaSummary` — quota por grupo/janela (fonte local).
- `GetUserStatus` — nome, e-mail, plano, créditos.
- `GetLoadCodeAssist` — tier/onboarding.
- `GetProfileData`, `GetAvailableModels`, `GetModelStatuses` etc.

O app inicia o processo com flags visíveis em `ps`:

```text
language_server --standalone --override_ide_name antigravity \
  --subclient_type hub --override_ide_version 2.29.0 \
  --https_server_port 0 --csrf_token <uuid> \
  --app_data_dir antigravity \
  --api_server_url https://generativelanguage.googleapis.com \
  --cloud_code_endpoint https://daily-cloudcode-pa.googleapis.com \
  --host_bridge_url=http://127.0.0.1:49193 \
  --host_bridge_token <token>
```

As portas são aleatórias. O app grava os dados de descoberta em:

```text
~/.gemini/antigravity/daemon/hub_<httpPort>.json
```

Exemplo:

```json
{
  "pid": 941,
  "httpsPort": 49194,
  "httpPort": 49195,
  "lsVersion": "2.29.0",
  "csrfToken": "<uuid>"
}
```

---

## 2. Prioridade de fontes

| Prioridade | Fonte | Quando usar | Risco |
|---|---|---|---|
| 1 | Statusline oficial do CLI (`agy -p /usage --output-format json` ou payload `quota`) | CLI instalado; menor risco de ToS | baixo |
| 2 | RPC local do `language_server`/hub | app/IDE aberto; tempo real | baixo/médio |
| 3 | Endpoint `daily-cloudcode-pa` com OAuth | app fechado; fallback explícito | alto (ToS + fragilidade) |

**Decisão do QuotaDeck:** usar 1 quando disponível, 2 como padrão no desktop, 3 apenas com flag explícita.

### 2.1 Statusline oficial (fonte de menor risco)

O CLI do Antigravity documenta um objeto `quota` no payload do statusline:

```json
"quota": {
  "gemini-weekly": {
    "remaining_fraction": 0.9378,
    "reset_time": "2026-07-06T07:50:32Z",
    "reset_in_seconds": 560580
  }
}
```

Campos: `remaining_fraction` ou `remaining_amount`, `reset_time`, `reset_in_seconds`, `disabled`.

Também existe o comando:

```bash
agy -p /usage --output-format json
```

Ele não inicia turno e não consome quota (segundo a documentação/comunidade), mas pode levar ~7 s. O QuotaDeck deve:

- detectar o binário `agy` no PATH, em `~/.gemini/bin/agy` e no bundle do app;
- executar com timeout de 15 s;
- parsear `quota` e normalizar;
- cachear por 60 s;
- usar o RPC local se o CLI não existir.

**Vantagem:** é o caminho mais defensável em relação ao ToS, porque o dado é produzido pelo próprio CLI.

---

## 3. Fonte local: RPC do `language_server`

### 3.1 Descoberta

1. Ler `~/.gemini/antigravity/daemon/hub_*.json` (o mais recente).
2. Verificar se `pid` está vivo (`kill(pid, 0)`).
3. Usar `httpPort` (preferido) ou `httpsPort` (self-signed).
4. Usar `csrfToken` no header `x-codeium-csrf-token`.

### 3.2 Chamada

```http
POST http://127.0.0.1:<httpPort>/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary
Content-Type: application/json
Connect-Protocol-Version: 1
x-codeium-csrf-token: <csrfToken>

{}
```

Funciona também em `https://127.0.0.1:<httpsPort>` com certificado self-signed (aceitar apenas localhost).

### 3.3 Resposta real (resumida)

```json
{
  "response": {
    "groups": [
      {
        "displayName": "Gemini Models",
        "description": "Models within this group: Gemini Flash, Gemini Pro",
        "buckets": [
          {
            "bucketId": "gemini-weekly",
            "displayName": "Weekly Limit Remaining",
            "window": "weekly",
            "remainingFraction": 0.95808464,
            "resetTime": "2026-11-15T12:23:20Z"
          },
          {
            "bucketId": "gemini-5h",
            "displayName": "Five Hour Limit Remaining",
            "window": "5h",
            "remainingFraction": 0.88162965,
            "resetTime": "2026-11-08T17:23:20Z"
          }
        ]
      },
      {
        "displayName": "Claude and GPT models",
        "buckets": [
          { "bucketId": "3p-weekly", "window": "weekly", "remainingFraction": 1, "resetTime": "2026-11-15T13:49:33Z" },
          { "bucketId": "3p-5h", "window": "5h", "remainingFraction": 1, "resetTime": "2026-11-08T18:49:33Z" }
        ]
      },
      {
        "displayName": "Gemini 4 Argon",
        "buckets": [
          { "bucketId": "gemini-argon-wtu-weekly", "window": "weekly", "remainingFraction": 1, "resetTime": "2026-11-15T13:49:33Z" }
        ]
      }
    ],
    "description": "Within each group, models share a weekly limit and a 5-hour limit..."
  }
}
```

Fixture: [`../../packages/core/test/fixtures/antigravity-quota-summary.json`](../../packages/core/test/fixtures/antigravity-quota-summary.json).

### 3.4 Normalização

| Campo | Regra |
|---|---|
| `usedPercent` | `(1 - remainingFraction) * 100`, clamp 0–100 |
| `remainingPercent` | `remainingFraction * 100` |
| `id` | `bucketId` |
| `label` | `displayName` traduzido ou `window` |
| `kind` | `5h` → `session`; `weekly` → `weekly` |
| `group` | `displayName` do grupo |
| `resetsAt` | `resetTime` (ISO UTC) |

Exemplo: `remainingFraction: 0.88162965` → `usedPercent: 11.8`, `remaining: 88.2`.

**Variações observadas:** `remaining.remainingFraction` aninhado, oneof `remaining: {"case":"remainingFraction","value":0.87}`, `resetTime` como epoch, e buckets com `disabled: true` (ignorar). O parser deve aceitar as três formas de `remainingFraction`.

### 3.5 Plano e créditos (opcional)

`GetUserStatus` retorna:

```json
{
  "userStatus": {
    "name": "...",
    "email": "...",
    "planStatus": {
      "planInfo": {
        "planName": "Pro",
        "teamsTier": "TEAMS_TIER_PRO",
        "monthlyPromptCredits": 50000,
        "monthlyFlowCredits": 150000
      },
      "availablePromptCredits": 500,
      "availableFlowCredits": 100
    }
  }
}
```

Usar apenas para exibir plano/créditos; **mascarar e-mail** e nunca logar nome/e-mail.

---

## 4. Fonte de fallback: OAuth direto

Quando o app está fechado, é possível consultar o endpoint do Cloud Code diretamente:

```http
POST https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary
Authorization: Bearer <access_token>
Content-Type: application/json
User-Agent: antigravity/hub/2.29.0 (aidev_client; os_type=darwin; arch=arm64)

{"project":"aicode-consumers"}
```

- `daily` reflete o consumo consumer; `cloudcode-pa` pode devolver buckets em 100%. Consultar `daily` primeiro.
- O `User-Agent` com `antigravity/hub/2.x` é funcional para liberar o grupo Gemini; `1.0.0` pode omitir o grupo.
- O body pode exigir `{"project":"aicode-consumers"}` ou o project id retornado por `loadCodeAssist`.
- Com token expirado, retorna 401 `UNAUTHENTICATED` (validado).

### 4.1 Onde está o token

- Keychain macOS: serviço `gemini`, conta `antigravity`; valor `go-keyring-base64:<base64>`.
  - Decodificado: `{"token":{"access_token":"...","refresh_token":"...","expiry":"...","expires_in":3599},"auth_method":"consumer","id_token_email":"..."}`
- Arquivo: `~/.gemini/jetski-standalone-oauth-token` (mesma estrutura JSON).

### 4.2 Refresh (opt-in)

Há mais de um client_id OAuth em circulação (o binário local contém `1098991175725-...`; outros apps usam `1071006060591-...`). **Não hardcodar** um client secret: descubra do binário da versão instalada ou use o client que emitiu o refresh token. Refresh token é vinculado ao client; trocar de client gera `invalid_client`/`GOOGLE_TOS_NOT_SUPPORTED_BY_CLIENT`.

Refresh via `https://oauth2.googleapis.com/token` com `grant_type=refresh_token`. **Cuidado:** refresh token pode rotacionar; se renovar, persistir atomicamente no mesmo local (Keychain/arquivo) ou não persistir e pedir para o app renovar. Preferir o statusline/RPC local.

**ToS:** o Additional Terms §6 do Antigravity proíbe acesso por software de terceiros. OAuth direto é o caminho de maior risco; use apenas com opt-in explícito e aviso.

### 4.3 Alternativa: iniciar o language_server headless

É possível iniciar o binário com `--standalone`, `--csrf_token`, `--http_server_port`, `--app_data_dir` e `--cloud_code_endpoint`, mas ele depende do estado/OAuth do app. Só considerar se o fallback OAuth direto não bastar.

---

## 5. Erros e fallback

| Situação | Código | Ação |
|---|---|---|
| Hub ausente | `PROVIDER_NOT_RUNNING` | “Abra o Antigravity” |
| PID morto | `PROVIDER_NOT_RUNNING` | Limpar hub stale + mensagem |
| 401 no RPC | `AUTH_EXPIRED` | Abrir app / fallback OAuth |
| 404 no RPC | `SCHEMA_CHANGED` | Verificar versão do language_server |
| Timeout | `NETWORK` | Cache stale |
| Sem `remainingFraction` | `SCHEMA_CHANGED` | Não inventar; cache |

---

## 6. Segurança

- CSRF token é local; nunca logar.
- RPC só em `127.0.0.1`; não expor porta.
- Aceitar certificado self-signed **apenas** para `127.0.0.1`/`localhost`.
- Não copiar `access_token`/`refresh_token` para cache/histórico.
- `GetUserStatus` contém PII; mascarar e não persistir por padrão.

---

## 7. Testes

- Fixture real (3 grupos, 5 buckets).
- Hub simulado + servidor Connect local.
- Teste de `remainingFraction` 0, 0.5, 1.
- Teste de `remaining` aninhado/oneof e `disabled`.
- Teste de grupo sem buckets.
- Teste de CSRF ausente/errado (401).
- Teste de app fechado (hub stale).
- Integração opt-in com app real.

---

## 8. Riscos

- O formato do RPC e o nome do hub podem mudar entre versões.
- O app precisa estar rodando para a fonte local.
- Múltiplas instâncias/janelas podem gerar mais de um hub; escolher o PID vivo mais recente.
- O endpoint direto pode exigir scopes/headers adicionais em versões futuras.
- **ToS:** o Additional Terms §6 proíbe acesso por software de terceiros. O statusline oficial é o caminho de menor risco; OAuth direto é opt-in.
- `remainingFraction: 1` pode significar “sem consumo medido”, não “100% para sempre”; exibir o reset junto.
