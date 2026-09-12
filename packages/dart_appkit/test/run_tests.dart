import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_appkit/dart_appkit.dart';
import 'package:dart_appkit/src/native/native_bindings.dart'
    show
        NativeRect,
        NativeScreenSnapshot,
        dartAppKitSecureInputIndicatorAutomatic,
        dartAppKitSecureInputIndicatorManual,
        dartAppKitScreenSelectionMain,
        dartAppKitExternalUrlPolicyForbidCredentials,
        dartAppKitExternalUrlPolicyRequireAuthority,
        dartAppKitExternalUrlPolicyRequireHost,
        dartAppKitWindowCollectionBehaviorCanJoinAllSpaces,
        dartAppKitWindowCollectionBehaviorFullScreenAuxiliary,
        dartAppKitWindowCollectionBehaviorStationary,
        dartAppKitWindowCollectionBehaviorTransient,
        dartAppKitWindowLevelStatus,
        dartAppKitViewAutoresizingWidth;
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
  StreamController<Object?> rawEvents, {
  ExternalUrlPolicy? externalUrlPolicy,
}) {
  return testing.attachApplicationForTesting(
    bindings: bindings,
    events: rawEvents.stream,
    externalUrlPolicy: externalUrlPolicy,
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
        bindings.requestedMaximumEventProtocolVersion == 8 &&
        app.eventProtocolVersion == 8,
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
  _expect(
    view.configuration == const TextViewConfiguration() &&
        bindings.textViewConfigurations.values.single.isCompatibilityDefault,
    'text view compatibility default is explicit and stable',
  );
  _expect(bindings.windowTitles.values.single == 'Updated', 'title update');
  _expect(window.contentView == view, 'content-view Dart ownership');
  _expect(
    window.contentLayoutRect == const Rect.fromLTWH(0, 0, 640, 480),
    'window content layout query',
  );
  bindings.failNextOperation = 'windowGetContentLayoutRect';
  final AppKitNativeException contentLayoutError =
      await _expectThrows<AppKitNativeException>(
        () => window.contentLayoutRect,
      );
  _expect(
    contentLayoutError.status == 7 &&
        contentLayoutError.nativeMessage == 'injected native failure',
    'window content layout native failure',
  );
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

Future<void> _testGlobalHotKeyApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings()
    ..nextHandle = (9 << 32) | 1;
  final AppKitApplication app = await _attach(bindings, raw);
  const ModifierKeys modifiers = ModifierKeys(
    ModifierKeys.controlBit | ModifierKeys.commandBit,
  );
  final GlobalHotKey hotKey = GlobalHotKey(keyCode: 50, modifiers: modifiers);
  final int handle = testing.nativeGlobalHotKeyHandleForTesting(hotKey);
  var applicationPresses = 0;
  var resourcePresses = 0;
  final List<Object> errors = <Object>[];
  final StreamSubscription<AppKitEvent> applicationEvents = app.events.listen((
    AppKitEvent event,
  ) {
    if (event is GlobalHotKeyPressedEvent) applicationPresses++;
  }, onError: errors.add);
  final StreamSubscription<GlobalHotKeyPressedEvent> hotKeyEvents = hotKey
      .onPressed
      .listen((GlobalHotKeyPressedEvent event) => resourcePresses++);

  _expect(
    hotKey.keyCode == 50 &&
        hotKey.modifiers == modifiers &&
        bindings.globalHotKeys[handle] ==
            (keyCode: 50, modifiers: modifiers.bits) &&
        bindings.attachedFinalizers.length == 1,
    'exclusive global hot key owns the native registration',
  );
  final GlobalHotKeyRegistrationException conflict =
      await _expectThrows<GlobalHotKeyRegistrationException>(
        () => GlobalHotKey(keyCode: 50, modifiers: modifiers),
      );
  _expect(
    conflict.reason == GlobalHotKeyRegistrationFailure.conflict &&
        conflict.nativeStatus == dartAppKitStatusGlobalHotKeyConflict &&
        bindings.globalHotKeys.length == 1,
    'exclusive conflict is typed and retains the first registration',
  );

  bindings
    ..failNextOperation = 'globalHotKeyRegister'
    ..failureStatus = dartAppKitStatusGlobalHotKeyRegistrationFailed;
  final GlobalHotKeyRegistrationException systemFailure =
      await _expectThrows<GlobalHotKeyRegistrationException>(
        () => GlobalHotKey(keyCode: 49, modifiers: modifiers),
      );
  _expect(
    systemFailure.reason == GlobalHotKeyRegistrationFailure.systemFailure &&
        systemFailure.nativeStatus ==
            dartAppKitStatusGlobalHotKeyRegistrationFailed &&
        bindings.globalHotKeys.length == 1,
    'system registration failure is typed and leaves the old owner intact',
  );
  final GlobalHotKeyRegistrationException unsupported =
      await _expectThrows<GlobalHotKeyRegistrationException>(
        () => GlobalHotKey(keyCode: 128, modifiers: modifiers),
      );
  _expect(
    unsupported.reason == GlobalHotKeyRegistrationFailure.unsupportedKey,
    'unsupported virtual key code is a typed registration failure',
  );
  await _expectThrows<ArgumentError>(
    () => GlobalHotKey(keyCode: 50, modifiers: const ModifierKeys(0)),
  );
  await _expectThrows<ArgumentError>(
    () => GlobalHotKey(
      keyCode: 50,
      modifiers: const ModifierKeys(ModifierKeys.capsLockBit),
    ),
  );

  raw.add(<Object?>[8, 41, handle, 9, 900000, 0]);
  _expect(
    applicationPresses == 1 && resourcePresses == 1 && errors.isEmpty,
    'version 8 press reaches the application and its exact resource once',
  );
  raw.add(<Object?>[7, 41, handle, 9, 901000, 0]);
  _expect(
    errors.length == 1 && errors.single is FormatException,
    'older protocol cannot smuggle a global hot-key event',
  );

  hotKey.dispose();
  raw.add(<Object?>[8, 41, handle, 9, 902000, 0]);
  _expect(
    applicationPresses == 2 &&
        resourcePresses == 1 &&
        bindings.globalHotKeys.isEmpty &&
        bindings.attachedFinalizers.isEmpty,
    'late queued event reaches no disposed registration owner',
  );
  final GlobalHotKey replacement = GlobalHotKey(
    keyCode: 50,
    modifiers: modifiers,
  );
  _expect(
    testing.nativeGlobalHotKeyHandleForTesting(replacement) != handle,
    'released chord can be registered again with a fresh owner identity',
  );
  replacement.dispose();
  await hotKeyEvents.cancel();
  await applicationEvents.cancel();
  await app.terminate();
  await raw.close();

  final StreamController<Object?> legacyRaw =
      StreamController<Object?>.broadcast(sync: true);
  final FakeNativeBindings legacyBindings = FakeNativeBindings()
    ..selectedEventProtocolVersion = 7;
  final AppKitApplication legacy = await _attach(legacyBindings, legacyRaw);
  await _expectThrows<UnsupportedError>(
    () => GlobalHotKey(keyCode: 50, modifiers: modifiers),
  );
  _expect(
    !legacyBindings.operations.contains('globalHotKeyRegister'),
    'older negotiated event protocol refuses registration before allocation',
  );
  await legacy.terminate();
  await legacyRaw.close();
}

Future<void> _testSecureEventInputApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final SecureEventInput secureInput = SecureEventInput();
  final int handle = testing.nativeSecureEventInputHandleForTesting(
    secureInput,
  );
  _expect(bindings.secureEventInputOwner == handle, 'native secure owner');

  SecureEventInputSnapshot snapshot = secureInput.snapshot();
  _expect(!snapshot.desired, 'initial request disabled');
  _expect(!snapshot.ownedEnabled, 'initial reference not owned');
  secureInput.setDesired(true);
  secureInput.setDesired(true);
  _expect(bindings.secureEventInputEnableCount == 1, 'enable is idempotent');
  snapshot = secureInput.snapshot();
  _expect(snapshot.desired && snapshot.ownedEnabled, 'active request acquired');

  bindings.changeApplicationActive(false);
  snapshot = secureInput.snapshot();
  _expect(snapshot.desired, 'inactive app retains desire');
  _expect(!snapshot.ownedEnabled, 'inactive app yields owned reference');
  bindings.changeApplicationActive(true);
  _expect(bindings.secureEventInputEnableCount == 2, 'activation reacquires');

  final SecureEventInputException duplicate =
      await _expectThrows<SecureEventInputException>(SecureEventInput.new);
  _expect(
    duplicate.reason == SecureEventInputFailure.alreadyOwned,
    'duplicate owner has typed failure',
  );

  bindings
    ..failNextOperation = 'secureEventInputSetDesired'
    ..failureStatus = dartAppKitStatusSecureEventInputFailed
    ..failureMessage = 'injected OSStatus -50';
  final SecureEventInputException systemFailure =
      await _expectThrows<SecureEventInputException>(
        () => secureInput.setDesired(false),
      );
  _expect(
    systemFailure.reason == SecureEventInputFailure.systemFailure &&
        systemFailure.nativeStatus == dartAppKitStatusSecureEventInputFailed,
    'OS failure has typed result',
  );
  _expect(
    secureInput.snapshot().ownedEnabled,
    'failed disable retains ownership knowledge',
  );
  secureInput.setDesired(false);

  final View view = View();
  view.secureInputIndicatorState = SecureInputIndicatorState.automatic;
  _expect(
    bindings.secureInputIndicatorStates.values.single ==
        dartAppKitSecureInputIndicatorAutomatic,
    'automatic indicator reaches native view',
  );
  view.secureInputIndicatorState = SecureInputIndicatorState.manual;
  _expect(
    view.secureInputIndicatorState == SecureInputIndicatorState.manual &&
        bindings.secureInputIndicatorStates.values.single ==
            dartAppKitSecureInputIndicatorManual,
    'manual indicator is distinct and cached after success',
  );
  bindings.failNextOperation = 'viewSetSecureInputIndicator';
  await _expectThrows<AppKitNativeException>(
    () => view.secureInputIndicatorState = SecureInputIndicatorState.automatic,
  );
  _expect(
    view.secureInputIndicatorState == SecureInputIndicatorState.manual,
    'failed indication does not corrupt Dart state',
  );

  bindings.secureEventInputSystemEnabled = true;
  secureInput.dispose();
  _expect(
    bindings.secureEventInputSystemEnabled,
    'dispose leaves externally-owned system state untouched',
  );
  view.dispose();
  await app.terminate();
  await raw.close();
}

Future<void> _testGenericViewBoundary() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  const ViewConfiguration viewConfiguration = ViewConfiguration(
    acceptsFirstResponder: false,
    autoresizesHeight: false,
  );
  final TextViewConfiguration textConfiguration = TextViewConfiguration(
    view: const ViewConfiguration(
      acceptsFirstResponder: false,
      autoresizesWidth: false,
    ),
    font: TextViewFont.named('Menlo', size: 14),
    padding: const TextViewPadding(top: 1, right: 2, bottom: 3, left: 4),
    foregroundColor: TextViewColor.sRgb(
      red: 0.1,
      green: 0.2,
      blue: 0.3,
      alpha: 0.4,
    ),
    backgroundColor: TextViewColor.sRgb(red: 0.9, green: 0.8, blue: 0.7),
  );
  final View genericView = View(configuration: viewConfiguration);
  final View customView = View.custom('example.CustomView');
  final TextView textView = TextView(configuration: textConfiguration)
    ..text = 'specialized';
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
  final int genericHandle = bindings.viewConfigurations.keys.first;
  final int textHandle = bindings.textViewConfigurations.keys.single;
  _expect(
    genericView.viewConfiguration == viewConfiguration &&
        !bindings.viewConfigurations[genericHandle]!.acceptsFirstResponder &&
        bindings.viewConfigurations[genericHandle]!.autoresizingMask ==
            dartAppKitViewAutoresizingWidth,
    'base view configuration reaches the native boundary',
  );
  final configuredText = bindings.textViewConfigurations[textHandle]!;
  _expect(
    textView.viewConfiguration == textConfiguration.view &&
        textView.configuration == textConfiguration &&
        configuredText.fontKind == TextViewFontKind.named.index &&
        configuredText.fontWeight == TextViewFontWeight.regular.index &&
        configuredText.fontFamily == 'Menlo' &&
        configuredText.fontSize == 14 &&
        configuredText.paddingTop == 1 &&
        configuredText.paddingRight == 2 &&
        configuredText.paddingBottom == 3 &&
        configuredText.paddingLeft == 4 &&
        configuredText.foregroundColorKind == TextViewColorKind.sRgb.index &&
        configuredText.foregroundAlpha == 0.4 &&
        configuredText.backgroundColorKind == TextViewColorKind.sRgb.index,
    'text view font, padding, colors, and base behavior reach native',
  );
  _expect(
    customView.viewConfiguration == null,
    'custom view behavior remains provider-owned',
  );
  _expect(
    TextViewFont.maximumSize == 512 &&
        TextViewFont.maximumFamilyUtf8Bytes == 256 &&
        TextViewPadding.maximumExtent == 4096,
    'public text-view bounds are stable',
  );
  await _expectThrows<ArgumentError>(() => TextViewFont.named(''));
  await _expectThrows<ArgumentError>(() => TextViewFont.named('é' * 129));
  await _expectThrows<ArgumentError>(
    () => TextView(
      configuration: const TextViewConfiguration(
        font: TextViewFont.system(size: double.infinity),
      ),
    ),
  );
  await _expectThrows<ArgumentError>(
    () => TextView(
      configuration: const TextViewConfiguration(
        padding: TextViewPadding(left: 4097),
      ),
    ),
  );
  await _expectThrows<RangeError>(
    () => TextViewColor.sRgb(red: -0.1, green: 0, blue: 0),
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

Future<void> _testAttributedTextEditorApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final TextEditorConfiguration configuration = TextEditorConfiguration(
    view: const ViewConfiguration(acceptsFirstResponder: true),
    font: TextViewFont.named('Menlo', size: 13),
    padding: const TextViewPadding(top: 8, right: 9, bottom: 10, left: 11),
    foregroundColor: TextViewColor.sRgb(red: 0.8, green: 0.8, blue: 0.8),
    backgroundColor: TextViewColor.sRgb(red: 0.1, green: 0.1, blue: 0.1),
  );
  final TextEditor editor = TextEditor(configuration: configuration);
  final String text = 'theme = dark\n👻';
  final List<TextEditorStyleRun> styles = <TextEditorStyleRun>[
    TextEditorStyleRun(
      start: 0,
      length: 5,
      foregroundColor: TextViewColor.sRgb(red: 0.3, green: 0.6, blue: 1),
    ),
    TextEditorStyleRun(
      start: 8,
      length: 4,
      foregroundColor: TextViewColor.sRgb(red: 0.4, green: 0.9, blue: 0.5),
      underlineStyle: TextEditorUnderlineStyle.single,
      underlineColor: TextViewColor.sRgb(red: 1, green: 0.3, blue: 0.3),
    ),
  ];
  editor.setDocument(
    TextEditorDocument(
      text: text,
      selection: const TextEditorSelection(start: 8, length: 4),
      styleRuns: styles,
    ),
  );
  final TextEditorSnapshot initial = editor.snapshot;
  final int handle = bindings.textEditorConfigurations.keys.single;
  _expect(
    editor.configuration == configuration &&
        editor.viewConfiguration == configuration.view &&
        initial.text == text &&
        initial.selection == const TextEditorSelection(start: 8, length: 4) &&
        !initial.isEditable &&
        !initial.hasMarkedText &&
        bindings.textEditorStyleRuns[handle]!.length == 2 &&
        bindings.textEditorConfigurations[handle]!.presentation.fontFamily ==
            'Menlo',
    'atomic editor document/configuration did not reach native bindings',
  );

  final TextEditorLineHighlight lineHighlight = TextEditorLineHighlight(
    location: 13,
    color: TextViewColor.sRgb(red: 0.16, green: 0.19, blue: 0.25, alpha: 0.8),
  );
  editor.setLineHighlight(lineHighlight);
  _expect(
    editor.lineHighlight == lineHighlight &&
        bindings.textEditorLineHighlights[handle]!.location == 13 &&
        bindings.textEditorLineHighlights[handle]!.blue == 0.25,
    'editor line highlight did not reach native bindings',
  );

  editor
    ..isEditable = true
    ..setSelection(const TextEditorSelection(start: 13, length: 2));
  editor.scrollSelectionToVisible();
  final TextEditorSnapshot editable = editor.snapshot;
  _expect(
    editable.text == text &&
        editable.isEditable &&
        editable.selection == const TextEditorSelection(start: 13, length: 2) &&
        bindings.operations.contains('textEditorScrollSelectionToVisible') &&
        bindings.textEditorLineHighlights[handle]!.location == 13,
    'selection reveal changed editor state or missed native bindings',
  );
  final List<TextEditorStyleRun> replacement = <TextEditorStyleRun>[
    TextEditorStyleRun(
      start: 8,
      length: 4,
      foregroundColor: TextViewColor.sRgb(red: 1, green: 0.7, blue: 0.2),
    ),
  ];
  editor.setStyleRuns(replacement);
  _expect(
    editor.snapshot.text == text &&
        bindings.textEditorStyleRuns[handle]!.single.foregroundRed == 1 &&
        bindings.textEditorLineHighlights[handle]!.location == 13,
    'style-only update replaced editor text or line highlight',
  );

  await _expectThrows<RangeError>(
    () => editor.setSelection(const TextEditorSelection(start: 14)),
  );
  await _expectThrows<RangeError>(
    () => editor.setLineHighlight(
      const TextEditorLineHighlight(location: 14, color: TextViewColor.label()),
    ),
  );
  await _expectThrows<RangeError>(
    () => editor.setLineHighlight(
      const TextEditorLineHighlight(location: 16, color: TextViewColor.label()),
    ),
  );
  await _expectThrows<RangeError>(
    () => editor.setStyleRuns(<TextEditorStyleRun>[
      const TextEditorStyleRun(
        start: 8,
        length: 4,
        foregroundColor: TextViewColor.label(),
      ),
      const TextEditorStyleRun(
        start: 2,
        length: 2,
        foregroundColor: TextViewColor.label(),
      ),
    ]),
  );
  await _expectThrows<RangeError>(
    () => editor.setDocument(
      TextEditorDocument(
        text: text,
        styleRuns: const <TextEditorStyleRun>[
          TextEditorStyleRun(
            start: 13,
            length: 1,
            foregroundColor: TextViewColor.label(),
          ),
        ],
      ),
    ),
  );
  _expect(
    TextEditorLimits.maximumTextUtf8Bytes == 16 * 1024 * 1024 &&
        TextEditorLimits.maximumStyleRuns == 64 * 1024,
    'public editor bounds changed',
  );

  editor.setDocument(
    TextEditorDocument(
      text: text,
      selection: const TextEditorSelection(start: 0),
      styleRuns: replacement,
    ),
  );
  _expect(
    editor.lineHighlight == null &&
        bindings.textEditorLineHighlights[handle] == null,
    'document replacement retained a stale line highlight',
  );
  editor
    ..setLineHighlight(lineHighlight)
    ..setLineHighlight(null);
  _expect(
    editor.lineHighlight == null &&
        bindings.textEditorLineHighlights[handle] == null,
    'explicit line highlight clear did not reach native bindings',
  );

  editor.dispose();
  await _expectThrows<StateError>(() => editor.snapshot);
  await _expectThrows<StateError>(() => editor.scrollSelectionToVisible());
  _expect(bindings.objects.isEmpty, 'text editor handle leaked');
  await app.terminate();
  await raw.close();
}

Future<void> _testWindowConfigurationApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final Window defaultWindow = Window(
    frame: const Rect.fromLTWH(0, 0, 320, 200),
    title: 'Default style',
  );
  const WindowConfiguration borderless = WindowConfiguration(
    titled: false,
    closable: false,
    miniaturizable: false,
    resizable: false,
  );
  const WindowConfiguration documentStyle = WindowConfiguration(
    miniaturizable: false,
    resizable: false,
  );
  final Window borderlessWindow = Window(
    frame: const Rect.fromLTWH(10, 10, 320, 200),
    title: 'Borderless',
    configuration: borderless,
  );
  final Window documentWindow = Window(
    frame: const Rect.fromLTWH(20, 20, 320, 200),
    title: 'Document',
    configuration: documentStyle,
  );

  final List<int> styleMasks = bindings.windowStyleMasks.values.toList();
  _expect(
    styleMasks[0] == 0xf,
    'default style retains every compatibility bit',
  );
  _expect(
    styleMasks[1] == 0 && borderlessWindow.configuration == borderless,
    'borderless style is forwarded and cached',
  );
  _expect(styleMasks[2] == 0x3, 'individual style flags are forwarded');

  defaultWindow.dispose();
  borderlessWindow.dispose();
  documentWindow.dispose();
  await app.terminate();
  await raw.close();
}

Future<void> _testScreenAndWindowPresentationApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);

  final AppKitResolvedScreen main = app.resolveScreen(
    AppKitScreenSelection.main,
  );
  final AppKitResolvedScreen mouse = app.resolveScreen(
    AppKitScreenSelection.mouse,
  );
  final AppKitResolvedScreen menuBar = app.resolveScreen(
    AppKitScreenSelection.menuBar,
  );
  _expect(
    main.screen.displayId == 1 &&
        main.screen.visibleFrame == const Rect.fromLTWH(0, 25, 1440, 875) &&
        main.backingScaleFactor == 2,
    'main screen geometry and backing scale are projected',
  );
  _expect(
    mouse.screen.displayId == 2 &&
        mouse.screen.frame == const Rect.fromLTWH(-1920, 0, 1920, 1080) &&
        mouse.backingScaleFactor == 1,
    'mouse screen preserves negative global coordinates',
  );
  _expect(
    menuBar.screen.displayId == 3 &&
        menuBar.screen.frame == const Rect.fromLTWH(1440, -200, 2560, 1440),
    'menu-bar screen preserves independent global coordinates',
  );
  bindings.failNextOperation = 'applicationResolveScreen';
  await _expectThrows<AppKitNativeException>(
    () => app.resolveScreen(AppKitScreenSelection.main),
  );
  bindings.resolvedScreens[dartAppKitScreenSelectionMain] =
      const NativeScreenSnapshot(
        displayId: 0,
        frame: NativeRect(x: 0, y: 0, width: 1, height: 1),
        visibleFrame: NativeRect(x: 0, y: 0, width: 1, height: 1),
        backingScaleFactor: 1,
      );
  await _expectThrows<StateError>(
    () => app.resolveScreen(AppKitScreenSelection.main),
  );

  final Window window = Window(
    frame: const Rect.fromLTWH(0, 700, 800, 1),
    title: 'Presentation',
    configuration: const WindowConfiguration(
      titled: false,
      closable: false,
      miniaturizable: false,
      resizable: false,
    ),
  );
  const WindowPresentationConfiguration overlay =
      WindowPresentationConfiguration(
        level: WindowPresentationLevel.status,
        canJoinAllSpaces: true,
        fullScreenAuxiliary: true,
        stationary: true,
        transient: true,
      );
  window.presentationConfiguration = overlay;
  final int handle = bindings.objects.keys.single;
  final ({int level, int collectionBehaviorMask}) nativeConfiguration =
      bindings.windowPresentationConfigurations[handle]!;
  _expect(
    window.presentationConfiguration == overlay &&
        nativeConfiguration.level == dartAppKitWindowLevelStatus &&
        nativeConfiguration.collectionBehaviorMask ==
            dartAppKitWindowCollectionBehaviorCanJoinAllSpaces |
                dartAppKitWindowCollectionBehaviorFullScreenAuxiliary |
                dartAppKitWindowCollectionBehaviorStationary |
                dartAppKitWindowCollectionBehaviorTransient,
    'window level and Spaces behavior are projected exactly',
  );
  final int operationsAfterConfiguration = bindings.operations.length;
  window.presentationConfiguration = overlay;
  _expect(
    bindings.operations.length == operationsAfterConfiguration,
    'equivalent presentation configuration is deduplicated',
  );

  const Rect shown = Rect.fromLTWH(0, 200, 800, 500);
  window.present(
    startFrame: const Rect.fromLTWH(0, 700, 800, 1),
    targetFrame: shown,
    duration: const Duration(milliseconds: 200),
    makeKey: false,
  );
  final presentation = bindings.windowPresentations.single;
  _expect(
    window.frame == shown &&
        presentation.targetFrame.y == 200 &&
        presentation.durationSeconds == 0.2 &&
        !presentation.makeKey,
    'bounded presentation retains the target frame and focus choice',
  );
  const Rect hidden = Rect.fromLTWH(0, 699, 800, 1);
  window.hide(targetFrame: hidden);
  _expect(
    window.frame == hidden && bindings.windowHides.single.durationSeconds == 0,
    'zero-duration hide retains the window and applies its endpoint',
  );

  await _expectThrows<RangeError>(
    () => window.present(
      startFrame: hidden,
      targetFrame: shown,
      duration: const Duration(microseconds: -1),
    ),
  );
  await _expectThrows<RangeError>(
    () =>
        window.hide(targetFrame: hidden, duration: const Duration(seconds: 6)),
  );
  await _expectThrows<ArgumentError>(
    () => window.present(
      startFrame: const Rect.fromLTWH(0, 0, 0, 1),
      targetFrame: shown,
    ),
  );
  final Rect beforeFailedPresentation = window.frame;
  bindings.failNextOperation = 'windowPresent';
  await _expectThrows<AppKitNativeException>(
    () => window.present(startFrame: hidden, targetFrame: shown),
  );
  _expect(
    window.frame == beforeFailedPresentation,
    'failed presentation does not invent a target frame',
  );
  bindings.failNextOperation = 'windowSetPresentationConfiguration';
  await _expectThrows<AppKitNativeException>(
    () => window.presentationConfiguration =
        const WindowPresentationConfiguration(
          level: WindowPresentationLevel.floating,
        ),
  );
  _expect(
    window.presentationConfiguration == overlay,
    'failed presentation policy does not change the Dart cache',
  );

  window.dispose();
  _expect(
    bindings.windowPresentationConfigurations.isEmpty,
    'window release clears presentation ownership',
  );
  await app.terminate();
  await raw.close();
}

Future<void> _testWindowPresentationMetadataApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 320, 200),
    title: 'Metadata',
  );
  final WindowTabColor color = WindowTabColor(
    red: 0.25,
    green: 0.5,
    blue: 0.75,
    alpha: 0.8,
  );

  window
    ..representedFilePath = '/private/tmp/Project 日本語 😀'
    ..tabColor = color;
  _expect(
    window.representedFilePath == '/private/tmp/Project 日本語 😀' &&
        window.tabColor == color &&
        bindings.windowRepresentedFilePaths.values.single ==
            '/private/tmp/Project 日本語 😀' &&
        bindings.windowTabColors.values.single.join(',') == '0.25,0.5,0.75,0.8',
    'represented path and tab color are copied and cached',
  );
  final int operationCount = bindings.operations.length;
  window
    ..representedFilePath = '/private/tmp/Project 日本語 😀'
    ..tabColor = WindowTabColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.8);
  _expect(
    bindings.operations.length == operationCount,
    'equal window metadata updates are native no-ops',
  );
  final WindowTabAccessory accessory = WindowTabAccessory(
    color: color,
    width: 14,
    height: 6,
    shape: WindowTabAccessoryShape.rectangle,
  );
  window.tabAccessory = accessory;
  _expect(
    window.tabAccessory == accessory &&
        window.tabColor == color &&
        bindings.windowTabAccessories.values.single.join(',') == '0,14.0,6.0',
    'tab accessory size and shape are forwarded and cached',
  );

  await _expectThrows<ArgumentError>(() => window.representedFilePath = 'tmp');
  await _expectThrows<ArgumentError>(() => window.representedFilePath = '');
  await _expectThrows<ArgumentError>(
    () => window.representedFilePath = '/tmp/\u0000invalid',
  );
  await _expectThrows<ArgumentError>(
    () => window.representedFilePath = '/tmp/\ud800invalid',
  );
  await _expectThrows<ArgumentError>(
    () => window.representedFilePath =
        '/${List<String>.filled(4097, 'a').join()}',
  );
  await _expectThrows<RangeError>(
    () => WindowTabColor(red: double.nan, green: 0, blue: 0),
  );
  await _expectThrows<RangeError>(
    () => WindowTabColor(red: 0, green: 0, blue: 1.01),
  );
  await _expectThrows<RangeError>(
    () => WindowTabAccessory(color: color, width: 0),
  );
  await _expectThrows<RangeError>(
    () => WindowTabAccessory(color: color, height: 257),
  );
  _expect(
    window.representedFilePath == '/private/tmp/Project 日本語 😀' &&
        window.tabColor == color,
    'invalid updates leave cached metadata unchanged',
  );

  bindings.failNextOperation = 'windowSetRepresentedFilePath';
  await _expectThrows<AppKitNativeException>(
    () => window.representedFilePath = '/private/tmp/other',
  );
  bindings.failNextOperation = 'windowSetTabAccessory';
  await _expectThrows<AppKitNativeException>(
    () => window.tabColor = WindowTabColor(red: 1, green: 0, blue: 0),
  );
  _expect(
    window.representedFilePath == '/private/tmp/Project 日本語 😀' &&
        window.tabColor == color,
    'native failures leave cached metadata unchanged',
  );

  window
    ..representedFilePath = null
    ..tabColor = null;
  _expect(
    window.representedFilePath == null &&
        window.tabColor == null &&
        window.tabAccessory == null &&
        bindings.windowRepresentedFilePaths.isEmpty &&
        bindings.windowTabColors.isEmpty &&
        bindings.windowTabAccessories.isEmpty,
    'optional presentation metadata clears without extra handles',
  );
  window.dispose();
  await _expectThrows<StateError>(() => window.representedFilePath);
  await _expectThrows<StateError>(() => window.tabColor);
  await _expectThrows<StateError>(() => window.tabAccessory);
  await app.terminate();
  await raw.close();
}

Future<void> _testWindowFrameAndFullscreenApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings()
    ..nextHandle = (7 << 32) | 1;
  final AppKitApplication app = await _attach(bindings, raw);
  final Window window = Window(
    frame: const Rect.fromLTWH(20, 30, 640, 480),
    title: 'Placement',
  );
  final int handle = bindings.objects.keys.single;
  const Rect moved = Rect.fromLTWH(-1200, 80, 920, 580);

  final int beforeNoOp = bindings.operations.length;
  window.frame = window.frame;
  _expect(
    bindings.operations.length == beforeNoOp,
    'equal frame mutation is a native no-op',
  );
  window.frame = moved;
  _expect(
    window.frame == moved &&
        bindings.windowFrames[handle]!.join(',') == '-1200.0,80.0,920.0,580.0',
    'finite outer frame is copied and cached',
  );
  await _expectThrows<ArgumentError>(
    () => window.frame = const Rect.fromLTWH(0, 0, 0, 100),
  );
  await _expectThrows<ArgumentError>(
    () => window.frame = Rect.fromLTWH(double.nan, 0, 100, 100),
  );
  bindings.failNextOperation = 'windowSetFrame';
  await _expectThrows<AppKitNativeException>(
    () => window.frame = const Rect.fromLTWH(1, 2, 300, 200),
  );
  _expect(
    window.frame == moved,
    'native frame failure retains cached geometry',
  );

  window.setFullscreen(true);
  final int afterFullscreenRequest = bindings.operations.length;
  window.setFullscreen(true);
  _expect(
    !window.isFullscreen &&
        bindings.windowFullscreenStates[handle] == true &&
        bindings.operations.length == afterFullscreenRequest,
    'fullscreen request is deduplicated while observed state remains async',
  );
  raw.add(<Object?>[6, 15, handle, 7, 400000, 0, true]);
  _expect(window.isFullscreen, 'fullscreen completion updates cached state');
  window.setFullscreen(false);
  _expect(
    bindings.windowFullscreenStates[handle] == false,
    'fullscreen exit request reaches the native boundary',
  );
  bindings.failNextOperation = 'windowSetFullscreen';
  await _expectThrows<AppKitNativeException>(() => window.setFullscreen(true));
  _expect(window.isFullscreen, 'failed exit/request does not invent state');

  window.dispose();
  await _expectThrows<StateError>(() => window.frame);
  await _expectThrows<StateError>(() => window.setFullscreen(false));
  await app.terminate();
  await raw.close();
}

Future<void> _testNativeTabsSplitViewAndFocusApi() async {
  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final View first = View();
  final View second = View();
  final TextView third = TextView();
  final TwoPaneSplitView nested = TwoPaneSplitView(axis: SplitViewAxis.vertical)
    ..setChildren(first: second, second: third)
    ..setPosition(
      fraction: 0.75,
      firstMinimumExtent: 20,
      secondMinimumExtent: 30,
    );
  final TwoPaneSplitView root = TwoPaneSplitView(axis: SplitViewAxis.horizontal)
    ..setChildren(first: first, second: nested)
    ..setPosition(
      fraction: 0.4,
      firstMinimumExtent: 40,
      secondMinimumExtent: 50,
    );
  final Window window = Window(
    frame: const Rect.fromLTWH(0, 0, 640, 480),
    title: 'First tab',
  )..contentView = root;
  final Window secondWindow = Window(
    frame: const Rect.fromLTWH(0, 0, 640, 480),
    title: 'Second tab',
  );
  final Window thirdWindow = Window(
    frame: const Rect.fromLTWH(0, 0, 640, 480),
    title: 'Third tab',
  );

  final int rootHandle = bindings.splitViewAxes.entries
      .singleWhere((MapEntry<int, int> entry) => entry.value == 0)
      .key;
  final int nestedHandle = bindings.splitViewAxes.entries
      .singleWhere((MapEntry<int, int> entry) => entry.value == 1)
      .key;
  final List<int> leafHandles = bindings.objects.entries
      .where(
        (MapEntry<int, FakeObjectKind> entry) =>
            entry.value == FakeObjectKind.view ||
            entry.value == FakeObjectKind.textView,
      )
      .map((MapEntry<int, FakeObjectKind> entry) => entry.key)
      .toList(growable: false);
  _expect(
    root.axis == SplitViewAxis.horizontal &&
        nested.axis == SplitViewAxis.vertical &&
        identical(root.firstView, first) &&
        identical(root.secondView, nested) &&
        root.fraction == 0.4 &&
        root.firstMinimumExtent == 40 &&
        root.secondMinimumExtent == 50 &&
        bindings.splitViewChildren[rootHandle]?.last == nestedHandle &&
        bindings.splitViewChildren[nestedHandle]?.length == 2,
    'nested split view retains ordered children, axis, fraction, and minima',
  );

  bindings.splitViewFractions[rootHandle] = 0.625;
  _expect(
    root.refreshFraction() == 0.625 && root.fraction == 0.625,
    'split fraction refresh observes a native divider mutation',
  );
  bindings.failNextOperation = 'splitViewGetFraction';
  await _expectThrows<AppKitNativeException>(() => root.refreshFraction());
  _expect(
    root.fraction == 0.625,
    'failed split fraction refresh preserves the last observed value',
  );

  root.equalize();
  root.zoomedChild = SplitViewChild.second;
  _expect(
    root.fraction == 0.5 &&
        root.zoomedChild == SplitViewChild.second &&
        bindings.splitViewFractions[rootHandle] == 0.5 &&
        bindings.splitViewZoomedChildren[rootHandle] == 1,
    'split equalize and zoom reach the native binding',
  );
  root.zoomedChild = null;
  window.makeFirstResponder(third);
  final int windowHandle = bindings.contentViews.keys.single;
  _expect(
    bindings.firstResponders[windowHandle] == leafHandles.last,
    'an attached nested leaf can become explicit first responder',
  );
  await _expectThrows<AppKitNativeException>(
    () => thirdWindow.makeFirstResponder(third),
  );

  window
    ..addTabbedWindow(secondWindow)
    ..addTabbedWindow(thirdWindow);
  thirdWindow.selectTab();
  _expect(
    bindings.windowTabGroups.length == 1 &&
        bindings.windowTabGroups.single.length == 3 &&
        bindings.selectedTabWindows.values.single ==
            bindings.windowTabGroups.single.last,
    'native window tabs append in model order and select explicitly',
  );
  secondWindow.removeFromTabGroup();
  _expect(
    bindings.windowTabGroups.single.length == 2,
    'native window tab can detach without closing',
  );

  await _expectThrows<ArgumentError>(
    () => root.setChildren(first: first, second: first),
  );
  await _expectThrows<ArgumentError>(
    () => root.setPosition(fraction: double.nan),
  );
  await _expectThrows<ArgumentError>(
    () => root.setPosition(fraction: 0.5, firstMinimumExtent: -1),
  );
  final double previousFraction = root.fraction;
  bindings.failNextOperation = 'splitViewSetPosition';
  await _expectThrows<AppKitNativeException>(
    () => root.setPosition(fraction: 0.25),
  );
  _expect(
    root.fraction == previousFraction &&
        bindings.splitViewFractions[rootHandle] == previousFraction,
    'failed split mutation preserves Dart and fake-native state',
  );
  await _expectThrows<ArgumentError>(() => window.addTabbedWindow(window));

  thirdWindow.dispose();
  secondWindow.dispose();
  window.dispose();
  root.dispose();
  nested.dispose();
  third.dispose();
  second.dispose();
  first.dispose();
  // ignore: deprecated_member_use
  final SplitView compatibilitySplit = SplitView(
    axis: SplitViewAxis.horizontal,
  );
  _expect(
    compatibilitySplit.runtimeType == TwoPaneSplitView,
    'legacy SplitView name aliases the explicit two-pane helper',
  );
  compatibilitySplit.dispose();
  _expect(bindings.objects.isEmpty, 'tab and split resources release exactly');
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
  window.keyEventRouting = KeyEventRouting.appKitOnly;
  _expect(
    window.keyEventRouting == KeyEventRouting.appKitOnly &&
        bindings.windowKeyEventRoutings[handle] == 2,
    'AppKit-only routing reaches the native first-responder path',
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
    ..add(<Object?>[
      5,
      14,
      handle,
      7,
      203500,
      0,
      18.5,
      27.25,
      -1.5,
      8.75,
      true,
      4,
      1,
      false,
      ModifierKeys.shiftBit | ModifierKeys.optionBit,
    ])
    ..add(<Object?>[99, 1, handle, 104])
    ..add(<Object?>[2, 1, handle])
    ..add(<Object?>[2, 1, handle, 8, 204000, 0])
    ..add(<Object?>[2, 1, handle, 7, -1, 0])
    ..add(<Object?>[2, 1, handle, 7, 204000, -1])
    ..add(<Object?>[2, 999, handle, 7, 204000, 0])
    ..add(<Object?>[2, 1, handle, 7, 204000, 0, 'trailing'])
    ..add(<Object?>[2, 2, handle, 7, 204000, 0, 'wide', 480.0]);

  raw
    ..add(<Object?>[
      4,
      14,
      handle,
      7,
      204001,
      0,
      0.0,
      0.0,
      0.0,
      1.0,
      false,
      0,
      0,
      false,
      0,
    ])
    ..add(<Object?>[
      5,
      14,
      handle,
      7,
      204002,
      0,
      0.0,
      0.0,
      0.0,
      double.infinity,
      true,
      4,
      0,
      false,
      0,
    ])
    ..add(<Object?>[
      5,
      14,
      handle,
      7,
      204003,
      0,
      0.0,
      0.0,
      0.0,
      1.0,
      true,
      3,
      0,
      false,
      0,
    ]);

  _expect(appEvents.length == 9, 'application receives v1, v2, and v5 events');
  _expect(windowEvents.length == 9, 'window receives v1, v2, and v5 events');
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
  final AppKitScrollEvent scroll = appEvents[8] as AppKitScrollEvent;
  _expect(
    scroll.protocolVersion == 5 &&
        scroll.x == 18.5 &&
        scroll.y == 27.25 &&
        scroll.scrollingDeltaX == -1.5 &&
        scroll.scrollingDeltaY == 8.75 &&
        scroll.hasPreciseScrollingDeltas &&
        scroll.phase == AppKitScrollPhase.changed &&
        scroll.momentumPhase == AppKitScrollPhase.began &&
        !scroll.directionInvertedFromDevice &&
        scroll.modifiers.shift &&
        scroll.modifiers.option,
    'version 5 scroll payload',
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
    streamErrors.length == 11 &&
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
      case WindowFrameChangedEvent(:final frame):
        cachedStateWasCurrent &= window.frame == frame;
      case WindowFullscreenChangedEvent(:final isFullscreen):
        cachedStateWasCurrent &= window.isFullscreen == isFullscreen;
      case WindowClosedEvent() ||
          WindowCloseRequestedEvent() ||
          WindowResizedEvent() ||
          AppKitMouseEvent() ||
          AppKitScrollEvent() ||
          AppKitKeyEvent() ||
          ApplicationEvent() ||
          MenuItemInvokedEvent() ||
          GlobalHotKeyPressedEvent():
        break;
    }
  }, onError: (Object error) => streamErrors.add(error));
  var focusCount = 0;
  var visibilityCount = 0;
  var occlusionCount = 0;
  var backingScaleCount = 0;
  var screenCount = 0;
  var frameCount = 0;
  var fullscreenCount = 0;
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
        window.onFrameChanged.listen(
          (WindowFrameChangedEvent event) => ++frameCount,
        ),
        window.onFullscreenChanged.listen(
          (WindowFullscreenChangedEvent event) => ++fullscreenCount,
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
    ])
    ..add(<Object?>[6, 9, handle, 7, 304001, 0, -1200.0, 80.0, 920.0, 580.0])
    ..add(<Object?>[6, 15, handle, 7, 304002, 0, true]);

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
  _expect(
    window.frame == const Rect.fromLTWH(-1200, 80, 920, 580),
    'outer frame state cached',
  );
  _expect(window.isFullscreen, 'fullscreen state cached');
  _expect(cachedStateWasCurrent, 'state updated before application observer');
  _expect(
    focusCount == 1 &&
        visibilityCount == 1 &&
        occlusionCount == 1 &&
        backingScaleCount == 1 &&
        screenCount == 1 &&
        frameCount == 1 &&
        fullscreenCount == 1,
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
  _expect(appEvents.length == 8, 'all state events reach application');

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
    ])
    ..add(<Object?>[5, 9, handle, 7, 314000, 0, 0.0, 0.0, 100.0, 100.0])
    ..add(<Object?>[6, 9, handle, 7, 315000, 0, 0.0, 0.0, 0.0, 100.0])
    ..add(<Object?>[6, 15, handle, 7, 316000, 0, 1])
    ..add(<Object?>[6, 15, handle, 7, 317000, 0]);
  _expect(
    streamErrors.length == 12 &&
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
  var appearanceCount = 0;
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
    if (event case ApplicationAppearanceChangedEvent(:final appearance)) {
      activeStateWasCurrent &= app.effectiveAppearance == appearance;
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
  final StreamSubscription<ApplicationAppearanceChangedEvent> appearanceEvents =
      app.onAppearanceChanged.listen(
        (ApplicationAppearanceChangedEvent event) => ++appearanceCount,
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
  testing.requestApplicationTerminationForTesting(app);
  _expect(
    bindings.debugApplicationTerminationRequestCount == 1,
    'test-only application termination request forwarded',
  );
  window.requestClose();
  _expect(
    bindings.windowCloseRequests.single == handle,
    'user-facing close requested',
  );

  raw
    ..add(<Object?>[4, 30, 0, 0, 400000, 0, true])
    ..add(<Object?>[7, 33, 0, 0, 400500, 0, true])
    ..add(<Object?>[4, 31, 0, 0, 401000, 0, false])
    ..add(<Object?>[4, 8, handle, 7, 402000, 41])
    ..add(<Object?>[4, 32, 0, 0, 403000, 42])
    ..add(<Object?>[4, 40, handle, 7, 404000, 0]);

  _expect(app.isActive && activeStateWasCurrent, 'active state cached first');
  _expect(
    activeCount == 1 &&
        reopenCount == 1 &&
        terminationCount == 1 &&
        appearanceCount == 1 &&
        closeRequestCount == 1,
    'typed lifecycle event streams',
  );
  _expect(
    app.effectiveAppearance == AppKitAppearance.dark,
    'appearance state cached before observer',
  );
  _expect(events.length == 6, 'all lifecycle events reach application');
  final ApplicationReopenRequestedEvent reopen =
      events[2] as ApplicationReopenRequestedEvent;
  _expect(!reopen.hasVisibleWindows, 'reopen payload');
  final WindowCloseRequestedEvent close =
      events[3] as WindowCloseRequestedEvent;
  final ApplicationTerminateRequestedEvent termination =
      events[4] as ApplicationTerminateRequestedEvent;
  final MenuItemInvokedEvent menu = events[5] as MenuItemInvokedEvent;
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
    ..add(<Object?>[4, 40, 0, 0, 411000, 0])
    ..add(<Object?>[6, 33, 0, 0, 412000, 0, true])
    ..add(<Object?>[7, 33, 0, 0, 413000, 0, 1]);
  _expect(
    errors.length == 9 &&
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
  await appearanceEvents.cancel();
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
  _expect(
    Pasteboard.maximumTextUtf8Bytes == 64 * 1024 * 1024,
    'public pasteboard read bound is stable',
  );
  bindings.pasteboardTextUtf8LengthOverride =
      Pasteboard.maximumTextUtf8Bytes + 1;
  final AppKitNativeException limitError =
      await _expectThrows<AppKitNativeException>(pasteboard.readText);
  _expect(
    limitError.status == 10 && snapshot.text == 'A\u0000é — 日本語',
    'oversized text is rejected without publishing a partial snapshot',
  );
  bindings.pasteboardTextUtf8LengthOverride = null;

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

Future<void> _testExternalUrlApi() async {
  await _expectThrows<ArgumentError>(() => ExternalUrlSchemePolicy(scheme: ''));
  await _expectThrows<ArgumentError>(
    () => ExternalUrlSchemePolicy(scheme: '1invalid'),
  );
  await _expectThrows<ArgumentError>(
    () => ExternalUrlSchemePolicy(
      scheme: 'custom',
      allowsAuthority: false,
      requiresHost: true,
    ),
  );
  await _expectThrows<ArgumentError>(
    () => ExternalUrlPolicy(<ExternalUrlSchemePolicy>[
      ExternalUrlSchemePolicy(scheme: 'custom'),
      ExternalUrlSchemePolicy(scheme: 'CUSTOM'),
    ]),
  );

  final List<String> valid = <String>[
    'https://example.com/path?query=value#fragment',
    'HTTP://example.com/%20space',
    'mailto:user@example.com?subject=Hello%20there',
  ];
  for (final String source in valid) {
    final AllowedExternalUrl? parsed = AllowedExternalUrl.tryParse(source);
    _expect(parsed != null, 'allowlisted URL parses: $source');
    _expect(parsed!.value == source, 'validated URL preserves exact text');
    _expect(
      parsed.scheme == Uri.parse(source).scheme.toLowerCase(),
      'validated URL exposes lowercase scheme',
    );
  }
  _expect(
    AllowedExternalUrl.maximumUtf8Bytes == 4096,
    'public external URL bound is stable',
  );

  final List<String> invalid = <String>[
    '',
    'example.com/path',
    '//example.com/path',
    'file:///tmp/report',
    'javascript:alert(1)',
    'data:text/plain,hello',
    'custom:value',
    'https://user:password@example.com',
    'https:///missing-host',
    'http:example.com',
    'mailto:',
    'mailto://user@example.com',
    'https://example.com/line\nbreak',
    'https://example.com/back\\slash',
    'https://example.com/hidden\u202evalue',
    'https://example.com/%0dheader',
    'https://example.com/%5cpath',
    'https://example.com/%E2%80%AEvalue',
    'https://example.com/%zz',
    'https://example.com/\uD800',
    'https://example.com/${'a' * 4096}',
  ];
  for (final String source in invalid) {
    _expect(
      AllowedExternalUrl.tryParse(source) == null,
      'unsafe URL is rejected: ${source.length}',
    );
  }
  await _expectThrows<FormatException>(
    () => AllowedExternalUrl.parse('ssh://example.com'),
  );

  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final AllowedExternalUrl target = AllowedExternalUrl.parse(valid.first);
  _expect(app.openExternalUrl(target), 'accepted workspace open is true');
  final int defaultWebFlags =
      dartAppKitExternalUrlPolicyRequireAuthority |
      dartAppKitExternalUrlPolicyRequireHost |
      dartAppKitExternalUrlPolicyForbidCredentials;
  _expect(
    bindings.openedExternalUrls.length == 1 &&
        bindings.openedExternalUrls.single == target.value &&
        bindings.openedExternalUrlSchemes.single == 'https' &&
        bindings.openedExternalUrlPolicyFlags.single == defaultWebFlags,
    'validated URL and its policy reach native bindings',
  );
  bindings.externalUrlOpenResult = false;
  _expect(
    !app.openExternalUrl(AllowedExternalUrl.parse(valid.last)),
    'workspace refusal is a nonexceptional false result',
  );
  bindings.failNextOperation = 'applicationOpenExternalUrl';
  final AppKitNativeException nativeError =
      await _expectThrows<AppKitNativeException>(
        () => app.openExternalUrl(target),
      );
  _expect(nativeError.status == 7, 'native URL-open error retained');

  await app.terminate();
  await _expectThrows<StateError>(() => app.openExternalUrl(target));
  await raw.close();

  final ExternalUrlPolicy customPolicy = ExternalUrlPolicy(
    <ExternalUrlSchemePolicy>[
      ExternalUrlSchemePolicy(
        scheme: 'ssh',
        requiresAuthority: true,
        requiresHost: true,
        allowsCredentials: true,
      ),
      ExternalUrlSchemePolicy(scheme: 'file', requiresPath: true),
      ExternalUrlSchemePolicy(
        scheme: 'custom',
        allowsAuthority: false,
        requiresPath: true,
      ),
    ],
  );
  _expect(
    AllowedExternalUrl.tryParse(
          'ssh://user@example.com/path',
          policy: customPolicy,
        ) !=
        null,
    'custom policy can allow credentials for a host scheme',
  );
  _expect(
    AllowedExternalUrl.tryParse('ssh:/path', policy: customPolicy) == null,
    'custom authority requirement is enforced',
  );
  _expect(
    AllowedExternalUrl.tryParse('file:///tmp/report', policy: customPolicy) !=
        null,
    'custom policy can allow file URLs',
  );
  _expect(
    AllowedExternalUrl.tryParse('custom:value', policy: customPolicy) != null,
    'custom non-authority scheme is accepted',
  );
  _expect(
    AllowedExternalUrl.tryParse('custom://value', policy: customPolicy) == null,
    'forbidden authority is rejected',
  );
  _expect(
    AllowedExternalUrl.tryParse('custom:unsafe\nvalue', policy: customPolicy) ==
        null,
    'library structural safety remains mandatory',
  );

  final StreamController<Object?> customRaw =
      StreamController<Object?>.broadcast(sync: true);
  final FakeNativeBindings customBindings = FakeNativeBindings();
  final AppKitApplication customApp = await _attach(
    customBindings,
    customRaw,
    externalUrlPolicy: customPolicy,
  );
  await _expectThrows<ArgumentError>(() => customApp.openExternalUrl(target));
  final AllowedExternalUrl customTarget = AllowedExternalUrl.parse(
    'ssh://user@example.com/path',
    policy: customPolicy,
  );
  _expect(customApp.openExternalUrl(customTarget), 'custom URL opens');
  _expect(
    customBindings.openedExternalUrlSchemes.single == 'ssh' &&
        customBindings.openedExternalUrlPolicyFlags.single ==
            (dartAppKitExternalUrlPolicyRequireAuthority |
                dartAppKitExternalUrlPolicyRequireHost),
    'application revalidates and forwards its attached custom policy',
  );
  await customApp.terminate();
  await customRaw.close();
}

Future<void> _testUserNotificationAndDockBadgeApi() async {
  await _expectThrows<ArgumentError>(
    () => AppKitUserNotification(identifier: '', title: 'title', body: ''),
  );
  await _expectThrows<ArgumentError>(
    () => AppKitUserNotification(
      identifier: 'invalid/id',
      title: 'title',
      body: '',
    ),
  );
  await _expectThrows<ArgumentError>(
    () => AppKitUserNotification(identifier: 'valid-id', title: '', body: ''),
  );
  await _expectThrows<ArgumentError>(
    () => AppKitUserNotification(
      identifier: 'valid-id',
      title: 'unsafe\u202evalue',
      body: '',
    ),
  );
  await _expectThrows<ArgumentError>(
    () => AppKitUserNotification(
      identifier: 'valid-id',
      title: 'x' * (AppKitUserNotification.maximumTextUtf8Bytes + 1),
      body: '',
    ),
  );

  final StreamController<Object?> raw = StreamController<Object?>.broadcast(
    sync: true,
  );
  final FakeNativeBindings bindings = FakeNativeBindings();
  final AppKitApplication app = await _attach(bindings, raw);
  final AppKitUserNotification notification = AppKitUserNotification(
    identifier: 'pane-4-session-2-notification-1',
    title: 'Build complete',
    body: 'The bounded task finished.',
  );
  app.postUserNotification(notification);
  _expect(
    bindings.postedUserNotifications.single ==
        (
          identifier: notification.identifier,
          title: notification.title,
          body: notification.body,
        ),
    'immutable notification payload reaches native bindings exactly once',
  );
  app.dockBadgeLabel = '73%';
  app.dockBadgeLabel = '73%';
  _expect(
    app.dockBadgeLabel == '73%' &&
        bindings.dockBadgeLabel == '73%' &&
        bindings.operations
                .where(
                  (String operation) =>
                      operation == 'applicationSetDockBadgeLabel',
                )
                .length ==
            1,
    'Dock badge caches and suppresses duplicate native updates',
  );
  app.dockBadgeLabel = '';
  _expect(
    app.dockBadgeLabel == null && bindings.dockBadgeLabel == null,
    'empty Dock badge input canonicalizes to clear',
  );
  await _expectThrows<ArgumentError>(() => app.dockBadgeLabel = 'x' * 33);
  app.removeUserNotification(notification.identifier);
  _expect(
    bindings.removedUserNotifications.single == notification.identifier,
    'notification removal keeps the exact validated identity',
  );

  bindings.failNextOperation = 'applicationPostUserNotification';
  final AppKitNativeException postError =
      await _expectThrows<AppKitNativeException>(
        () => app.postUserNotification(notification),
      );
  _expect(
    postError.status == 7 && bindings.postedUserNotifications.length == 1,
    'failed native submission does not mutate fake notification state',
  );
  bindings.failNextOperation = 'applicationSetDockBadgeLabel';
  await _expectThrows<AppKitNativeException>(() => app.dockBadgeLabel = '9%');
  _expect(
    app.dockBadgeLabel == null && bindings.dockBadgeLabel == null,
    'failed Dock update does not publish a Dart or fake cache value',
  );

  await app.terminate();
  await _expectThrows<StateError>(() => app.postUserNotification(notification));
  await _expectThrows<StateError>(
    () => app.removeUserNotification(notification.identifier),
  );
  await _expectThrows<StateError>(() => app.dockBadgeLabel = '1%');
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
  final Menu automaticMenu = Menu(
    title: 'Automatic',
    configuration: const MenuConfiguration(autoEnablesItems: true),
  );
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
  final int automaticMenuHandle = bindings.menuTitles.entries
      .singleWhere((MapEntry<int, String> entry) => entry.value == 'Automatic')
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
    mainMenu.configuration == const MenuConfiguration() &&
        bindings.menuAutoEnablesItems[mainHandle] == false &&
        automaticMenu.configuration.autoEnablesItems &&
        bindings.menuAutoEnablesItems[automaticMenuHandle] == true,
    'menu auto-enablement is explicit and reaches native creation',
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
  quit.isChecked = true;
  _expect(
    quit.isChecked && bindings.menuItemChecked[quitHandle] == true,
    'checked state forwarded',
  );
  bindings.failNextOperation = 'menuItemSetChecked';
  await _expectThrows<AppKitNativeException>(() => quit.isChecked = false);
  _expect(quit.isChecked, 'failed checked update is not cached');
  quit.isChecked = false;
  bindings.failNextOperation = 'menuItemSetEnabled';
  await _expectThrows<AppKitNativeException>(() => quit.isEnabled = false);
  _expect(quit.isEnabled, 'failed enabled update is not cached');
  await _expectThrows<StateError>(separator.performAction);
  await _expectThrows<StateError>(() => separator.isChecked = true);
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
  automaticMenu.dispose();
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
  final Window oldWindow = Window(
    frame: const Rect.fromLTWH(0, 0, 100, 100),
    title: 'Old window',
  );
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
  final TwoPaneSplitView newSplit = TwoPaneSplitView(
    axis: SplitViewAxis.horizontal,
  );
  final View newView = View();
  await _expectThrows<StateError>(() => newWindow.contentView = oldView);
  await _expectThrows<StateError>(
    () => newSplit.setChildren(first: oldView, second: newView),
  );
  await _expectThrows<StateError>(() => newWindow.makeFirstResponder(oldView));
  await _expectThrows<StateError>(() => newWindow.addTabbedWindow(oldWindow));
  await _expectThrows<StateError>(() => newMenu.addItem(oldItem));
  await _expectThrows<StateError>(() => newItem.submenu = oldMenu);
  await _expectThrows<StateError>(() => appTwo.mainMenu = oldMenu);

  oldView.dispose();
  oldWindow.dispose();
  oldItem.dispose();
  oldMenu.dispose();
  newItem.dispose();
  newMenu.dispose();
  newSplit.dispose();
  newView.dispose();
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
  await _test('attributed multiline text editor', _testAttributedTextEditorApi);
  await _test('immutable window configuration', _testWindowConfigurationApi);
  await _test(
    'current screen and animated window presentation',
    _testScreenAndWindowPresentationApi,
  );
  await _test(
    'native tabs, split views, and explicit focus',
    _testNativeTabsSplitViewAndFocusApi,
  );
  await _test(
    'window represented path and native-tab color',
    _testWindowPresentationMetadataApi,
  );
  await _test(
    'window frame and asynchronous fullscreen state',
    _testWindowFrameAndFullscreenApi,
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
  await _test('exclusive global hot-key ownership', _testGlobalHotKeyApi);
  await _test(
    'balanced Secure Event Input ownership and indication',
    _testSecureEventInputApi,
  );
  await _test('plain-text pasteboard snapshots', _testPasteboardApi);
  await _test('allowlisted external URL opening', _testExternalUrlApi);
  await _test(
    'bounded user notification and Dock badge API',
    _testUserNotificationAndDockBadgeApi,
  );
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
