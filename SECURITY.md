# Segurança

## Reportando

Não abra issue pública para vulnerabilidades. Use o canal privado do GitHub Security Advisories.

Inclua:

- versão do app e do sistema;
- provider afetado;
- passos para reproduzir;
- impacto (vazamento de token, PII, execução de código etc.);
- prova de conceito, se possível.

Prazo alvo: confirmação em 48h; correção ou mitigação em 7 dias para críticos.

## Escopo

- Vazamento de token/CSRF em log, JSON, erro, diagnóstico ou histórico.
- Bypass de redaction.
- Escrita indevida em credenciais.
- Dependência comprometida.
- Execução de código via código nativo ou dependência.

## Fora de escopo

- Endpoints internos mudarem (não é vulnerabilidade do app; abra issue de provider).
- ToS dos provedores.
- Acesso local por outro processo do mesmo usuário (modelo de ameaça do SO).
- Engenharia social.

## Política de tokens

- Nunca commitar token, CSRF, e-mail ou account ID.
- Se um token vazar em issue/PR/log: revogar/rotacionar imediatamente, remover o conteúdo e adicionar teste de regressão.
- O app não persiste tokens; lê em memória e descarta.

## Releases

- macOS: hardened runtime + notarização quando distribuído fora da máquina do autor.
- Windows: Authenticode quando distribuído.
- Linux: pacotes assinados quando possível.
- SBOM e checksums publicados.
