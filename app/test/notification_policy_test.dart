import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/desktop/notification_service.dart';
import 'package:quota_deck_models/quota_deck_models.dart';

ProviderSnapshot _snapshot({
  double used = 0,
  DateTime? resetsAt,
  bool stale = false,
  List<QdeckErrorInfo> errors = const [],
}) => ProviderSnapshot(
  provider: ProviderId.claude,
  account: const AccountInfo(label: 'Claude'),
  windows: [
    QuotaWindow(
      id: 'five_hour',
      label: '5 horas',
      kind: WindowKind.session,
      usedPercent: used,
      remainingPercent: 100 - used,
      resetsAt: resetsAt,
      status: statusForUsed(used),
      source: SourceKind.api,
    ),
  ],
  source: 'test',
  fetchedAt: DateTime.utc(2026, 11, 10, 12),
  stale: stale,
  errors: errors,
);

SnapshotEnvelope _envelope({double used = 0, DateTime? resetsAt}) =>
    SnapshotEnvelope(
      generatedAt: DateTime.utc(2026, 11, 10, 12),
      results: [_snapshot(used: used, resetsAt: resetsAt)],
    );

AppConfig _config() => AppConfig.defaults().copyWith(
  notificationsEnabled: true,
  warningThreshold: 80,
  criticalThreshold: 95,
);

void main() {
  test('avisa uma vez ao cruzar o limiar de aviso', () {
    final policy = NotificationPolicy();
    final config = _config();
    final reset = DateTime.utc(2026, 11, 10, 15);

    final first = policy.evaluate(
      envelope: _envelope(used: 82, resetsAt: reset),
      config: config,
    );
    expect(first, hasLength(1));
    expect(first.first.title, contains('82%'));

    final second = policy.evaluate(
      envelope: _envelope(used: 84, resetsAt: reset),
      config: config,
    );
    expect(second, isEmpty);
  });

  test('pular direto para crítico gera só a notificação crítica', () {
    final policy = NotificationPolicy();
    final messages = policy.evaluate(
      envelope: _envelope(used: 97),
      config: _config(),
    );
    expect(messages, hasLength(1));
    expect(messages.first.title, contains('limite'));
  });

  test('re-arma quando o uso cai 5 pontos abaixo do aviso', () {
    final policy = NotificationPolicy();
    final config = _config();
    expect(
      policy.evaluate(envelope: _envelope(used: 82), config: config),
      hasLength(1),
    );
    expect(
      policy.evaluate(envelope: _envelope(used: 74), config: config),
      isEmpty,
    );
    expect(
      policy.evaluate(envelope: _envelope(used: 81), config: config),
      hasLength(1),
    );
  });

  test('reset muito distante trata como janela nova e re-arma', () {
    final policy = NotificationPolicy();
    final config = _config();
    final first = DateTime.utc(2026, 11, 10, 15);
    expect(
      policy.evaluate(
        envelope: _envelope(used: 82, resetsAt: first),
        config: config,
      ),
      hasLength(1),
    );
    expect(
      policy.evaluate(
        envelope: _envelope(
          used: 82,
          resetsAt: first.add(const Duration(hours: 3)),
        ),
        config: config,
      ),
      hasLength(1),
    );
  });

  test('não notifica snapshot stale, com erro ou janela oculta', () {
    final policy = NotificationPolicy();
    final config = _config().withWindowVisibility(
      ProviderId.claude,
      'five_hour',
      WindowVisibility.hidden,
    );
    expect(
      policy.evaluate(
        envelope: SnapshotEnvelope(
          generatedAt: DateTime.utc(2026, 11, 10, 12),
          results: [_snapshot(used: 99, stale: true)],
        ),
        config: _config(),
      ),
      isEmpty,
    );
    expect(
      policy.evaluate(
        envelope: SnapshotEnvelope(
          generatedAt: DateTime.utc(2026, 11, 10, 12),
          results: [
            _snapshot(
              used: 99,
              errors: const [
                QdeckErrorInfo(code: 'NETWORK', message: 'offline'),
              ],
            ),
          ],
        ),
        config: _config(),
      ),
      isEmpty,
    );
    expect(
      policy.evaluate(envelope: _envelope(used: 99), config: config),
      isEmpty,
    );
  });
}
