import 'dart:async';
import 'dart:io';

import 'package:dart_appkit/src/api.dart';

import 'fake_native_bindings.dart';

typedef TestBody = FutureOr<void> Function();

int _failures = 0;

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

Future<T> _expectThrows<T extends Object>(
  FutureOr<void> Function() body,
) async {
  try {
    await body();
  } on Object catch (error) {
    if (error is T) {
      return error;
    }
    throw StateError('expected $T but caught ${error.runtimeType}: $error');
  }
  throw StateError('expected $T but no exception was thrown');
}

Future<AppKitApplication> _attach(
  FakeNativeBindings bindings,
  StreamController<Object?> rawEvents,
) {
  return attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
  );
}

Future<void> _testAttachGuards() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings badAbi = FakeNativeBindings()
    ..reportedAbiVersion = 99;
  final AppKitInitializationException abiError =
      await _expectThrows<AppKitInitializationException>(
        () => _attach(badAbi, raw),
      );
  _expect(abiError.message.contains('ABI version 99'), 'ABI mismatch detail');

  final FakeNativeBindings wrongThread = FakeNativeBindings()
    ..mainThreadValue = 0;
  final AppKitInitializationException threadError =
      await _expectThrows<AppKitInitializationException>(
        () => _attach(wrongThread, raw),
      );
  _expect(threadError.message.contains('main thread'), 'main-thread mismatch');
  await raw.close();
}

Future<void> _testLifecycleAndErrors() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  _expect(bindings.eventPort == 4242, 'native event port registration');

  final TextView view = TextView()..text = 'Hello — 日本語';
  final Window window = Window(
    frame: const Rect.fromLTWH(20, 30, 640, 480),
    title: 'Initial',
  )..contentView = view;
  window
    ..title = 'Updated'
    ..show()
    ..close();

  _expect(bindings.objects.length == 2, 'two live native objects');
  _expect(bindings.texts.values.single == 'Hello — 日本語', 'UTF-8 text');
  _expect(bindings.windowTitles.values.single == 'Updated', 'title update');
  _expect(window.contentView == view, 'content-view Dart ownership');
  _expect(app.debugLiveObjectCount == 2, 'debug live count');
  _expect(bindings.attachedFinalizers.length == 2, 'finalizers attached');

  bindings.failNextOperation = 'windowSetTitle';
  final AppKitNativeException nativeError =
      await _expectThrows<AppKitNativeException>(() => window.title = 'fails');
  _expect(nativeError.status == 7, 'native status retained');
  _expect(
    nativeError.nativeMessage == 'injected native failure',
    'native detail retained',
  );

  view.dispose();
  view.dispose();
  await _expectThrows<StateError>(() => view.text = 'after dispose');
  window.dispose();
  window.dispose();
  _expect(bindings.objects.isEmpty, 'all native objects released');
  _expect(bindings.attachedFinalizers.isEmpty, 'finalizers detached');

  await app.terminate();
  await app.terminate();
  _expect(bindings.terminateCalled, 'native terminate requested');
  await raw.close();
}

Future<void> _testEventRoutingAndDecoding() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 320, 200),
    title: 'Events',
  );
  final int handle = bindings.objects.keys.single;

  final List<AppKitEvent> appEvents = <AppKitEvent>[];
  final List<WindowEvent> windowEvents = <WindowEvent>[];
  final List<Object> streamErrors = <Object>[];
  final StreamSubscription<AppKitEvent> appSubscription = app.events.listen(
    appEvents.add,
    onError: (Object error) => streamErrors.add(error),
  );
  final StreamSubscription<WindowEvent> windowSubscription = window.events
      .listen(windowEvents.add);

  raw
    ..add(<Object?>[1, 2, handle, 100, 800.0, 500.0])
    ..add(<Object?>[
      1,
      10,
      handle,
      101,
      12.5,
      20.5,
      0,
      ModifierKeys.shiftBit | ModifierKeys.commandBit,
      2,
    ])
    ..add(<Object?>[
      1,
      20,
      handle,
      102,
      14,
      ModifierKeys.optionBit,
      true,
      'é',
      'e',
    ])
    ..add(<Object?>[1, 1, handle, 103])
    ..add(<Object?>[99, 1, handle, 104]);

  _expect(appEvents.length == 4, 'application receives four valid events');
  _expect(windowEvents.length == 4, 'window receives four valid events');
  final WindowResizedEvent resized = appEvents[0] as WindowResizedEvent;
  _expect(resized.width == 800 && resized.height == 500, 'resize payload');
  final AppKitMouseEvent mouse = appEvents[1] as AppKitMouseEvent;
  _expect(mouse.modifiers.shift && mouse.modifiers.command, 'mouse modifiers');
  _expect(mouse.clickCount == 2, 'mouse click count');
  final AppKitKeyEvent key = appEvents[2] as AppKitKeyEvent;
  _expect(key.isRepeat && key.characters == 'é', 'key payload');
  _expect(window.isClosed, 'close event updates window state');
  _expect(
    streamErrors.single is FormatException,
    'malformed event is surfaced',
  );

  await appSubscription.cancel();
  await windowSubscription.cancel();
  window.dispose();
  await app.terminate();
  await raw.close();
}

Future<void> _testCrossApplicationGuard() async {
  final StreamController<Object?> rawOne = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindingsOne = FakeNativeBindings();
  final AppKitApplication appOne = await _attach(bindingsOne, rawOne);
  final TextView oldView = TextView();
  await appOne.terminate();
  await rawOne.close();

  final StreamController<Object?> rawTwo = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindingsTwo = FakeNativeBindings();
  final AppKitApplication appTwo = await _attach(bindingsTwo, rawTwo);
  final Window newWindow = Window(
    frame: const Rect.fromLTWH(0, 0, 100, 100),
    title: 'Second',
  );
  await _expectThrows<StateError>(() => newWindow.contentView = oldView);

  oldView.dispose();
  newWindow.dispose();
  await appTwo.terminate();
  await rawTwo.close();
}

Future<void> main() async {
  await _test('attach guards ABI and main thread', _testAttachGuards);
  await _test('resource lifecycle and native errors', _testLifecycleAndErrors);
  await _test(
    'event decoding and weak window routing',
    _testEventRoutingAndDecoding,
  );
  await _test(
    'cross-application content view guard',
    _testCrossApplicationGuard,
  );

  if (_failures != 0) {
    stderr.writeln('$_failures Dart API test(s) failed');
    exitCode = 1;
    return;
  }
  stdout.writeln('all Dart API tests passed');
}
