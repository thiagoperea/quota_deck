import 'package:flutter_test/flutter_test.dart';
import 'package:quota_deck/src/desktop/update_service.dart';

void main() {
  final service = UpdateService();

  group('compareVersions', () {
    test('versões iguais resultam em 0', () {
      expect(service.compareVersions('1.0.0', '1.0.0'), 0);
      expect(service.compareVersions('1.2', '1.2.0'), 0);
    });

    test('patch maior é mais novo', () {
      expect(service.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(service.compareVersions('1.0.0', '1.0.1'), lessThan(0));
    });

    test('compara segmentos como números, não texto', () {
      expect(service.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(service.compareVersions('1.9.9', '1.10.0'), lessThan(0));
    });

    test('aceita prefixo v', () {
      expect(service.compareVersions('v1.0.1', '1.0.0'), greaterThan(0));
      expect(service.compareVersions('V1.0.1', 'v1.0.1'), 0);
    });

    test('ignora build metadata', () {
      expect(service.compareVersions('1.2.3+8', '1.2.3'), 0);
      expect(service.compareVersions('1.2.4+8', '1.2.3'), greaterThan(0));
    });

    test('ignora sufixos de pré-release', () {
      expect(service.compareVersions('1.2.3-rc.1', '1.2.3'), 0);
    });

    test('strings vazias ou inválidas não lançam', () {
      expect(service.compareVersions('', ''), 0);
      expect(service.compareVersions('abc', 'xyz'), 0);
      expect(service.compareVersions('', '1.0.0'), lessThan(0));
      expect(service.compareVersions('1.0.0', ''), greaterThan(0));
    });
  });

  group('isNewer', () {
    test('detecta versão mais nova', () {
      expect(service.isNewer('1.0.1', '1.0.0'), isTrue);
      expect(service.isNewer('1.10.0', '1.9.9'), isTrue);
    });

    test('versão igual ou anterior não é nova', () {
      expect(service.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(service.isNewer('0.9.9', '1.0.0'), isFalse);
    });

    test('aceita prefixo v na tag', () {
      expect(service.isNewer('v0.7.0', '0.6.0'), isTrue);
      expect(service.isNewer('v0.6.0', '0.6.0'), isFalse);
    });

    test('build metadata não conta como nova versão', () {
      expect(service.isNewer('1.2.3+9', '1.2.3+8'), isFalse);
    });

    test('entradas inválidas não lançam', () {
      expect(service.isNewer('', ''), isFalse);
      expect(service.isNewer('abc', 'xyz'), isFalse);
    });
  });
}
