# qdeck

CLI do QuotaDeck. Usa `quota_deck_core` diretamente; não precisa do app aberto.

## Instalar

```bash
cd packages/cli
dart pub global activate --source path .
qdeck show
```

O shim fica em `~/.pub-cache/bin` (precisa estar no `PATH`). Para conferir:
`which qdeck && qdeck version`.

Ou:

```bash
dart run bin/qdeck.dart show
```

## Comandos

```text
qdeck show [--provider id] [--json] [--no-cache] [--ttl s] [--no-color]
           [--include-disabled]
qdeck json
qdeck doctor
qdeck history --provider id --window id [--hours 24]
qdeck settings [--json]
qdeck watch [--provider id] [--interval 60] [--no-color] [--no-clear]
qdeck statusline
qdeck version
```

`statusline` devolve uma linha curta:

```text
OC 4% · AG 12% · CX 0% · CL !
```

Exit codes: `0` ok, `2` auth, `3` rede, `4` rate limit, `5` parcial/erro.
