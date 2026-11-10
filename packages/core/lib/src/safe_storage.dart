import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:ffi/ffi.dart';

/// Descriptografa blobs do Electron `safeStorage` no Windows e no macOS.
///
/// Windows: `"v10" || nonce(12) || ciphertext || tag(16)`, chave AES-256
/// protegida por DPAPI em `Local State` (`os_crypt.encrypted_key`).
///
/// macOS: `"v10" || ciphertext`, AES-128-CBC com chave do Keychain
/// (`Claude Safe Storage`) — implementado apenas quando o item existe.
///
/// Linux: Electron usa `basic_text`/libsecret; não suportado aqui e o
/// chamador cai no histórico local.
Future<Uint8List?> decryptElectronSafeStorage(
  String encoded, {
  required String localStatePath,
}) async {
  if (encoded.isEmpty) return null;
  try {
    final raw = base64Decode(encoded);
    if (raw.length < 19 || raw[0] != 0x76 || raw[1] != 0x31 || raw[2] != 0x30) {
      _debug(
        'blob sem prefixo v10 (${raw.length} bytes; ${raw.take(3).toList()})',
      );
      return null;
    }
    if (Platform.isWindows) {
      return await _decryptWindows(raw, localStatePath);
    }
    if (Platform.isMacOS) {
      return await _decryptMac(raw);
    }
    _debug('plataforma sem suporte a safeStorage');
    return null;
  } catch (error) {
    _debug('falha ao decifrar: ${error.runtimeType}: $error');
    return null;
  }
}

final bool _debugEnabled =
    Platform.environment['QDECK_DEBUG_SAFE_STORAGE'] == '1';

void _debug(String message) {
  if (_debugEnabled) stderr.writeln('[safeStorage] $message');
}

// ---------------------------------------------------------------------------
// Windows (DPAPI + AES-256-GCM)
// ---------------------------------------------------------------------------

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

typedef _CryptUnprotectDataNative = Int32 Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Void> ppszDataDescr,
  Pointer<Void> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  Uint32 dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _CryptUnprotectDataDart = int Function(
  Pointer<_DataBlob> pDataIn,
  Pointer<Void> ppszDataDescr,
  Pointer<Void> pOptionalEntropy,
  Pointer<Void> pvReserved,
  Pointer<Void> pPromptStruct,
  int dwFlags,
  Pointer<_DataBlob> pDataOut,
);

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

Future<Uint8List?> _decryptWindows(Uint8List raw, String localStatePath) async {
  final key = _windowsAesKey(localStatePath);
  if (key == null) return null;
  final nonce = raw.sublist(3, 15);
  final payload = raw.sublist(15);
  if (payload.length <= 16) return null;
  final cipherText = payload.sublist(0, payload.length - 16);
  final mac = payload.sublist(payload.length - 16);

  final clear = await AesGcm.with256bits().decrypt(
    SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
    secretKey: SecretKey(key),
  );
  return Uint8List.fromList(clear);
}

Uint8List? _windowsAesKey(String localStatePath) {
  final file = File(localStatePath);
  if (!file.existsSync()) {
    _debug('Local State não encontrado: $localStatePath');
    return null;
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) return null;
  final osCrypt = decoded['os_crypt'];
  if (osCrypt is! Map) {
    _debug('Local State sem os_crypt');
    return null;
  }
  final encoded = osCrypt['encrypted_key']?.toString();
  if (encoded == null || encoded.isEmpty) {
    _debug('Local State sem encrypted_key');
    return null;
  }
  final blob = base64Decode(encoded);
  if (blob.length <= 5) return null;
  // Prefixo "DPAPI" antes do blob protegido.
  if (blob[0] != 0x44 ||
      blob[1] != 0x50 ||
      blob[2] != 0x41 ||
      blob[3] != 0x50 ||
      blob[4] != 0x49) {
    _debug('encrypted_key sem prefixo DPAPI');
    return null;
  }
  final key = _dpapiUnprotect(Uint8List.fromList(blob.sublist(5)));
  if (key == null) {
    _debug('DPAPI não devolveu chave');
  } else {
    _debug('chave DPAPI ok (${key.length} bytes)');
  }
  return key;
}

Uint8List? _dpapiUnprotect(Uint8List data) {
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final unprotect = crypt32
      .lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectDataDart>(
        'CryptUnprotectData',
      );
  final localFree = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>(
    'LocalFree',
  );

  final input = malloc.allocate<Uint8>(data.length);
  input.asTypedList(data.length).setAll(0, data);
  final blobIn = malloc<_DataBlob>();
  final blobOut = malloc<_DataBlob>();
  blobIn.ref
    ..cbData = data.length
    ..pbData = input;
  blobOut.ref
    ..cbData = 0
    ..pbData = nullptr;

  try {
    final ok = unprotect(
      blobIn,
      nullptr,
      nullptr,
      nullptr,
      nullptr,
      0,
      blobOut,
    );
    if (ok == 0 || blobOut.ref.pbData == nullptr) return null;
    return Uint8List.fromList(
      blobOut.ref.pbData.asTypedList(blobOut.ref.cbData),
    );
  } catch (_) {
    return null;
  } finally {
    if (blobOut.ref.pbData != nullptr) {
      localFree(blobOut.ref.pbData.cast<Void>());
    }
    malloc
      ..free(blobIn)
      ..free(blobOut)
      ..free(input);
  }
}

// ---------------------------------------------------------------------------
// macOS (Keychain + AES-128-CBC)
// ---------------------------------------------------------------------------

Future<Uint8List?> _decryptMac(Uint8List raw) async {
  // Formato do OSCrypt no macOS: "v10" + ciphertext (sem nonce/tag).
  final cipherText = raw.sublist(3);
  final password = await _macSafeStoragePassword();
  if (password == null) return null;
  try {
    final keyBytes = await _macDeriveKey(password);
    final clear = await AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
        .decrypt(
          SecretBox(
            cipherText,
            nonce: List<int>.filled(16, 0x20),
            mac: Mac.empty,
          ),
          secretKey: SecretKey(keyBytes),
        );
    return Uint8List.fromList(clear);
  } catch (_) {
    return null;
  }
}

Future<String?> _macSafeStoragePassword() async {
  for (final service in const [
    'Claude Safe Storage',
    'Claude Code Safe Storage',
  ]) {
    try {
      final result = await Process.run('security', [
        'find-generic-password',
        '-s',
        service,
        '-w',
      ]);
      if (result.exitCode == 0) {
        final value = result.stdout.toString().trim();
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
  }
  return null;
}

Future<List<int>> _macDeriveKey(String password) async {
  // Chromium/Electron no macOS: PBKDF2-HMAC-SHA1, 1003 iterações, 16 bytes.
  final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha1(), iterations: 1003, bits: 128);
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: utf8.encode('saltysalt'),
  );
  return key.extractBytes();
}
