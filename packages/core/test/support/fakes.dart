import 'dart:async';
import 'dart:io';

import 'package:quota_deck_core/quota_deck_core.dart';

class FakeProcessRunner implements ProcessRunner {
  final Map<String, ProcessResultData> results;
  final Map<String, ProcessSession> sessions;

  FakeProcessRunner({
    Map<String, ProcessResultData>? results,
    Map<String, ProcessSession>? sessions,
  }) : results = results ?? {},
       sessions = sessions ?? {};

  String _key(String executable, List<String> args) =>
      '$executable ${args.join(' ')}'.trim();

  @override
  Future<ProcessResultData> run(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return results[_key(executable, args)] ??
        const ProcessResultData(exitCode: 1, stdout: '', stderr: 'not found');
  }

  @override
  Future<ProcessSession> start(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
  }) async {
    final session = sessions[_key(executable, args)];
    if (session == null) {
      throw ProcessException(executable, args, 'not found');
    }
    return session;
  }
}

class FakeProcessSession implements ProcessSession {
  final _out = StreamController<String>.broadcast();
  final _err = StreamController<String>.broadcast();
  final _exit = Completer<int>();
  final List<String> written = [];

  void emit(String line) => _out.add(line);
  void emitError(String line) => _err.add(line);
  void finish([int code = 0]) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<String> get stdoutLines => _out.stream;

  @override
  Stream<String> get stderrLines => _err.stream;

  @override
  void writeLine(String line) => written.add(line);

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    finish(143);
    return true;
  }

  @override
  Future<void> close() async {
    finish();
    await _out.close();
    await _err.close();
  }
}
