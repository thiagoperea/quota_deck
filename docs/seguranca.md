# Segurança

O QuotaDeck lê credenciais locais. A regra é simples: ler o mínimo, guardar o mínimo, expor o mínimo.

## Ativos

| Ativo | Onde vive |
|---|---|
| Chave OpenCode Go | SQLite do OpenCode (`credential`) |
| OAuth Codex | `~/.codex/auth.json` |
| OAuth Claude | Keychain do macOS / `~/.claude/.credentials.json` |
| OAuth Antigravity | Keychain/arquivo; usado só pelo app original |
| CSRF do Antigravity | `hub_*.json` local |
| Histórico de uso | SQLite do QuotaDeck |

## Princípios

- **Somente leitura.** O app não escreve credenciais.
- **Sem refresh OAuth.** Token expirado vira mensagem para abrir a ferramenta original.
- **Sem telemetria.** Nenhum dado sai da máquina.
- **Sem daemon.** O desktop não abre porta, não cria cookie/token e não expõe HTTP.
- **Redaction.** Toda mensagem de erro/log passa por `redact()`.

## Credenciais por SO

### macOS

- Claude: Keychain `Claude Code-credentials`.
- Antigravity: Keychain `gemini`/`antigravity` (fallback; o app usa o RPC local).
- OpenCode: SQLite em `~/.local/share/opencode/opencode.db`.
- Codex: `~/.codex/auth.json`.
- O **App Sandbox está desligado** (`DebugProfile`/`Release`) para ler esses caminhos e executar `security`/`codex`. Distribuição fora da App Store; para Mac App Store seria necessário helper/security-scoped bookmarks.

### Windows

- OpenCode: `%LOCALAPPDATA%\opencode\opencode.db`.
- Codex: `%USERPROFILE%\.codex\auth.json`.
- Claude: `%USERPROFILE%\.claude\.credentials.json`.
- Antigravity: `%USERPROFILE%\.gemini\antigravity\daemon\hub_*.json`.

### Linux

- OpenCode: `$XDG_DATA_HOME/opencode/opencode.db` ou `~/.local/share/opencode/opencode.db`.
- Codex: `~/.codex/auth.json`.
- Claude: `~/.claude/.credentials.json`.
- Antigravity: `~/.gemini/antigravity/daemon/hub_*.json`.

## Redaction

Padrões: `oc_...`, `sk-ant-...`, `sk-...`, `ya29...`, JWT (`eyJ...`), `go-keyring-base64:`, `Bearer ...` e campos `token|secret|key|authorization|cookie|password`.

`maskEmail()` é usado em respostas e diagnóstico. Nenhum token aparece em JSON, tabela, log ou histórico.

## Logs e diagnóstico

- Log local com rotação; nunca headers ou corpos de credencial.
- `qdeck doctor` mostra presença/validade, não valores.
- Se um token aparecer em issue/log: revogar, remover o conteúdo e adicionar teste de regressão.

## Permissões

- Data dir `0700`; arquivos `0600` quando o SO permite.
- Windows não tem chmod POSIX; a proteção é a ACL do perfil do usuário.
- “Apagar dados” remove cache, histórico e config.

## Endpoints internos

OpenCode, Codex, Claude e Antigravity usam endpoints/RPC não documentados oficialmente. Eles podem mudar sem aviso. O app é read-only e não faz probe que consome quota, mas o uso é por sua conta e risco.

## Antigravity e ToS

O Additional Terms do Antigravity (§6) proíbe acesso ao serviço por software de terceiros. O caminho de menor risco é o statusline oficial do CLI; o app usa o RPC local que o próprio app já expõe. OAuth direto não é usado no fluxo padrão.

## Supply chain

- Lockfiles commitados.
- `dart analyze`/testes no CI.
- Releases assinadas quando houver distribuição.
- Revisão extra para PRs que tocam credenciais/providers.

## Checklist de PR

- [ ] Nenhum token/CSRF em log, fixture, teste ou print.
- [ ] Novo provider usa `redact()`.
- [ ] Nova chamada de rede tem timeout.
- [ ] Arquivo sensível com permissão restrita.
- [ ] Teste de segurança cobre o novo caminho.
