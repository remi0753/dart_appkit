import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

typedef _NativeThreadProbe = IntPtr Function();

int _isMainThread(int address) {
  return Pointer<NativeFunction<_NativeThreadProbe>>.fromAddress(address)
      .asFunction<int Function()>()();
}

@pragma('vm:entry-point', 'call')
int publicHostSynchronousProbe() => 42;

@pragma('vm:entry-point', 'call')
String publicHostPlatformScriptProbe() => Platform.script.toString();

@pragma('vm:entry-point', 'call')
void publicHostMicrotaskProbe(SendPort report) {
  scheduleMicrotask(() {
    report.send(<Object?>['microtask', 'completed']);
  });
}

@pragma('vm:entry-point', 'call')
Future<void> publicHostLifecycleProbe(
  SendPort report,
  int threadProbeAddress,
) async {
  try {
    await Future<void>.microtask(() {});
    final List<Object?> normal = await Isolate.run<List<Object?>>(() async {
      await Future<void>.microtask(() {});
      return <Object?>[
        Platform.script.toString(),
        _isMainThread(threadProbeAddress),
      ];
    }, debugName: 'dart-appkit-public-host-normal');

    final ReceivePort faultErrors = ReceivePort();
    final ReceivePort faultExit = ReceivePort();
    await Isolate.spawn<void>(
      _faultWorker,
      null,
      debugName: 'dart-appkit-public-host-fault',
      errorsAreFatal: true,
      onError: faultErrors.sendPort,
      onExit: faultExit.sendPort,
    );
    final Object? fault = await faultErrors.first;
    await faultExit.first;
    faultErrors.close();
    faultExit.close();

    final ReceivePort forcedReady = ReceivePort();
    final ReceivePort forcedExit = ReceivePort();
    final Isolate forced = await Isolate.spawn<SendPort>(
      _idleWorker,
      forcedReady.sendPort,
      debugName: 'dart-appkit-public-host-forced',
      onExit: forcedExit.sendPort,
    );
    await forcedReady.first;
    forcedReady.close();
    forced.kill(priority: Isolate.immediate);
    await forcedExit.first;
    forcedExit.close();

    final String replacement = await Isolate.run<String>(() async {
      await Future<void>.microtask(() {});
      return 'replacement:${Platform.script}';
    }, debugName: 'dart-appkit-public-host-replacement');

    final ReceivePort liveReady = ReceivePort();
    _liveWorker = await Isolate.spawn<SendPort>(
      _idleWorker,
      liveReady.sendPort,
      debugName: 'dart-appkit-public-host-live-at-cleanup',
    );
    await liveReady.first;
    liveReady.close();

    report.send(<Object?>[
      'lifecycle',
      'ok',
      normal.first,
      normal.last,
      fault.toString(),
      replacement,
      _isMainThread(threadProbeAddress),
      _liveWorker!.debugName ?? 'unnamed-live-worker',
    ]);
  } on Object catch (error, stackTrace) {
    report.send(<Object?>['lifecycle', 'error', '$error', '$stackTrace']);
  }
}

Isolate? _liveWorker;

@pragma('vm:entry-point')
Future<void> _faultWorker(void _) async {
  await Future<void>.microtask(() {});
  throw StateError('intentional public-host worker failure');
}

@pragma('vm:entry-point')
void _idleWorker(SendPort ready) {
  final ReceivePort keepAlive = ReceivePort();
  ready.send(null);
  keepAlive.listen((Object? _) {});
}

void main() {}
