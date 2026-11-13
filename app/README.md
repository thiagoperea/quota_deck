# QuotaDeck — app

App Flutter desktop (macOS/Linux/Windows) com bandeja do sistema.

```bash
flutter pub get
flutter run -d macos      # ou -d windows / -d linux
```

O app é single-process: `LocalQuotaApi` conversa com um worker Dart persistente
que roda `packages/core`. Não há daemon nem HTTP; a única porta é o socket local
de instância única (`127.0.0.1:47831`), usado só para trazer a janela à frente.

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
