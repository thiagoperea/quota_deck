# Benchmark do core Dart — 08/11/2026

Ambiente: macOS 27.0.1, MacBook Air arm64, 16 GB RAM, Flutter/Dart 3.13.7.
Método: `packages/core/tool/bench.dart`, uma execução por provider, sem cache (`noCache: true`), incluindo startup do processo Dart.

| Provider | Latência | Janelas | Erros | Fonte |
|---|---:|---:|---:|---|
| OpenCode | 404 ms | 3 | 0 | `opencode-usage-api` |
| Antigravity | 29 ms | 5 | 0 | `antigravity-language-server` |
| Codex | 283 ms | 2 | 0 | `codex-wham-usage` |
| Claude | 38 ms | 0 | 1 | `error` (token expirado, sem rede) |

**Total do snapshot completo (probe):** ~1,75–1,97 s, incluindo startup do Dart e build hooks.

Observações:

- Antigravity é o mais rápido porque usa RPC local, sem rede.
- Claude falha antes da rede ao detectar `expiresAt` no passado; 38 ms é o custo de ler o Keychain.
- Codex usou o fallback `wham/usage` porque o binário `codex` não está no PATH; com `app-server`, a expectativa é similar ao Antigravity (processo local).
- Números de uma execução; não são benchmark estatístico. Servem para ordem de grandeza e para detectar regressões.
