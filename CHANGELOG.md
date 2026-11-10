# Changelog

## 0.6.0

### Claude sem CLI
- Lê a sessão do **Claude Desktop** direto do `config.json` do Electron e decifra
  `oauth:tokenCacheV2` via `safeStorage` (DPAPI + AES-256-GCM no Windows,
  Keychain + AES-128-CBC no macOS). Não é mais preciso ter o Claude Code.
- Fallback para o histórico local (`plan-usage-history.json`) quando a leitura
  ao vivo falha, e mensagens de renovação apontam para o app, não para o CLI.
- `qdeck`/painel mostram `Claude Desktop (team)` com as janelas 5h e 7d.

### Mini
- Mini ancorado na bandeja: abre no canto inferior direito da área útil do
  monitor do cursor, com validação de coordenadas (nunca fora da tela).
- Tamanho fixo de 380×500, sem alças de redimensionamento.
- Lista as janelas de todos os provedores (5h e 7d sempre), incluindo os grupos
  do Antigravity, sem resumo, sem versão no rodapé.
- Logo/título também abrem o dashboard, além do botão.

### Cards
- Logos reais dos provedores (Claude, Codex, Antigravity, OpenCode) no lugar
  das iniciais.
- `5 horas` no lugar de `Rolling 5h`; janelas curtas antes das longas.
- Badge de status alinhado à direita; confiabilidade removida do rodapé.
- Tempo relativo com precisão (`em 4 h 44 min`, `em 12 d 18 h`).
- Sem email sob o nome e sem fonte por linha; créditos só aparecem com valor.

### Sistema
- Iniciar com o sistema (Windows Run key, LaunchAgent, `.desktop`) com
  `--startup`, abrindo direto na bandeja.
- Instalador Windows atualizado com a task de autostart.

### Mock
- Nove cenários de layout (normal, status, estados de card, grupos, um
  provedor, não instalado, vazio, erro, carregando), com seletor de cenário e
  de tamanho de janela. Porta de instância própria para rodar junto do app.

### Correções
- Salvar configurações não abre mais o diálogo de "descartar alterações".
- Janela não fica mais fora da tela ao abrir o mini.
