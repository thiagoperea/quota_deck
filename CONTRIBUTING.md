# Contribuindo

O QuotaDeck lê credenciais locais; por isso, além do código, a revisão de segurança faz parte do processo.

## Setup

Requisitos: Flutter 3.47+ e a toolchain do seu sistema (Xcode no macOS, Visual Studio Desktop C++ no Windows, GTK/CMake/Ninja no Linux).

```bash
cd quota_deck

(cd packages/models && dart pub get)
(cd packages/core && dart pub get)
(cd packages/cli && dart pub get)
(cd app && flutter pub get)

(cd app && flutter run -d macos)  # ou -d windows / -d linux
```

## Estrutura

- `app/` — UI Flutter desktop, tray e janela.
- `packages/models` — DTOs, config, status e redaction.
- `packages/core` — providers, cache, histórico SQLite, paths e doctor.
- `packages/cli` — CLI `qdeck`.
- `docs/` — arquitetura, build, segurança, modelo e providers.

## Adicionando um provider

1. Implemente `ProviderAdapter` em `packages/core/src/providers/<id>.dart`.
2. Adicione o enum em `packages/models` se for um provider novo.
3. Crie uma fixture real anonimizada em `packages/core/test/fixtures`.
4. Escreva testes de contrato e de erro (401/429/schema).
5. Atualize `docs/providers/<id>.md`.
6. A UI e a CLI consomem o provider automaticamente pelo registry.

## Testes

```bash
(cd packages/models && dart test)
(cd packages/core && dart test)
(cd packages/cli && dart test)
(cd app && flutter test)
```

Integração real opt-in:

```bash
(cd packages/core && QDECK_INTEGRATION=1 dart test test/integration_test.dart)
(cd app && QDECK_INTEGRATION=1 flutter test test/local_quota_integration_test.dart)
```

Análise:

```bash
(cd packages/models && dart analyze)
(cd packages/core && dart analyze)
(cd packages/cli && dart analyze)
(cd app && dart analyze lib test)
```

## Regras de PR

- PRs pequenos; um assunto por PR.
- Testes e análise verdes.
- Nenhum token, CSRF, e-mail ou account ID em código, fixture, log ou print.
- Toda chamada de rede tem timeout.
- Toda mensagem de erro passa por `redact()`.
- Novo arquivo sensível usa permissão restrita.
- PRs que tocam `providers/` ou credenciais exigem revisão extra.

## Commits

Convenção: `feat:`, `fix:`, `docs:`, `test:`, `chore:`, `security:`.

## Código de conduta

Ao participar, você concorda com o [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
