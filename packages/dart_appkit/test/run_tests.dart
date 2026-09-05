import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_appkit/src/api.dart';
import 'package:dart_appkit/testing.dart' as testing;

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
  _expect(
    bindings.requestedMinimumEventProtocolVersion == 1 &&
        bindings.requestedMaximumEventProtocolVersion == 4 &&
        app.eventProtocolVersion == 4,
    'current event protocol negotiation',
  );

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

Future<void> _testGenericViewBoundary() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final View genericView = View();
  final View customView = View.custom('example.CustomView');
  final TextView textView = TextView()..text = 'specialized';
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 320, 200),
    title: 'Generic view',
  )..contentView = genericView;

  _expect(window.contentView == genericView, 'generic view attachment');
  _expect(
    bindings.objects[bindings.contentViews.values.single] ==
        FakeObjectKind.view,
    'generic native kind',
  );

  window.contentView = customView;
  _expect(
    window.contentView == customView,
    'registered custom view attachment',
  );
  _expect(
    bindings.customViewProviders.values.single == 'example.CustomView',
    'custom provider identifier forwarded',
  );
  final Uint8List operationPayload = Uint8List.fromList(<int>[1, 2, 3, 4]);
  customView.performCustomOperation(operationPayload);
  operationPayload[0] = 9;
  _expect(
    bindings.customViewOperations.values.single.single[0] == 1,
    'custom view operation copies its opaque payload',
  );
  await _expectThrows<AppKitNativeException>(
    () => genericView.performCustomOperation(Uint8List(0)),
  );

  window.contentView = textView;
  _expect(window.contentView == textView, 'text view is a View');
  _expect(
    bindings.objects[bindings.contentViews.values.single] ==
        FakeObjectKind.textView,
    'specialized view attachment',
  );
  _expect(bindings.attachedFinalizers.length == 4, 'all handles finalized');

  genericView.dispose();
  customView.dispose();
  textView.dispose();
  window.dispose();
  _expect(bindings.objects.isEmpty, 'generic view objects released');
  await app.terminate();
  await raw.close();
}

Future<void> _testKeyEventRoutingPolicy() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 320, 200),
    title: 'Key routing',
  );
  final int handle = bindings.objects.keys.single;

  _expect(
    window.keyEventRouting == KeyEventRouting.dartAndAppKit &&
        bindings.windowKeyEventRoutings[handle] == 0,
    'window defaults to Dart and AppKit key routing',
  );

  window.keyEventRouting = KeyEventRouting.dartOnly;
  _expect(
    window.keyEventRouting == KeyEventRouting.dartOnly &&
        bindings.windowKeyEventRoutings[handle] == 1,
    'Dart-only key routing reaches native window',
  );
  final int callsAfterChange = bindings.operations
      .where((String value) => value == 'windowSetKeyEventRouting')
      .length;
  window.keyEventRouting = KeyEventRouting.dartOnly;
  _expect(
    bindings.operations
            .where((String value) => value == 'windowSetKeyEventRouting')
            .length ==
        callsAfterChange,
    'unchanged key routing is not sent twice',
  );

  bindings.failNextOperation = 'windowSetKeyEventRouting';
  await _expectThrows<AppKitNativeException>(
    () => window.keyEventRouting = KeyEventRouting.dartAndAppKit,
  );
  _expect(
    window.keyEventRouting == KeyEventRouting.dartOnly &&
        bindings.windowKeyEventRoutings[handle] == 1,
    'failed routing update preserves Dart and native state',
  );

  window.keyEventRouting = KeyEventRouting.dartAndAppKit;
  _expect(
    bindings.windowKeyEventRoutings[handle] == 0,
    'dual routing can be restored',
  );
  window.dispose();
  await _expectThrows<StateError>(() => window.keyEventRouting);
  await _expectThrows<StateError>(
    () => window.keyEventRouting = KeyEventRouting.dartOnly,
  );
  await app.terminate();
  await raw.close();
}

Future<void> _testEventRoutingAndDecoding() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings()
    ..nextHandle = (7 << 32) | 1;
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
    ..add(<Object?>[2, 2, handle, 7, 200000, 0, 640.0, 480.0])
    ..add(<Object?>[
      2,
      10,
      handle,
      7,
      201001,
      0,
      1.5,
      2.5,
      1,
      ModifierKeys.controlBit,
      1,
    ])
    ..add(<Object?>[
      2,
      20,
      handle,
      7,
      202999,
      0,
      36,
      ModifierKeys.commandBit,
      false,
      '\n',
      '\n',
    ])
    ..add(<Object?>[2, 1, handle, 7, 203000, 0])
    ..add(<Object?>[99, 1, handle, 104])
    ..add(<Object?>[2, 1, handle])
    ..add(<Object?>[2, 1, handle, 8, 204000, 0])
    ..add(<Object?>[2, 1, handle, 7, -1, 0])
    ..add(<Object?>[2, 1, handle, 7, 204000, -1])
    ..add(<Object?>[2, 999, handle, 7, 204000, 0])
    ..add(<Object?>[2, 1, handle, 7, 204000, 0, 'trailing'])
    ..add(<Object?>[2, 2, handle, 7, 204000, 0, 'wide', 480.0]);

  _expect(appEvents.length == 8, 'application receives v1 and v2 events');
  _expect(windowEvents.length == 8, 'window receives v1 and v2 events');
  final WindowResizedEvent resized = appEvents[0] as WindowResizedEvent;
  _expect(resized.width == 800 && resized.height == 500, 'resize payload');
  final AppKitMouseEvent mouse = appEvents[1] as AppKitMouseEvent;
  _expect(mouse.modifiers.shift && mouse.modifiers.command, 'mouse modifiers');
  _expect(mouse.clickCount == 2, 'mouse click count');
  final AppKitKeyEvent key = appEvents[2] as AppKitKeyEvent;
  _expect(key.isRepeat && key.characters == 'é', 'key payload');
  final WindowResizedEvent versionTwo = appEvents[4] as WindowResizedEvent;
  _expect(
    versionTwo.protocolVersion == 2 &&
        versionTwo.sourceGeneration == 7 &&
        versionTwo.monotonicNanoseconds == 200000 &&
        versionTwo.monotonicMicros == 200 &&
        versionTwo.operationId == 0,
    'version 2 common metadata',
  );
  final WindowClosedEvent sourceCompatible = WindowClosedEvent(
    windowHandle: handle,
    monotonicMicros: 12,
  );
  _expect(
    sourceCompatible.protocolVersion == 1 &&
        sourceCompatible.monotonicNanoseconds == 12000,
    'legacy public event constructor defaults',
  );
  _expect(window.isClosed, 'close event updates window state');
  _expect(
    streamErrors.length == 8 &&
        streamErrors.every((Object error) => error is FormatException),
    'malformed and unsupported events are surfaced',
  );

  await appSubscription.cancel();
  await windowSubscription.cancel();
  window.dispose();
  await app.terminate();
  await raw.close();
}

Future<void> _testWindowStateEvents() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings()
    ..nextHandle = (7 << 32) | 1;
  final AppKitApplication app = await _attach(bindings, raw);
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 320, 200),
    title: 'State events',
  );
  final int handle = bindings.objects.keys.single;
  final List<AppKitEvent> appEvents = <AppKitEvent>[];
  final List<Object> streamErrors = <Object>[];
  var cachedStateWasCurrent = true;
  final StreamSubscription<AppKitEvent> appSubscription = app.events.listen((
    AppKitEvent event,
  ) {
    appEvents.add(event);
    switch (event) {
      case WindowFocusChangedEvent(:final isFocused):
        cachedStateWasCurrent &= window.isFocused == isFocused;
      case WindowVisibilityChangedEvent(:final isVisible):
        cachedStateWasCurrent &= window.isVisible == isVisible;
      case WindowOcclusionChangedEvent(:final isOccluded):
        cachedStateWasCurrent &= window.isOccluded == isOccluded;
      case WindowBackingScaleChangedEvent(:final backingScaleFactor):
        cachedStateWasCurrent &=
            window.backingScaleFactor == backingScaleFactor;
      case WindowScreenChangedEvent(:final screen):
        cachedStateWasCurrent &= window.screen == screen;
      case WindowClosedEvent() ||
          WindowCloseRequestedEvent() ||
          WindowResizedEvent() ||
          AppKitMouseEvent() ||
          AppKitKeyEvent() ||
          ApplicationEvent() ||
          MenuItemInvokedEvent():
        break;
    }
  }, onError: (Object error) => streamErrors.add(error));
  var focusCount = 0;
  var visibilityCount = 0;
  var occlusionCount = 0;
  var backingScaleCount = 0;
  var screenCount = 0;
  final List<StreamSubscription<WindowEvent>> subscriptions =
      <StreamSubscription<WindowEvent>>[
        window.onFocusChanged.listen(
          (WindowFocusChangedEvent event) => ++focusCount,
        ),
        window.onVisibilityChanged.listen(
          (WindowVisibilityChangedEvent event) => ++visibilityCount,
        ),
        window.onOcclusionChanged.listen(
          (WindowOcclusionChangedEvent event) => ++occlusionCount,
        ),
        window.onBackingScaleChanged.listen(
          (WindowBackingScaleChangedEvent event) => ++backingScaleCount,
        ),
        window.onScreenChanged.listen(
          (WindowScreenChangedEvent event) => ++screenCount,
        ),
      ];

  raw
    ..add(<Object?>[3, 3, handle, 7, 300000, 0, true])
    ..add(<Object?>[3, 4, handle, 7, 301000, 0, true])
    ..add(<Object?>[3, 5, handle, 7, 302000, 0, false])
    ..add(<Object?>[3, 6, handle, 7, 303000, 0, 2.0])
    ..add(<Object?>[
      3,
      7,
      handle,
      7,
      304000,
      0,
      true,
      55,
      -1920.0,
      0.0,
      1920.0,
      1080.0,
      -1920.0,
      25.0,
      1920.0,
      1055.0,
    ]);

  const AppKitScreen expectedScreen = AppKitScreen(
    displayId: 55,
    frame: Rect.fromLTWH(-1920, 0, 1920, 1080),
    visibleFrame: Rect.fromLTWH(-1920, 25, 1920, 1055),
  );
  _expect(window.isFocused, 'focus state cached');
  _expect(window.isVisible, 'visibility state cached');
  _expect(!window.isOccluded, 'occlusion state cached');
  _expect(window.backingScaleFactor == 2.0, 'backing scale cached');
  _expect(window.screen == expectedScreen, 'screen state cached');
  _expect(cachedStateWasCurrent, 'state updated before application observer');
  _expect(
    focusCount == 1 &&
        visibilityCount == 1 &&
        occlusionCount == 1 &&
        backingScaleCount == 1 &&
        screenCount == 1,
    'typed state streams',
  );

  raw.add(<Object?>[
    3,
    7,
    handle,
    7,
    305000,
    0,
    false,
    0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
  ]);
  _expect(window.screen == null, 'absent screen cached');
  _expect(screenCount == 2, 'absent screen event routed');
  _expect(appEvents.length == 6, 'all state events reach application');

  raw
    ..add(<Object?>[2, 3, handle, 7, 306000, 0, true])
    ..add(<Object?>[3, 3, handle, 7, 307000, 0, 'true'])
    ..add(<Object?>[3, 6, handle, 7, 308000, 0, 0.0])
    ..add(<Object?>[3, 6, handle, 7, 309000, 0, double.nan])
    ..add(<Object?>[
      3,
      7,
      handle,
      7,
      310000,
      0,
      true,
      0,
      0.0,
      0.0,
      100.0,
      100.0,
      0.0,
      0.0,
      100.0,
      100.0,
    ])
    ..add(<Object?>[
      3,
      7,
      handle,
      7,
      311000,
      0,
      false,
      0,
      1.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
      0.0,
    ])
    ..add(<Object?>[3, 7, handle, 7, 312000, 0, false, 0])
    ..add(<Object?>[
      3,
      7,
      handle,
      7,
      313000,
      0,
      true,
      55,
      double.infinity,
      0.0,
      100.0,
      100.0,
      0.0,
      0.0,
      100.0,
      100.0,
    ]);
  _expect(
    streamErrors.length == 8 &&
        streamErrors.every((Object error) => error is FormatException),
    'malformed state events are surfaced',
  );

  for (final StreamSubscription<WindowEvent> subscription in subscriptions) {
    await subscription.cancel();
  }
  await appSubscription.cancel();
  window.dispose();
  await app.terminate();
  await raw.close();
}

Future<void> _testLifecycleRequestEvents() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings()
    ..nextHandle = (7 << 32) | 1;
  final AppKitApplication app = await _attach(bindings, raw);
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 320, 200),
    title: 'Lifecycle events',
  );
  final int handle = bindings.objects.keys.single;

  var activeCount = 0;
  var reopenCount = 0;
  var terminationCount = 0;
  var closeRequestCount = 0;
  var activeStateWasCurrent = true;
  final List<AppKitEvent> events = <AppKitEvent>[];
  final List<Object> errors = <Object>[];
  final StreamSubscription<AppKitEvent> appEvents = app.events.listen((
    AppKitEvent event,
  ) {
    events.add(event);
    if (event case ApplicationActiveChangedEvent(:final isActive)) {
      activeStateWasCurrent &= app.isActive == isActive;
    }
  }, onError: (Object error) => errors.add(error));
  final StreamSubscription<ApplicationActiveChangedEvent> activeEvents = app
      .onActiveChanged
      .listen(
        (ApplicationActiveChangedEvent event) => ++activeCount,
        onError: (Object _) {},
      );
  final StreamSubscription<ApplicationReopenRequestedEvent> reopenEvents = app
      .onReopenRequested
      .listen(
        (ApplicationReopenRequestedEvent event) => ++reopenCount,
        onError: (Object _) {},
      );
  final StreamSubscription<ApplicationTerminateRequestedEvent>
  terminationEvents = app.onTerminateRequested.listen(
    (ApplicationTerminateRequestedEvent event) => ++terminationCount,
    onError: (Object _) {},
  );
  final StreamSubscription<WindowCloseRequestedEvent> closeEvents = window
      .onCloseRequested
      .listen((WindowCloseRequestedEvent event) => ++closeRequestCount);

  app.defersTerminationRequests = true;
  window.defersCloseRequests = true;
  _expect(
    bindings.applicationTerminationDeferral &&
        bindings.windowCloseDeferrals[handle] == true,
    'native lifecycle deferral enabled',
  );
  window.requestClose();
  _expect(
    bindings.windowCloseRequests.single == handle,
    'user-facing close requested',
  );

  raw
    ..add(<Object?>[4, 30, 0, 0, 400000, 0, true])
    ..add(<Object?>[4, 31, 0, 0, 401000, 0, false])
    ..add(<Object?>[4, 8, handle, 7, 402000, 41])
    ..add(<Object?>[4, 32, 0, 0, 403000, 42])
    ..add(<Object?>[4, 40, handle, 7, 404000, 0]);

  _expect(app.isActive && activeStateWasCurrent, 'active state cached first');
  _expect(
    activeCount == 1 &&
        reopenCount == 1 &&
        terminationCount == 1 &&
        closeRequestCount == 1,
    'typed lifecycle event streams',
  );
  _expect(events.length == 5, 'all lifecycle events reach application');
  final ApplicationReopenRequestedEvent reopen =
      events[1] as ApplicationReopenRequestedEvent;
  _expect(!reopen.hasVisibleWindows, 'reopen payload');
  final WindowCloseRequestedEvent close =
      events[2] as WindowCloseRequestedEvent;
  final ApplicationTerminateRequestedEvent termination =
      events[3] as ApplicationTerminateRequestedEvent;
  final MenuItemInvokedEvent menu = events[4] as MenuItemInvokedEvent;
  _expect(
    close.operationId == 41 &&
        termination.operationId == 42 &&
        termination.sourceHandle == 0 &&
        menu.menuItemHandle == handle,
    'version 4 source and operation metadata',
  );

  window.replyToCloseRequest(close, allow: false);
  app.replyToTerminationRequest(termination, allow: true);
  _expect(
    bindings.windowCloseReplyHandle == handle &&
        bindings.windowCloseReplyOperationId == 41 &&
        bindings.windowCloseReplyAllow == false,
    'window reply forwarded',
  );
  _expect(
    bindings.applicationTerminationReplyOperationId == 42 &&
        bindings.applicationTerminationReplyAllow == true,
    'application reply forwarded',
  );

  final Window other = Window(
    frame: const Rect.fromLTWH(0, 0, 100, 100),
    title: 'Other',
  );
  await _expectThrows<ArgumentError>(
    () => other.replyToCloseRequest(close, allow: true),
  );

  raw
    ..add(<Object?>[4, 30, handle, 7, 405000, 0, true])
    ..add(<Object?>[4, 1, 0, 0, 406000, 0])
    ..add(<Object?>[4, 8, handle, 7, 407000, 0])
    ..add(<Object?>[4, 30, 0, 0, 408000, 1, false])
    ..add(<Object?>[4, 32, 0, 0, 409000, 0])
    ..add(<Object?>[3, 30, 0, 0, 410000, 0, true])
    ..add(<Object?>[4, 40, 0, 0, 411000, 0]);
  _expect(
    errors.length == 7 &&
        errors.every((Object error) => error is FormatException),
    'malformed lifecycle events are surfaced',
  );

  window.defersCloseRequests = false;
  app.defersTerminationRequests = false;
  _expect(
    !bindings.applicationTerminationDeferral &&
        bindings.windowCloseDeferrals[handle] == false,
    'native lifecycle deferral disabled',
  );

  await activeEvents.cancel();
  await reopenEvents.cancel();
  await terminationEvents.cancel();
  await closeEvents.cancel();
  await appEvents.cancel();
  other.dispose();
  window.dispose();
  await app.terminate();
  await raw.close();
}

Future<void> _testPasteboardApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final Pasteboard pasteboard = app.generalPasteboard;
  _expect(
    identical(pasteboard, app.generalPasteboard),
    'general pasteboard wrapper is stable',
  );

  PasteboardTextSnapshot snapshot = pasteboard.readText();
  _expect(
    snapshot.text == null && snapshot.changeCount == 0,
    'absent text snapshot',
  );
  final int unicodeCount = pasteboard.writeText('A\u0000é — 日本語');
  _expect(unicodeCount == 1, 'write returns change count');
  snapshot = pasteboard.readText();
  _expect(
    snapshot.text == 'A\u0000é — 日本語' && snapshot.changeCount == 1,
    'unicode and embedded NUL round trip',
  );

  final int emptyCount = pasteboard.writeText('');
  snapshot = pasteboard.readText();
  _expect(
    snapshot.text == '' &&
        snapshot.changeCount == emptyCount &&
        pasteboard.changeCount == emptyCount,
    'empty text remains present',
  );
  final int clearCount = pasteboard.clear();
  snapshot = pasteboard.readText();
  _expect(
    snapshot.text == null && snapshot.changeCount == clearCount,
    'clear restores absent text',
  );

  bindings.failNextOperation = 'pasteboardReadText';
  final AppKitNativeException readError =
      await _expectThrows<AppKitNativeException>(pasteboard.readText);
  _expect(readError.status == 7, 'pasteboard read error retained');
  bindings.failNextOperation = 'pasteboardWriteText';
  await _expectThrows<AppKitNativeException>(
    () => pasteboard.writeText('unchanged'),
  );
  _expect(bindings.pasteboardText == null, 'failed write does not change fake');

  await app.terminate();
  await _expectThrows<StateError>(() => pasteboard.changeCount);
  await raw.close();
}

Future<void> _testMenuApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings()
    ..nextHandle = (9 << 32) | 1;
  final AppKitApplication app = await _attach(bindings, raw);

  final Menu mainMenu = Menu(title: 'Main');
  final Menu applicationMenu = Menu(title: 'Application');
  final MenuItem applicationItem = MenuItem(title: 'Application')
    ..submenu = applicationMenu;
  final MenuItem separator = MenuItem.separator();
  final MenuItem quit = MenuItem(
    title: 'Quit — 日本語',
    keyEquivalent: 'q',
    modifiers: const ModifierKeys(
      ModifierKeys.commandBit | ModifierKeys.shiftBit,
    ),
  );
  mainMenu.addItem(applicationItem);
  applicationMenu
    ..addItem(separator)
    ..addItem(quit);
  app.mainMenu = mainMenu;

  final int mainHandle = bindings.menuTitles.entries
      .singleWhere((MapEntry<int, String> entry) => entry.value == 'Main')
      .key;
  final int applicationMenuHandle = bindings.menuTitles.entries
      .singleWhere(
        (MapEntry<int, String> entry) => entry.value == 'Application',
      )
      .key;
  final int applicationItemHandle = bindings.menuItems.entries
      .singleWhere(
        (MapEntry<int, FakeMenuItemState> entry) =>
            entry.value.title == 'Application',
      )
      .key;
  final int quitHandle = bindings.menuItems.entries
      .singleWhere(
        (MapEntry<int, FakeMenuItemState> entry) =>
            entry.value.title.startsWith('Quit'),
      )
      .key;
  _expect(
    app.mainMenu == mainMenu && bindings.mainMenu == mainHandle,
    'main menu ownership and native attachment',
  );
  _expect(
    mainMenu.items.single == applicationItem &&
        applicationMenu.items.length == 2 &&
        applicationItem.submenu == applicationMenu &&
        bindings.submenus[applicationItemHandle] == applicationMenuHandle,
    'menu item and submenu ownership',
  );
  final FakeMenuItemState quitState = bindings.menuItems[quitHandle]!;
  _expect(
    quitState.keyEquivalent == 'q' &&
        quitState.modifiers ==
            ModifierKeys.commandBit | ModifierKeys.shiftBit &&
        separator.isSeparator,
    'menu metadata forwarded',
  );

  int appActionCount = 0;
  int itemActionCount = 0;
  final List<Object> actionErrors = <Object>[];
  final StreamSubscription<AppKitEvent> appEvents = app.events.listen((
    AppKitEvent event,
  ) {
    if (event is MenuItemInvokedEvent) {
      ++appActionCount;
    }
  }, onError: (Object error) => actionErrors.add(error));
  final StreamSubscription<MenuItemInvokedEvent> itemEvents = quit.onInvoked
      .listen((MenuItemInvokedEvent event) {
        _expect(event.menuItemHandle == quitHandle, 'item event identity');
        ++itemActionCount;
      });
  quit.performAction();
  _expect(
    bindings.performedMenuItems.single == quitHandle,
    'explicit action forwarded',
  );
  raw.add(<Object?>[4, 40, quitHandle, 9, 500000, 0]);
  _expect(
    appActionCount == 1 && itemActionCount == 1,
    'action reaches application and item streams',
  );
  raw.add(<Object?>[4, 40, quitHandle, 10, 500500, 0]);
  _expect(
    actionErrors.length == 1 && actionErrors.single is FormatException,
    'mismatched action generation is rejected',
  );

  quit.isEnabled = false;
  _expect(
    !quit.isEnabled && bindings.menuItemEnabled[quitHandle] == false,
    'disabled state forwarded',
  );
  await _expectThrows<StateError>(quit.performAction);
  quit.isEnabled = true;
  bindings.failNextOperation = 'menuItemSetEnabled';
  await _expectThrows<AppKitNativeException>(() => quit.isEnabled = false);
  _expect(quit.isEnabled, 'failed enabled update is not cached');
  await _expectThrows<StateError>(separator.performAction);
  await _expectThrows<StateError>(() => separator.submenu = applicationMenu);
  await _expectThrows<ArgumentError>(
    () => MenuItem(title: 'Invalid', modifiers: const ModifierKeys(1 << 20)),
  );

  bindings.failNextOperation = 'release';
  await _expectThrows<AppKitNativeException>(quit.dispose);
  _expect(!quit.isDisposed, 'failed item release preserves wrapper state');
  raw.add(<Object?>[4, 40, quitHandle, 9, 500750, 0]);
  _expect(
    appActionCount == 2 && itemActionCount == 2,
    'failed item release preserves routing',
  );
  quit.dispose();
  raw.add(<Object?>[4, 40, quitHandle, 9, 501000, 0]);
  _expect(
    appActionCount == 3 && itemActionCount == 2,
    'disposed item ignores a late routed action',
  );
  bindings.failNextOperation = 'release';
  await _expectThrows<AppKitNativeException>(mainMenu.dispose);
  _expect(
    app.mainMenu == mainMenu && !mainMenu.isDisposed,
    'failed main-menu release preserves attachment state',
  );
  mainMenu.dispose();
  _expect(
    app.mainMenu == null && bindings.mainMenu == null,
    'disposing the main menu clears attachment state',
  );

  await itemEvents.cancel();
  await appEvents.cancel();
  separator.dispose();
  applicationItem.dispose();
  applicationMenu.dispose();
  _expect(bindings.objects.isEmpty, 'all menu handles released');
  await app.terminate();
  await raw.close();
}

Future<void> _testLegacyProtocolSelection() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings()
    ..selectedEventProtocolVersion = 1;
  final AppKitApplication app = await _attach(bindings, raw);
  _expect(app.eventProtocolVersion == 1, 'legacy event protocol selected');
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 100, 100),
    title: 'Legacy lifecycle',
  );
  await _expectThrows<UnsupportedError>(
    () => app.defersTerminationRequests = true,
  );
  await _expectThrows<UnsupportedError>(
    () => window.defersCloseRequests = true,
  );
  await _expectThrows<UnsupportedError>(() => Menu(title: 'Unavailable'));
  window.dispose();
  await app.terminate();
  await raw.close();
}

Future<void> _testRawEventInjectionHooks() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings()
    ..nextHandle = (7 << 32) | 1;
  final AppKitApplication app = await _attach(bindings, raw);
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 100, 100),
    title: 'Fault injection',
  );
  final int handle = testing.nativeWindowHandleForTesting(window);
  var applicationEventCount = 0;
  var windowEventCount = 0;
  final List<Object> errors = <Object>[];
  final StreamSubscription<AppKitEvent> applicationEvents = app.events.listen((
    _,
  ) {
    ++applicationEventCount;
  }, onError: errors.add);
  final StreamSubscription<WindowEvent> windowEvents = window.events.listen((
    _,
  ) {
    ++windowEventCount;
  });

  window.dispose();
  window.dispose();
  testing.injectRawAppKitEventForTesting(app, <Object?>[
    4,
    1,
    handle,
    handle >> 32,
    1000,
    0,
  ]);
  _expect(
    applicationEventCount == 1 && windowEventCount == 0,
    'late event reaches no disposed owner',
  );
  testing.injectRawAppKitEventForTesting(app, 'malformed');
  _expect(
    errors.length == 1 && errors.single is FormatException,
    'malformed event is surfaced once',
  );
  testing.injectRawAppKitEventForTesting(app, <Object?>[
    4,
    30,
    0,
    0,
    2000,
    0,
    true,
  ]);
  _expect(
    applicationEventCount == 2 && app.isActive,
    'valid event is handled after malformed input',
  );

  await applicationEvents.cancel();
  await windowEvents.cancel();
  await app.terminate();
  await _expectThrows<StateError>(
    () => testing.injectRawAppKitEventForTesting(app, const <Object?>[]),
  );
  await raw.close();
}

Future<void> _testCrossApplicationGuard() async {
  final StreamController<Object?> rawOne = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindingsOne = FakeNativeBindings();
  final AppKitApplication appOne = await _attach(bindingsOne, rawOne);
  final TextView oldView = TextView();
  final Menu oldMenu = Menu(title: 'Old');
  final MenuItem oldItem = MenuItem(title: 'Old item');
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
  final Menu newMenu = Menu(title: 'New');
  final MenuItem newItem = MenuItem(title: 'New item');
  await _expectThrows<StateError>(() => newWindow.contentView = oldView);
  await _expectThrows<StateError>(() => newMenu.addItem(oldItem));
  await _expectThrows<StateError>(() => newItem.submenu = oldMenu);
  await _expectThrows<StateError>(() => appTwo.mainMenu = oldMenu);

  oldView.dispose();
  oldItem.dispose();
  oldMenu.dispose();
  newItem.dispose();
  newMenu.dispose();
  newWindow.dispose();
  await appTwo.terminate();
  await rawTwo.close();
}

Future<void> main() async {
  await _test('attach guards ABI and main thread', _testAttachGuards);
  await _test('resource lifecycle and native errors', _testLifecycleAndErrors);
  await _test(
    'generic and specialized view boundary',
    _testGenericViewBoundary,
  );
  await _test('key event routing policy', _testKeyEventRoutingPolicy);
  await _test(
    'event decoding and weak window routing',
    _testEventRoutingAndDecoding,
  );
  await _test(
    'window state event decoding and caching',
    _testWindowStateEvents,
  );
  await _test(
    'application and window lifecycle request events',
    _testLifecycleRequestEvents,
  );
  await _test('plain-text pasteboard snapshots', _testPasteboardApi);
  await _test('menu ownership and action routing', _testMenuApi);
  await _test('legacy event protocol selection', _testLegacyProtocolSelection);
  await _test('raw event fault injection hooks', _testRawEventInjectionHooks);
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
