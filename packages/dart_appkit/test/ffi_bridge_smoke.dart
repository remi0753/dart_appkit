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
      .applicationOpenExternalUrl('https://example.com');
  if (externalUrl.isSuccess ||
      externalUrl.status != 5 ||
      externalUrl.message.isEmpty) {
    _fail('external URL symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> menu = bindings.menuCreate('FFI smoke');
  if (menu.isSuccess || menu.status != 5 || menu.message.isEmpty) {
    _fail('menu symbol did not preserve its main-thread guard');
  }
  final NativeValueResult<int> customView = bindings.customViewCreate(
    'missing.Provider',
  );
  if (customView.isSuccess ||
      customView.status != 5 ||
      customView.message.isEmpty) {
    _fail('custom-view symbol did not preserve its main-thread guard');
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
  final NativeCallResult tabColor = bindings.windowSetTabColor(
    handle: 1,
    hasColor: true,
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
  );
  if (invalidWindow.isSuccess || invalidWindow.message.isEmpty) {
    _fail('invalid window call did not preserve native failure detail');
  }

  stdout.writeln(
    'FFI bridge smoke test passed '
    '(standalone Dart mainThread=${threadResult.value})',
  );
}
