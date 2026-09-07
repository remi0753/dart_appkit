import 'dart:io';

import 'package:dart_appkit/src/native/ffi_native_bindings.dart';
import 'package:dart_appkit/src/native/native_bindings.dart';

Never _fail(String message) {
  stderr.writeln('legacy event bridge smoke test failed: $message');
  exit(1);
}

void main(List<String> arguments) {
  if (arguments.length != 1) {
    _fail('expected one legacy bridge dylib path');
  }
  final FfiNativeBindings bindings = FfiNativeBindings.open(arguments.single);
  final NativeValueResult<int> compatible = bindings
      .applicationSetEventPortVersioned(
        port: 4242,
        minimumVersion: 1,
        maximumVersion: 2,
      );
  if (!compatible.isSuccess || compatible.value != 1) {
    _fail('new Dart bindings did not fall back to legacy version 1');
  }

  final NativeValueResult<int> incompatible = bindings
      .applicationSetEventPortVersioned(
        port: 4242,
        minimumVersion: 2,
        maximumVersion: 2,
      );
  if (incompatible.isSuccess || incompatible.status != 8) {
    _fail('legacy fallback accepted an unsupported event version');
  }
  final NativeValueResult<int> malformed = bindings
      .applicationSetEventPortVersioned(
        port: 4242,
        minimumVersion: 0,
        maximumVersion: 2,
      );
  if (malformed.isSuccess || malformed.status != 1) {
    _fail('legacy fallback accepted an invalid event version range');
  }
  final NativeValueResult<int> genericView = bindings.viewCreate();
  if (genericView.isSuccess || genericView.status != 8) {
    _fail('legacy bridge did not reject the additive generic-view API');
  }
  final NativeValueResult<int> customView = bindings.customViewCreate(
    'example.CustomView',
  );
  if (customView.isSuccess || customView.status != 8) {
    _fail('legacy bridge did not reject the custom-view provider API');
  }
  if (bindings.applicationSetTerminationRequestDeferral(true).status != 8 ||
      bindings
              .applicationReplyToTerminationRequest(operationId: 1, allow: true)
              .status !=
          8 ||
      bindings.windowRequestClose(1).status != 8 ||
      bindings.windowSetCloseRequestDeferral(1, true).status != 8 ||
      bindings.windowSetKeyEventRouting(1, 1).status != 8 ||
      bindings
              .windowReplyToCloseRequest(handle: 1, operationId: 1, allow: true)
              .status !=
          8) {
    _fail('legacy bridge did not reject additive lifecycle APIs');
  }
  if (bindings.pasteboardReadText().status != 8 ||
      bindings.pasteboardWriteText('text').status != 8 ||
      bindings.pasteboardClear().status != 8 ||
      bindings.pasteboardGetChangeCount().status != 8) {
    _fail('legacy bridge did not reject additive pasteboard APIs');
  }
  if (bindings.applicationOpenExternalUrl('https://example.com').status != 8) {
    _fail('legacy bridge did not reject the additive external URL API');
  }
  if (bindings.windowAddTabbedWindow(1, 2).status != 8 ||
      bindings.windowSetRepresentedFilePath(1, '/tmp').status != 8 ||
      bindings
              .windowSetTabColor(
                handle: 1,
                hasColor: true,
                red: 1,
                green: 0,
                blue: 0,
                alpha: 1,
              )
              .status !=
          8 ||
      bindings.windowRemoveFromTabGroup(1).status != 8 ||
      bindings.windowSelectTab(1).status != 8 ||
      bindings.windowMakeFirstResponder(1, 2).status != 8 ||
      bindings.splitViewCreate(0).status != 8 ||
      bindings.splitViewSetChildren(1, 2, 3).status != 8 ||
      bindings
              .splitViewSetPosition(
                handle: 1,
                fraction: 0.5,
                firstMinimumExtent: 0,
                secondMinimumExtent: 0,
              )
              .status !=
          8 ||
      bindings.splitViewEqualize(1).status != 8 ||
      bindings.splitViewSetZoomedChild(1, -1).status != 8) {
    _fail('legacy bridge did not reject additive tab/split/focus APIs');
  }
  if (bindings.menuCreate('Menu').status != 8 ||
      bindings
              .menuItemCreate(title: 'Item', keyEquivalent: 'i', modifiers: 0)
              .status !=
          8 ||
      bindings.menuItemCreateSeparator().status != 8 ||
      bindings.menuAddItem(1, 2).status != 8 ||
      bindings.menuItemSetSubmenu(1, 2).status != 8 ||
      bindings.menuItemSetEnabled(1, true).status != 8 ||
      bindings.applicationSetMainMenu(1).status != 8 ||
      bindings.menuItemPerformAction(1).status != 8) {
    _fail('legacy bridge did not reject additive menu APIs');
  }
  stdout.writeln('legacy event bridge fallback smoke test passed');
}
