import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Instância única via socket loopback: a segunda execução pede foco e sai.
class SingleInstance {
  SingleInstance({this.port = 47831, this.onShow});

  final int port;
  final Future<void> Function()? onShow;

  ServerSocket? _server;

  Future<bool> acquire() async {
    try {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      _server = server;
      server.listen((client) async {
        try {
          final data = await client
              .map((chunk) => utf8.decode(chunk))
              .join()
              .timeout(const Duration(seconds: 2));
          if (data.contains('qdeck:show')) {
            await onShow?.call();
          }
        } catch (_) {
        } finally {
          client.destroy();
        }
      });
      return true;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> notifyExisting() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.write('qdeck:show');
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    try {
      await _server?.close();
    } catch (_) {}
  }
}
