# quota_deck_models

DTOs, configuração e utilitários compartilhados entre o core, a CLI e o app Flutter.

Sem `dart:io`, sem `sqlite3`, sem Flutter. Pode ser importado no browser.

## Conteúdo

- `ProviderId`, `WindowKind`, `QuotaStatus`, `Confidence`, `SourceKind`.
- `ProviderSnapshot`, `QuotaWindow`, `AccountInfo`, `CreditsInfo`, `QdeckErrorInfo`.
- `SnapshotEnvelope`, `DetectionResult`, `DoctorCheck`, `HistorySample`, `HistorySummary`.
- `AppConfig` + defaults + `copyWith`.
- `statusForUsed`, `labelForWindow`, `kindForWindow`, `relativeTime`, `formatPercent`.
- `redact`, `maskEmail`, `isSensitiveKey`.

## Uso

```dart
import 'package:quota_deck_models/quota_deck_models.dart';

final snapshot = ProviderSnapshot.fromJson(json);
final status = statusForUsed(snapshot.windows.first.usedPercent);
```

## Testes

```bash
dart test
```
