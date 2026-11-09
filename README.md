# QuotaDeck

App de bandeja para ver quanto de limite ainda resta em **OpenCode**, **Antigravity**, **Codex** e **Claude**.

Ele escaneia o que está instalado (Desktop e CLI), lê a credencial local de cada superfície e mostra tudo em uma janela compacta. Sem login, sem proxy, sem telemetria.

## O que faz

- Detecção por superfície: separa **Desktop** e **CLI**, mostra versão/caminho/conta e só exibe no assistente o que existe na máquina.
- OpenCode lê o banco XDG (`~/.local/share/opencode/opencode.db`) ou o legado `%LOCALAPPDATA%`.
- Claude Desktop usa o histórico local (`plan-usage-history.json`, estimado); Claude Code usa a API OAuth ao vivo.
- Ícone na bandeja e assistente guiado por provedor, com instruções de login/refresh.
- Provedor mais usado, próximo reset e uso disponível estimado no topo.
- Clique abre a janela compacta; menu abre o dashboard ou atualiza.
- Janelas de 5h, semanais e mensais por provedor, com reset e status.
- Histórico local em SQLite com burn rate e ETA.
- CLI `qdeck` para terminal, scripts e statusline.
- Cache de 60 s e fallback para o último dado quando a rede falha.

## Instalar

**Windows (recomendado):** baixe `quota_deck-<versão>-setup.exe` na release mais recente. O instalador grava em `%LOCALAPPDATA%\Programs\QuotaDeck`, cria atalho no Menu Iniciar (e opcional na área de trabalho) e desinstalador. Não precisa de admin.

**macOS/Linux ou build local:**

```bash
git clone https://github.com/thiagoperea/quota_deck.git
cd quota_deck/app
flutter pub get
flutter run -d macos      # ou -d windows / -d linux
```

Build:

```bash
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

Os artifacts também são gerados no GitHub Actions (`.app`, `.exe` e bundle Linux).

## CLI

```bash
cd packages/cli
dart pub global activate --source path .
qdeck show
qdeck json
qdeck doctor
qdeck history --provider opencode --window rolling --hours 24
qdeck watch --interval 60
qdeck statusline
```

Se `qdeck` não aparecer no PATH:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

Ou sem instalar globalmente:

```bash
dart run bin/qdeck.dart show
```

`qdeck statusline` devolve uma linha curta, por exemplo:

```text
OC 4% · AG 12% · CX 0% · CL !
```

## Como funciona

O desktop é **um processo só**: o app chama o core Dart (`packages/core`) diretamente. Não há daemon, porta ou token.

```
app Flutter (macOS/Linux/Windows)
        │
        ▼
packages/core ──► credenciais locais
        ├────────► OpenCode SQLite + /zen/go/v1/usage
        ├────────► Antigravity language_server (RPC local)
        ├────────► Codex app-server / wham/usage
        └────────► Claude Code Keychain/arquivo + OAuth usage
```

O core é somente leitura: não renova OAuth, não escreve credenciais e não faz probe que consome quota.

## Segurança

- Nenhum token vai para servidor próprio, log ou histórico.
- Credenciais lidas localmente; cache e histórico com permissão restrita.
- No macOS o App Sandbox fica desligado porque o app precisa ler `~/.codex`, `~/.claude`, SQLite do OpenCode e o hub do Antigravity.
- Endpoints internos podem mudar sem aviso. Use por sua conta e risco.

Detalhes em [`docs/seguranca.md`](docs/seguranca.md).

## Limitações

- Antigravity precisa do app aberto para o RPC local.
- Claude Code com token expirado pede para abrir o Claude Code e renovar.
- Codex usa `wham/usage` quando o binário `codex` não está no PATH.
- Tray no Linux depende de um painel com AppIndicator (KDE, Ubuntu com extensão etc.).

## Licença

MIT.
