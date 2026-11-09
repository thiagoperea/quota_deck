# Build, run e testes

## Pré-requisitos

| Ferramenta | Uso |
|---|---|
| Flutter 3.47+ / Dart 3.13+ | app, core e CLI |
| Xcode 27+ | build macOS (macOS 26.6+, Apple Silicon) |
| Visual Studio Desktop C++ | build Windows |
| GTK 3, X11, Xi, CMake, Ninja, Clang | build Linux |
| Node/npm | não é usado |

```bash
flutter --version
dart --version
flutter doctor -v
```

## Dependências

```bash
cd quota_deck

dart tool/tasks.dart setup
```

`tool/tasks.dart` funciona no Windows, macOS e Linux; os alvos do `Makefile` apenas delegam para ele (`make setup`, `make analyze`, `make test`, `make build-windows`, `make installer`).

## Windows (instalador)

O CI gera `quota_deck-<versão>-setup.exe` (Inno Setup) junto do zip portátil:

```powershell
# build local do instalador (requer Inno Setup 6 no PATH)
cd app; flutter build windows --release
cd ..
dart tool/tasks.dart installer
```

O instalador usa `%LOCALAPPDATA%\Programs\QuotaDeck` (sem admin), cria atalho no Menu Iniciar, desinstalador e opcionalmente inicia com o Windows.

## Rodar o app

```bash
cd app
flutter run -d macos      # macOS
flutter run -d windows    # Windows
flutter run -d linux      # Linux
```

Modo mock (sem credenciais, dados sintéticos):

```bash
flutter run -d macos --dart-define=QDECK_MOCK=1
```

O app abre em 420×760. O tray mostra o pior provedor; clique esquerdo alterna a janela, clique direito abre o menu.

## Build

```bash
cd app
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

Ou `dart tool/tasks.dart build-windows` (idem macOS/Linux).

Saídas:

- macOS: `build/macos/Build/Products/Release/quota_deck.app`
- Windows: `build/windows/x64/runner/Release/`
- Linux: `build/linux/x64/release/bundle/`

O CI em `.github/workflows/ci.yml` gera os três artifacts.

## CLI

Instalação local:

```bash
cd packages/cli
dart pub global activate --source path .
qdeck show
```

Ou sem instalar:

```bash
dart run bin/qdeck.dart show
```

Comandos:

```text
qdeck show [--provider id] [--json] [--no-cache] [--ttl s] [--no-color]
qdeck json
qdeck doctor
qdeck history --provider id --window id [--hours 24]
qdeck settings [--json]
qdeck watch [--provider id] [--interval 60] [--no-color]
qdeck statusline
qdeck version
```

Exit codes: `0` ok, `2` auth, `3` rede, `4` rate limit, `5` parcial/erro.

## Testes

```bash
(cd packages/models && dart test)
(cd packages/core && dart test)
(cd packages/cli && dart test)
(cd app && flutter test)
```

Integração real (opt-in):

```bash
(cd packages/core && QDECK_INTEGRATION=1 dart test test/integration_test.dart)
(cd app && QDECK_INTEGRATION=1 flutter test test/local_quota_integration_test.dart)
```

Análise estática:

```bash
(cd packages/models && dart analyze)
(cd packages/core && dart analyze)
(cd packages/cli && dart analyze)
(cd app && dart analyze lib test)
```

> Em paths com espaço/Unicode, `flutter analyze` pode crashar o analysis server. Use `dart analyze lib test`.

## macOS

O App Sandbox está desligado nos entitlements (`DebugProfile` e `Release`) porque o app lê credenciais fora do container. Isso é intencional para distribuição fora da App Store.

Para build local, Xcode completo é obrigatório:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -license accept
cd app && flutter build macos --release
```

Assinatura/notarização são necessárias apenas para distribuir fora da sua máquina.

## Troubleshooting

| Sintoma | Ação |
|---|---|
| Tray não aparece no Linux | precisa de AppIndicator no painel (KDE, Ubuntu com extensão) |
| `xcodebuild requires Xcode` | instalar Xcode; os testes Dart e a CLI seguem funcionando |
| Claude com `AUTH_EXPIRED` | abrir o Claude Code e renovar; o app não renova refresh token |
| Antigravity sem dados | abrir o Antigravity; o RPC local depende do app rodando |
| Codex sem app-server | o adapter cai para `wham/usage` |
