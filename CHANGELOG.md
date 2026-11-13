# Changelog

## 0.7.1

### Bandeja e janela
- Fechar a janela **não encerra mais o app** no macOS: o runner deixou de
  terminar no último fechamento e o `TrayService` só esconde (ou encerra de
  forma explícita quando não há bandeja). Teste de regressão lê o
  `AppDelegate.swift`.
- Falha ao inicializar a bandeja não derruba mais o app; `_quit`/`dispose`
  ficaram idempotentes.

### Detecção de provedores
- Instalação agora exige prova real: binário no PATH, `Nome.app` em
  `/Applications`/`~/Applications` ou processo rodando. Diretório de config,
  histórico antigo e credencial órfã não contam mais — sobras de instalações
  antigas faziam Codex e Claude aparecerem como instalados.
- A tela de Configurações lista apenas provedores instalados (ou ligados) e
  resume em uma linha: "Desktop e CLI conectados", "Desktop conectado",
  "CLI sem login". Os ausentes viram uma nota com "Abrir assistente".
- A leitura manda mais que a detecção: superfície com erro de login não
  aparece como conectada em nenhuma tela.
- "Verificar agora" invalida o cache de descoberta e vê binários instalados
  depois de abrir o app.

### Claude no macOS
- Respeita `CLAUDE_CONFIG_DIR` (arquivo antes do Keychain), tenta
  `~/.claude/.credentials.json` como fallback e diferencia
  `PERMISSION_DENIED` (`security` exit 51/45) de credencial ausente.

### Dados e erros
- Falha de socket/DNS/TLS vira `NETWORK` (exit 3) e JSON inesperado vira
  `SCHEMA_CHANGED`; antes caíam em `UNKNOWN`.
- Credencial ilegível deixa de ser reportada como "não instalado" (exit 2).
- `clampPercent(99,95)` não anuncia mais 100%/limite.
- `AppConfig.fromJson` normaliza thresholds, retenção e tema (config editado
  à mão não apaga mais o histórico).
- Backup `.bak` de config/cache não é mais sobrescrito por arquivo corrompido.
- Burn rate/ETA ignora amostras anteriores ao último reset da janela.
- `QdeckErrorInfo.toJson` redige `message` e `details` (cobre `--json`).

### CLI (`qdeck`)
- `dart pub global activate` volta a criar o binário (`executables: qdeck`).
- Versão unificada com o app (`0.7.1`); teste impede divergência.
- `doctor --json`, `--no-color` e `--data-dir`; ignora provedores desligados e
  diz "token expirado em X — abra o Claude Code para renovar".
- Novo `show/json --include-disabled`; provider desligado pedido em
  `--provider` avisa e sai com 5.
- `watch` não emite mais `ESC[2J` em pipe e ganhou `--no-clear`.

### Painel e visual
- Tema claro sem o véu cinza nos cards (cor sólida em vez de gradiente com
  alfa baixo) e ação de snackbar com contraste AA.
- Header (inclusive compacto) mostra a **última coleta**, não o dado mais
  antigo; "Próximos resets" inclui o grupo para desambiguar "5 horas".
- Falha de atualização marca os cards como desatualizados.
- KPIs empilham em telas estreitas/fonte ampliada; barra em 0% sem ponto
  verde; menu de visibilidade opaco; feedback ao salvar personalização.
- Wizard não sobrepõe mais erro de carga e fechar o assistente persiste o
  onboarding. Copy de "atualizado há…" e do mini corrigidas.

### Segurança e release
- Link de atualização só abre `https://github.com/thiagoperea/quota_deck/...`;
  no Windows usa `rundll32` em vez de `cmd /c start`.
- `make clean` não apaga mais o pub cache global; tarefa desconhecida sai 64;
  `setup` avisa sobre Xcode/CocoaPods ausentes.
- CI falha se a tag não bater com `app/pubspec.yaml`.
- **macOS continua apenas como build local**: sem Developer ID/notarização o
  binário baixado é marcado como danificado pelo Gatekeeper, então o zip saiu
  dos assets do release. Compile com `cd app && flutter build macos --release`.

## 0.7.0

### Painel
- O refresh saiu do isolate da UI: o core roda em um worker persistente e a
  janela não trava mais se um provedor demora. Timeout por provedor caiu de
  40 s para 12 s.
- Refreshes concorrentes não são mais descartados: quem chega durante uma
  rodada aguarda e dispara uma nova no fim (last-wins). "Já renovei" e o
  assistente passam a ler dados realmente frescos.
- `%` da janela virou o número de destaque (17 px, dígitos tabulares) e a
  barra cresceu para 8 px; "resta X%" aparece no tooltip e no leitor de tela.
- KPI duplicado removido: "Folga da janela mais apertada" + "Próximo reset",
  com a cor vinda do status da própria janela (fim das três regras de cor).
- Faixa "Precisa de atenção" no topo, sem revogar a ordem personalizada.
- Rodapé de procedência dos cards só aparece quando o dado está velho,
  estimado ou com erro.
- Breakpoint do painel lateral em 760 px (antes 980) e KPIs do compacto em
  2 colunas; sem overflow em 320 px com fonte 1.5×.

### Mini e bandeja
- Mini mostra "atualizado há X" e um aviso âmbar com "Tentar" quando o
  refresh falha ou o dado está velho.
- Notificações são agregadas em um toast por avaliação e suprimidas com a
  janela aberta; clicar no toast foca a janela em vez de encolhê-la.
- Mini não estoura mais com nome de superfície + "login necessário".

### Configuração e assistente
- Personalização grava em série e sempre persiste o estado mais recente;
  falha de gravação aparece na tela. "Restaurar padrão" ganhou Desfazer (5 s)
  e só habilita quando há customização.
- Sair do sheet de Configurações para Personalizar respeita edições não
  salvas.
- "Verificar agora/de novo" força a redetecção (antes lia o cache e dava
  falso positivo). Resumo do assistente conta pendências e não diz mais
  "Tudo pronto" com login faltando; fechar com ajustes pede confirmação.

### Visual e acessibilidade
- Contraste AA: `dim` claro 4,25 → 6,3:1, bordas de controle a 3:1, foco
  visível (0.32), hover 12%; texto mínimo 10,5 px.
- Todos os números usam `tabularFigures`; `QdSpace`/`QdRadius`/`QdMotion`
  novos e animações respeitam "reduzir movimento".
- Status de superfície ganhou ícone e texto além da cor.
- Formatação pt-BR (vírgula) e nunca "100%" antes do limite real; moeda via
  `intl`. `flutter_localizations` em pt-BR para widgets nativos.

### Correções
- Janela do dashboard cabe na área útil (1366×768 não corta mais o rodapé).
- Sparkline só repinta quando os valores mudam; cards em `RepaintBoundary`.
- `DoctorCheck`/`HistorySummary` ganharam `fromJson` (paridade CLI/RPC).
- Testes novos: refresh concorrente, worker do core, mini stale, 320 px com
  fonte 1.5×, semântica da barra e formatação de percentual.

### Mock removido
- O seletor de cenários e o `--dart-define=QDECK_MOCK=1` saíram do app: não
  há mais caminho de dados falsos em produção. As fixtures de UI continuam
  em `app/test/support/fake_api.dart`, usadas só pelos testes.

### Notificações
- Aviso nativo ao cruzar os limites (padrão 80%) e no crítico (95%), com
  histerese: uma travessia = uma notificação; re-arma ao cair 5 pontos ou
  quando a janela reseta de verdade.
- Configuração no sheet: liga/desliga, sliders de aviso/crítico e
  "Testar notificação". Funciona com a janela na bandeja (polling de 5 min).

### Personalizar painel
- Nova tela com reordenação dos provedores por arraste.
- Cada janela pode ser **Sempre**, **Sob demanda** (atrás de "mostrar mais")
  ou **Oculta** — ocultar não interrompe a consulta.
- Mini e dashboard respeitam a escolha; "Restaurar padrão" limpa tudo.

### Resiliência
- HTTP 429 entra em backoff persistido (5 min ou `Retry-After`), reaproveita o
  último snapshot e mostra quando a próxima tentativa acontece; refresh manual
  também respeita o bloqueio.

### Provedores
- Detecção incremental: só liga o que encontrou, nunca desliga, e persiste o
  resultado da primeira execução.
- "Detectar provedores" no menu da bandeja, com resumo do que foi encontrado.

### Bandeja e atualização
- Ícone da bandeja muda de cor por severidade (verde/amarelo/vermelho) e o
  tooltip lista todos os provedores.
- Aviso discreto de nova versão (release do GitHub), com botão "Baixar" e
  opção de desligar a checagem.

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
