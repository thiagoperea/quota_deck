import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Detecta `--startup` mesmo quando o runner do Flutter não repassa `main(args)`.
///
/// No Windows a linha de comando real é lida com `GetCommandLineW`; nos outros
/// desktops usa `Platform.executableArguments`.
bool launchedAtStartup([List<String> args = const []]) {
  if (args.contains('--startup')) return true;
  if (Platform.isWindows) {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getCommandLine = kernel32
          .lookupFunction<Pointer<Utf16> Function(), Pointer<Utf16> Function()>(
            'GetCommandLineW',
          );
      final line = getCommandLine().toDartString();
      return line.contains('--startup');
    } catch (_) {
      return false;
    }
  }
  return Platform.executableArguments.contains('--startup');
}
