import 'package:flutter/material.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

import '../theme.dart';
import 'provider_card.dart';

/// Estado vazio: nenhum provedor detectado (ou todos desativados).
class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    super.key,
    this.onRetry,
    this.onOpenWizard,
    this.onOpenSettings,
    this.noProvidersEnabled = false,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onOpenWizard;
  final VoidCallback? onOpenSettings;
  final bool noProvidersEnabled;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Container(
      key: const Key('onboarding-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: palette.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  noProvidersEnabled ? Icons.tune : Icons.radar_outlined,
                  size: 18,
                  color: palette.green,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      noProvidersEnabled
                          ? 'Todos os provedores estão desativados'
                          : 'Nenhum provedor detectado',
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      noProvidersEnabled
                          ? 'Ative pelo menos um provedor nas configurações para ver as quotas.'
                          : 'O QuotaDeck lê as credenciais que já existem na sua máquina. Entre em uma das ferramentas abaixo e depois atualize.',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!noProvidersEnabled) ...[
            const SizedBox(height: 16),
            _Step(
              number: '1',
              provider: ProviderId.opencode,
              instruction:
                  'Use o OpenCode Go uma vez para criar a credencial local.',
              command: 'opencode',
            ),
            _Step(
              number: '2',
              provider: ProviderId.antigravity,
              instruction: 'Abra o app Antigravity e faça login; o language server local expõe a quota.',
            ),
            _Step(
              number: '3',
              provider: ProviderId.codex,
              instruction: 'Faça login no Codex para gravar a sessão local.',
              command: 'codex',
            ),
            _Step(
              number: '4',
              provider: ProviderId.claude,
              instruction:
                  'Faça login no Claude Code para renovar o token OAuth.',
              command: 'claude',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: palette.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: palette.green.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 15, color: palette.green),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '100% local: nenhum token ou dado de uso sai da sua máquina.',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: QdType.small,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onOpenWizard != null)
                FilledButton.icon(
                  key: const Key('onboarding-wizard'),
                  onPressed: onOpenWizard,
                  icon: const Icon(Icons.checklist_rtl, size: 16),
                  label: const Text('Abrir assistente'),
                ),
              if (onRetry != null)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(
                    noProvidersEnabled ? 'Atualizar' : 'Verificar novamente',
                  ),
                ),
              if (onOpenSettings != null)
                OutlinedButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Configurações'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.text,
                    side: BorderSide(color: palette.border),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.provider,
    required this.instruction,
    this.command,
  });

  final String number;
  final ProviderId provider;
  final String instruction;
  final String? command;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 19,
            height: 19,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.panel,
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: palette.muted,
                fontSize: QdType.meta,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ProviderAvatar(provider: provider, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      provider.displayName,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (command != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.panel,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: palette.border),
                        ),
                        child: SelectableText(
                          command!,
                          style: TextStyle(
                            color: palette.green,
                            fontSize: QdType.meta,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  instruction,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: QdType.small,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
