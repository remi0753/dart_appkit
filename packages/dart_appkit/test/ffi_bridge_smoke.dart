import 'dart:ffi';
import 'dart:io';

import 'package:dart_appkit/src/native/ffi_native_bindings.dart';
import 'package:dart_appkit/src/native/native_bindings.dart';

typedef _ReleaseAsyncNative = Int32 Function(Uint64);
typedef _ReleaseAsyncDart = int Function(int);

Never _fail(String message) {
  stderr.writeln('FFI bridge smoke test failed: $message');
  exit(1);
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    _fail('expected one bridge dylib path');
  }

  final FfiNativeBindings bindings = FfiNativeBindings.open(arguments.single);
  if (bindings.abiVersion() != dartAppKitAbiVersion) {
    _fail('ABI version mismatch');
  }
  final _ReleaseAsyncDart releaseAsync = DynamicLibrary.open(
    arguments.single,
  ).lookupFunction<_ReleaseAsyncNative, _ReleaseAsyncDart>('da_release_async');
  if (releaseAsync(0) != 3) {
    _fail('asynchronous release symbol did not reject an invalid handle');
  }

  final NativeValueResult<int> eventRegistration = bindings
      .applicationSetEventPortVersioned(
        port: 4242,
        minimumVersion: dartAppKitMinimumEventProtocolVersion,
        maximumVersion: dartAppKitCurrentEventProtocolVersion,
      );
  if (eventRegistration.isSuccess ||
      (eventRegistration.status != 5 && eventRegistration.status != 6) ||
      eventRegistration.message.isEmpty) {
    _fail('versioned event registration did not reach the native bridge');
  }

  final NativeValueResult<int> threadResult = bindings.debugIsMainThread();
  if (!threadResult.isSuccess ||
      (threadResult.value != 0 && threadResult.value != 1)) {
    _fail('invalid main-thread probe result');
  }
  final NativeValueResult<int> pasteboardCount = bindings
      .pasteboardGetChangeCount();
  if (pasteboardCount.isSuccess ||
      pasteboardCount.status != 5 ||
      pasteboardCount.message.isEmpty) {
    _fail('pasteboard symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> externalUrl = bindings
      .applicationOpenExternalUrl(
        'https://example.com',
        scheme: 'https',
        policyFlags:
            dartAppKitExternalUrlPolicyRequireAuthority |
            dartAppKitExternalUrlPolicyRequireHost |
            dartAppKitExternalUrlPolicyForbidCredentials,
      );
  if (externalUrl.isSuccess ||
      externalUrl.status != 5 ||
      externalUrl.message.isEmpty) {
    _fail('external URL symbol did not preserve its main-thread guard');
  }
  final NativeCallResult userNotification = bindings
      .applicationPostUserNotification(
        identifier: 'ffi-smoke-1',
        title: 'Smoke',
        body: 'Main-thread guard',
      );
  if (userNotification.isSuccess ||
      userNotification.status != 5 ||
      userNotification.message.isEmpty) {
    _fail('user notification symbol did not preserve its main-thread guard');
  }
  final NativeCallResult notificationRemoval = bindings
      .applicationRemoveUserNotification('ffi-smoke-1');
  if (notificationRemoval.isSuccess ||
      notificationRemoval.status != 5 ||
      notificationRemoval.message.isEmpty) {
    _fail('notification removal did not preserve its main-thread guard');
  }
  final NativeCallResult dockBadge = bindings.applicationSetDockBadgeLabel(
    '1%',
  );
  if (dockBadge.isSuccess ||
      dockBadge.status != 5 ||
      dockBadge.message.isEmpty) {
    _fail('Dock badge symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> globalHotKey = bindings.globalHotKeyRegister(
    keyCode: 79,
    modifiers: 1 << 4,
  );
  if (globalHotKey.isSuccess ||
      globalHotKey.status != 5 ||
      globalHotKey.message.isEmpty) {
    _fail('global hot-key symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> secureInput = bindings.secureEventInputCreate();
  final NativeCallResult secureIndicator = bindings.viewSetSecureInputIndicator(
    1,
    dartAppKitSecureInputIndicatorAutomatic,
  );
  if (secureInput.isSuccess ||
      secureInput.status != 5 ||
      secureInput.message.isEmpty ||
      secureIndicator.isSuccess ||
      secureIndicator.status != 5 ||
      secureIndicator.message.isEmpty) {
    _fail('secure-input symbols did not preserve their main-thread guards');
  }
  final NativeCallResult contextMenu = bindings.viewSetContextMenu(1, 2);
  if (contextMenu.isSuccess ||
      contextMenu.status != 5 ||
      contextMenu.message.isEmpty) {
    _fail('view context-menu symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<NativeScreenSnapshot> screen = bindings
      .applicationResolveScreen(dartAppKitScreenSelectionMain);
  final NativeCallResult presentationConfiguration = bindings
      .windowSetPresentationConfiguration(
        handle: 1,
        level: dartAppKitWindowLevelStatus,
        collectionBehaviorMask:
            dartAppKitWindowCollectionBehaviorCanJoinAllSpaces,
      );
  final NativeCallResult present = bindings.windowPresent(
    handle: 1,
    startFrame: const NativeRect(x: 0, y: 0, width: 100, height: 1),
    targetFrame: const NativeRect(x: 0, y: 0, width: 100, height: 100),
    durationSeconds: 0,
    makeKey: false,
  );
  final NativeCallResult hide = bindings.windowHide(
    handle: 1,
    targetFrame: const NativeRect(x: 0, y: 0, width: 100, height: 1),
    durationSeconds: 0,
  );
  if (screen.isSuccess ||
      screen.status != 5 ||
      screen.message.isEmpty ||
      presentationConfiguration.isSuccess ||
      presentationConfiguration.status != 5 ||
      presentationConfiguration.message.isEmpty ||
      present.isSuccess ||
      present.status != 5 ||
      present.message.isEmpty ||
      hide.isSuccess ||
      hide.status != 5 ||
      hide.message.isEmpty) {
    _fail('window presentation symbols did not preserve main-thread guards');
  }
  final NativeValueResult<int> menu = bindings.menuCreate(
    'FFI smoke',
    autoEnablesItems: true,
  );
  if (menu.isSuccess || menu.status != 5 || menu.message.isEmpty) {
    _fail('menu symbol did not preserve its main-thread guard');
  }
  final NativeCallResult checked = bindings.menuItemSetChecked(1, true);
  if (checked.isSuccess || checked.status != 5 || checked.message.isEmpty) {
    _fail('checked menu-item symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> customView = bindings.customViewCreate(
    'missing.Provider',
  );
  if (customView.isSuccess ||
      customView.status != 5 ||
      customView.message.isEmpty) {
    _fail('custom-view symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> configuredView = bindings.viewCreate(
    const NativeViewConfiguration(
      acceptsFirstResponder: false,
      autoresizingMask: dartAppKitViewAutoresizingWidth,
    ),
  );
  if (configuredView.isSuccess ||
      configuredView.status != 5 ||
      configuredView.message.isEmpty) {
    _fail('configured view symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> configuredTextView = bindings.textViewCreate(
    NativeTextViewConfiguration.compatibilityDefault,
  );
  if (configuredTextView.isSuccess ||
      configuredTextView.status != 5 ||
      configuredTextView.message.isEmpty) {
    _fail('configured text-view symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> configuredTextEditor = bindings.textEditorCreate(
    const NativeTextEditorConfiguration(
      presentation: NativeTextViewConfiguration.compatibilityDefault,
      initiallyEditable: false,
    ),
  );
  final NativeCallResult editorDocument = bindings.textEditorSetDocument(
    1,
    const NativeTextEditorDocument(
      text: 'theme = dark',
      selectionStart: 0,
      selectionLength: 5,
      styleRuns: <NativeTextEditorStyleRun>[
        NativeTextEditorStyleRun(
          start: 0,
          length: 5,
          foregroundColorKind: 2,
          foregroundRed: 0.3,
          foregroundGreen: 0.6,
          foregroundBlue: 1,
          foregroundAlpha: 1,
          underlineStyle: 0,
          underlineColorKind: 0,
          underlineRed: 0,
          underlineGreen: 0,
          underlineBlue: 0,
          underlineAlpha: 1,
        ),
      ],
    ),
  );
  final NativeValueResult<NativeTextEditorSnapshot> editorSnapshot = bindings
      .textEditorSnapshot(1);
  final NativeCallResult editorLineHighlight = bindings
      .textEditorSetLineHighlight(
        1,
        const NativeTextEditorLineHighlight(
          location: 0,
          colorKind: 0,
          red: 0,
          green: 0,
          blue: 0,
          alpha: 1,
        ),
      );
  final NativeCallResult editorSelectionReveal = bindings
      .textEditorScrollSelectionToVisible(1);
  if (configuredTextEditor.isSuccess ||
      configuredTextEditor.status != 5 ||
      configuredTextEditor.message.isEmpty ||
      editorDocument.isSuccess ||
      editorDocument.status != 5 ||
      editorDocument.message.isEmpty ||
      editorSnapshot.isSuccess ||
      editorSnapshot.status != 5 ||
      editorSnapshot.message.isEmpty ||
      editorLineHighlight.isSuccess ||
      editorLineHighlight.status != 5 ||
      editorLineHighlight.message.isEmpty ||
      editorSelectionReveal.isSuccess ||
      editorSelectionReveal.status != 5 ||
      editorSelectionReveal.message.isEmpty) {
    _fail('text-editor FFI did not preserve its main-thread guard');
  }
  final NativeValueResult<int> splitView = bindings.splitViewCreate(0);
  if (splitView.isSuccess ||
      splitView.status != 5 ||
      splitView.message.isEmpty) {
    _fail('split-view create FFI did not preserve its main-thread guard');
  }
  final NativeCallResult splitPosition = bindings.splitViewSetPosition(
    handle: 1,
    fraction: 0.5,
    firstMinimumExtent: 10,
    secondMinimumExtent: 10,
  );
  if (splitPosition.isSuccess ||
      splitPosition.status != 5 ||
      splitPosition.message.isEmpty) {
    _fail('split-view position FFI did not preserve its main-thread guard');
  }
  final NativeCallResult tabGroup = bindings.windowAddTabbedWindow(1, 2);
  if (tabGroup.isSuccess || tabGroup.status != 5 || tabGroup.message.isEmpty) {
    _fail('window-tab FFI did not preserve its main-thread guard');
  }
  final NativeCallResult windowFrame = bindings.windowSetFrame(
    handle: 1,
    x: 10,
    y: 20,
    width: 640,
    height: 480,
  );
  final NativeCallResult fullscreen = bindings.windowSetFullscreen(1, true);
  if (windowFrame.isSuccess ||
      windowFrame.status != 5 ||
      windowFrame.message.isEmpty ||
      fullscreen.isSuccess ||
      fullscreen.status != 5 ||
      fullscreen.message.isEmpty) {
    _fail('window placement FFI did not preserve its main-thread guard');
  }
  final NativeCallResult representedPath = bindings
      .windowSetRepresentedFilePath(1, '/private/tmp');
  final NativeCallResult tabColor = bindings.windowSetTabAccessory(
    handle: 1,
    hasAccessory: true,
    shape: dartAppKitWindowTabAccessoryShapeRectangle,
    width: 12,
    height: 5,
    red: 1,
    green: 0,
    blue: 0,
    alpha: 1,
  );
  if (representedPath.isSuccess ||
      representedPath.status != 5 ||
      representedPath.message.isEmpty ||
      tabColor.isSuccess ||
      tabColor.status != 5 ||
      tabColor.message.isEmpty) {
    _fail('window metadata FFI did not preserve its main-thread guard');
  }

  final NativeValueResult<int> invalidWindow = bindings.windowCreate(
    x: 0,
    y: 0,
    width: -1,
    height: 100,
    title: 'FFI smoke — 日本語',
    styleMask: dartAppKitDefaultWindowStyleMask,
  );
  if (invalidWindow.isSuccess || invalidWindow.message.isEmpty) {
    _fail('invalid window call did not preserve native failure detail');
  }

  stdout.writeln(
    'FFI bridge smoke test passed '
    '(standalone Dart mainThread=${threadResult.value})',
  );
}
