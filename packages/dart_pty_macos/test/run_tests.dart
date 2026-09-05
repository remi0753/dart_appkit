import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_pty_macos/dart_pty_macos.dart';
import 'package:dart_pty_macos/testing.dart';

typedef TestBody = FutureOr<void> Function();

var _failures = 0;

@Native<Uint32 Function()>(
  symbol: 'dpty_abi_version',
  assetId: 'package:dart_pty_macos/dart_pty_macos.dart',
)
external int _abiVersion();

@Native<Uint64 Function()>(
  symbol: 'dpty_debug_live_session_count',
  assetId: 'package:dart_pty_macos/dart_pty_macos.dart',
)
external int _liveSessionCount();

Future<void> _test(String name, TestBody body) async {
  try {
    await body();
    stdout.writeln('PASS $name');
  } on Object catch (error, stackTrace) {
    ++_failures;
    stderr.writeln('FAIL $name: $error');
    stderr.writeln(stackTrace);
  }
}

void _expect(bool condition, String description) {
  if (!condition) {
    throw StateError('expectation failed: $description');
  }
}

T _expectThrows<T extends Object>(void Function() body) {
  try {
    body();
  } on Object catch (error) {
    if (error is T) {
      return error;
    }
    throw StateError('expected $T but caught ${error.runtimeType}');
  }
  throw StateError('expected $T but no error was thrown');
}

Future<void> main() async {
  await _test('public command and queue validation', () async {
    _expectThrows<ArgumentError>(() => PtyCommand(executable: 'zsh'));
    _expectThrows<ArgumentError>(
      () => PtyCommand(
        executable: '/bin/zsh',
        environment: <String, String>{'BAD=KEY': 'value'},
      ),
    );
    final FakePtyBackend backend = FakePtyBackend();
    await _expectThrowsAsync<ArgumentError>(() {
      return startPty(
        PtyCommand(executable: '/bin/sh'),
        backend: backend,
        readHighWaterBytes: 10,
        readLowWaterBytes: 10,
      );
    });
  });

  await _test('deterministic fake backend lifecycle', () async {
    final FakePtyBackend backend = FakePtyBackend(autoExitOnClose: false);
    final PtyCommand command = PtyCommand(
      executable: '/bin/zsh',
      arguments: const <String>['-f', '-i'],
      environment: const <String, String>{'TERM': 'xterm-256color'},
      workingDirectory: '/private/tmp',
      loginShell: true,
    );
    final PtyProcess process = await startPty(
      command,
      backend: backend,
      initialSize: const PtySize(rows: 30, columns: 100),
      writeCapacityBytes: 4,
    );
    final FakePtyProcess fake = backend.processes.single;
    final List<int> output = <int>[];
    final StreamSubscription<Uint8List> subscription = process.output.listen(
      output.addAll,
    );
    _expect(process.pid == 4000, 'fake PID');
    _expect(identical(backend.commands.single, command), 'command recorded');
    _expect(
      process.write(Uint8List.fromList(<int>[1, 2, 3, 4])) ==
          PtyWriteResult.accepted,
      'bounded write accepted',
    );
    _expect(
      process.write(Uint8List.fromList(<int>[5])) ==
          PtyWriteResult.backpressured,
      'bounded write rejects overflow',
    );
    fake.drainWrites();
    process.resize(const PtySize(rows: 43, columns: 132));
    process.sendSignal(PtySignal.interrupt);
    fake.emitOutput(<int>[0xe2]);
    fake.emitOutput(<int>[0x82, 0xac]);
    process.close(gracePeriod: const Duration(milliseconds: 250));
    fake.finish(exitCode: 37);
    final PtyExit exit = await process.exit;
    await subscription.cancel();
    await process.dispose();
    _expect(exit.exitCode == 37 && exit.signal == null, 'fake exit');
    _expect(output.length == 3, 'raw split bytes are preserved');
    _expect(fake.sizes.last.rows == 43, 'resize recorded');
    _expect(fake.signals.single == PtySignal.interrupt, 'signal recorded');
    _expect(
      fake.closeGracePeriods.single == const Duration(milliseconds: 250),
      'close grace recorded',
    );
    _expect(process.finalStats?.hasExited ?? false, 'fake stats finalized');
  });

  await _test('fake force close remains valid while closing', () async {
    final FakePtyBackend backend = FakePtyBackend(
      autoExitOnClose: false,
      autoExitOnForceClose: false,
    );
    final PtyProcess process = await startPty(
      PtyCommand(executable: '/bin/sh'),
      backend: backend,
    );
    final FakePtyProcess fake = backend.processes.single;
    process.close(gracePeriod: const Duration(seconds: 60));
    process.forceClose();
    process.forceClose();
    _expect(
      fake.forceCloseRequests == 2,
      'repeated force requests are accepted after graceful close',
    );
    fake.finish(exitCode: 137, signal: 9);
    final PtyExit exit = await process.exit;
    process.forceClose();
    await process.dispose();
    _expect(
      fake.forceCloseRequests == 2,
      'force close is a no-op after process completion',
    );
    _expect(
      exit.exitCode == 137 && exit.signal == 9,
      'fake forced exit is preserved',
    );
  });

  await _test('real Dart listener callback and process lifecycle', () async {
    _expect(_abiVersion() == 2, 'native asset ABI');
    final PtyProcess process = await startPty(
      PtyCommand(
        executable: '/bin/sh',
        arguments: const <String>[
          '-c',
          'printf "__DPTY_DART__%s:%s" "\$DPTY_DART_ENV" "\$PWD"; exit 9',
        ],
        environment: const <String, String>{'DPTY_DART_ENV': 'ok'},
        includeParentEnvironment: false,
        workingDirectory: '/private/tmp',
      ),
      readHighWaterBytes: 128 * 1024,
      readLowWaterBytes: 64 * 1024,
      writeCapacityBytes: 64 * 1024,
    );
    final Future<List<int>> outputFuture = process.output
        .expand<int>((Uint8List bytes) => bytes)
        .toList();
    final PtyExit exit = await process.exit.timeout(const Duration(seconds: 4));
    final String output = utf8.decode(await outputFuture);
    _expect(exit.exitCode == 9 && exit.signal == null, 'real exit code');
    _expect(
      output.contains('__DPTY_DART__ok:/private/tmp'),
      'environment and cwd cross the native callback boundary',
    );
    _expect(process.finalStats?.hasExited ?? false, 'real stats finalized');
    await process.dispose();
    _expect(_liveSessionCount() == 0, 'real native session is released');
  });

  await _test(
    'real force close bypasses an active graceful deadline',
    () async {
      final PtyProcess process = await startPty(
        PtyCommand(
          executable: '/bin/sh',
          arguments: const <String>[
            '-c',
            "trap '' HUP TERM; printf __DPTY_DART_FORCE__; while :; do sleep 1; done",
          ],
          includeParentEnvironment: false,
        ),
      );
      final StringBuffer output = StringBuffer();
      final Completer<void> ready = Completer<void>();
      final StreamSubscription<Uint8List> subscription = process.output.listen((
        Uint8List bytes,
      ) {
        output.write(utf8.decode(bytes, allowMalformed: true));
        if (!ready.isCompleted &&
            output.toString().contains('__DPTY_DART_FORCE__')) {
          ready.complete();
        }
      });
      await ready.future.timeout(const Duration(seconds: 3));
      process.close(gracePeriod: const Duration(seconds: 60));
      final Stopwatch elapsed = Stopwatch()..start();
      process.forceClose();
      process.forceClose();
      final PtyExit exit = await process.exit.timeout(
        const Duration(seconds: 3),
      );
      elapsed.stop();
      process.forceClose();
      await subscription.cancel();
      await process.dispose();
      _expect(
        exit.exitCode == 137 && exit.signal == 9,
        'real explicit force close reports SIGKILL',
      );
      _expect(
        elapsed.elapsed < const Duration(seconds: 2),
        'real explicit force close bypasses the 60 second grace period',
      );
      _expect(_liveSessionCount() == 0, 'force-closed session is released');
    },
  );

  await _test('explicit bundled-library loading', () async {
    final Uri packageLibrary = (await Isolate.resolvePackageUri(
      Uri.parse('package:dart_pty_macos/dart_pty_macos.dart'),
    ))!;
    final String libraryPath = File.fromUri(packageLibrary).parent.parent
        .childDirectory('.dart_tool')
        .childDirectory('lib')
        .childFile('libdart_pty_macos.dylib')
        .path;
    final MacosPtyBackend backend = MacosPtyBackend.open(libraryPath);
    final PtyProcess process = await backend.start(
      PtyCommand(
        executable: '/bin/sh',
        arguments: const <String>['-c', 'printf __DPTY_DYNAMIC__; exit 4'],
        includeParentEnvironment: false,
      ),
    );
    final Future<List<int>> outputFuture = process.output
        .expand<int>((Uint8List bytes) => bytes)
        .toList();
    final PtyExit exit = await process.exit.timeout(const Duration(seconds: 4));
    _expect(exit.exitCode == 4, 'dynamic backend exit code');
    _expect(
      utf8.decode(await outputFuture).contains('__DPTY_DYNAMIC__'),
      'dynamic backend output',
    );
    await process.dispose();
    _expect(_liveSessionCount() == 0, 'dynamic native session is released');
  });

  await _test('real asynchronous exec failure', () async {
    await _expectThrowsAsync<PtyException>(() {
      return startPty(
        PtyCommand(
          executable: '/definitely/missing/dpty',
          includeParentEnvironment: false,
        ),
      );
    });
    _expect(_liveSessionCount() == 0, 'failed native session is released');
  });

  if (_failures != 0) {
    exitCode = 1;
  }
}

extension on Directory {
  Directory childDirectory(String name) =>
      Directory(uri.resolve('$name/').toFilePath());

  File childFile(String name) => File(uri.resolve(name).toFilePath());
}

Future<T> _expectThrowsAsync<T extends Object>(
  Future<void> Function() body,
) async {
  try {
    await body();
  } on Object catch (error) {
    if (error is T) {
      return error;
    }
    throw StateError('expected $T but caught ${error.runtimeType}: $error');
  }
  throw StateError('expected $T but no error was thrown');
}
