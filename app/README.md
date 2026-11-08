# QuotaDeck — app

App Flutter desktop (macOS/Linux/Windows) com bandeja do sistema.

```bash
flutter pub get
flutter run -d macos      # ou -d windows / -d linux
```

O app é single-process: `LocalQuotaApi` chama `packages/core` diretamente. Não há daemon, porta ou token.

Modo mock:

```bash
flutter run -d macos --dart-define=QDECK_MOCK=1
```

Build:

```bash
flutter build macos --release
flutter build windows --release
flutter build linux --release
```

Testes:

```bash
flutter test
dart analyze lib test
```

O target macOS exige Xcode; Windows exige Visual Studio Desktop C++; Linux exige GTK/CMake/Ninja. O App Sandbox do macOS fica desligado para ler credenciais locais.
