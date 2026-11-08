import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ProcessResultData {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ProcessResultData({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get ok => exitCode == 0;
}

abstract class ProcessRunner {
  Future<ProcessResultData> run(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<ProcessSession> start(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
  });
}

abstract class ProcessSession {
  Stream<String> get stdoutLines;
  Stream<String> get stderrLines;
  void writeLine(String line);
  Future<int> get exitCode;
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]);
  Future<void> close();
}

class DartProcessRunner implements ProcessRunner {
  const DartProcessRunner();

  @override
  Future<ProcessResultData> run(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final result = await Process.run(
      executable,
      args,
      environment: environment,
      runInShell: false,
    ).timeout(timeout);
    return ProcessResultData(
      exitCode: result.exitCode,
      stdout: result.stdout?.toString() ?? '',
      stderr: result.stderr?.toString() ?? '',
    );
  }

  @override
  Future<ProcessSession> start(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      args,
      environment: environment,
      runInShell: false,
    );
    return DartProcessSession(process);
  }
}

class DartProcessSession implements ProcessSession {
  final Process _process;
  late final Stream<String> _stdout;
  late final Stream<String> _stderr;

  DartProcessSession(this._process) {
    _stdout = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    _stderr = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
  }

  @override
  Stream<String> get stdoutLines => _stdout;

  @override
  Stream<String> get stderrLines => _stderr;

  @override
  void writeLine(String line) {
    _process.stdin.writeln(line);
  }

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process.kill(signal);

  @override
  Future<void> close() async {
    try {
      _process.kill(ProcessSignal.sigterm);
    } catch (_) {}
    try {
      await _process.stdin.close();
    } catch (_) {}
  }
}
