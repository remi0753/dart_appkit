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
  final NativeValueResult<int> genericView = bindings.viewCreate(
    NativeViewConfiguration.compatibilityDefault,
  );
  if (genericView.status != 7) {
    _fail('legacy bridge did not retain default generic-view creation');
  }
  final NativeValueResult<int> configuredGenericView = bindings.viewCreate(
    const NativeViewConfiguration(
      acceptsFirstResponder: false,
      autoresizingMask: 0,
    ),
  );
  if (configuredGenericView.status != 8) {
    _fail('legacy bridge accepted a configured generic view');
  }
  if (bindings
          .textViewCreate(NativeTextViewConfiguration.compatibilityDefault)
          .status !=
      7) {
    _fail('legacy bridge did not retain default text-view creation');
  }
  const NativeTextViewConfiguration configuredTextView =
      NativeTextViewConfiguration(
        view: NativeViewConfiguration.compatibilityDefault,
        fontKind: 0,
        fontWeight: 3,
        fontSize: 14,
        fontFamily: null,
        paddingTop: 4,
        paddingRight: 4,
        paddingBottom: 4,
        paddingLeft: 4,
        foregroundColorKind: 0,
        foregroundRed: 0,
        foregroundGreen: 0,
        foregroundBlue: 0,
        foregroundAlpha: 1,
        backgroundColorKind: 1,
        backgroundRed: 0,
        backgroundGreen: 0,
        backgroundBlue: 0,
        backgroundAlpha: 1,
      );
  if (bindings.textViewCreate(configuredTextView).status != 8) {
    _fail('legacy bridge accepted a configured text view');
  }
  if (bindings
              .textEditorCreate(
                const NativeTextEditorConfiguration(
                  presentation:
                      NativeTextViewConfiguration.compatibilityDefault,
                  initiallyEditable: false,
                ),
              )
              .status !=
          8 ||
      bindings
              .textEditorSetDocument(
                1,
                const NativeTextEditorDocument(
                  text: '',
                  selectionStart: 0,
                  selectionLength: 0,
                  styleRuns: <NativeTextEditorStyleRun>[],
                ),
              )
              .status !=
          8 ||
      bindings
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
              )
              .status !=
          8 ||
      bindings.textEditorScrollSelectionToVisible(1).status != 8 ||
      bindings.textEditorSnapshot(1).status != 8) {
    _fail('legacy bridge accepted the additive text-editor API');
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
  final int defaultExternalUrlFlags =
      dartAppKitExternalUrlPolicyRequireAuthority |
      dartAppKitExternalUrlPolicyRequireHost |
      dartAppKitExternalUrlPolicyForbidCredentials;
  if (bindings
          .applicationOpenExternalUrl(
            'https://example.com',
            scheme: 'https',
            policyFlags: defaultExternalUrlFlags,
          )
          .status !=
      7) {
    _fail('legacy bridge did not retain the default external URL policy');
  }
  if (bindings
          .applicationOpenExternalUrl(
            'ssh://example.com',
            scheme: 'ssh',
            policyFlags: defaultExternalUrlFlags,
          )
          .status !=
      8) {
    _fail('legacy bridge accepted a custom external URL policy');
  }
  if (bindings
              .applicationPostUserNotification(
                identifier: 'legacy-1',
                title: 'Legacy',
                body: 'Unsupported',
              )
              .status !=
          8 ||
      bindings.applicationRemoveUserNotification('legacy-1').status != 8 ||
      bindings.applicationSetDockBadgeLabel('1%').status != 8) {
    _fail('legacy bridge accepted additive notification or Dock APIs');
  }
  if (bindings.globalHotKeyRegister(keyCode: 79, modifiers: 1 << 4).status !=
      8) {
    _fail('legacy bridge accepted additive global hot-key registration');
  }
  if (bindings.secureEventInputCreate().status != 8 ||
      bindings.secureEventInputSetDesired(1, true).status != 8 ||
      bindings.secureEventInputGetSnapshot(1).status != 8 ||
      bindings
              .viewSetSecureInputIndicator(
                1,
                dartAppKitSecureInputIndicatorAutomatic,
              )
              .status !=
          8) {
    _fail('legacy bridge accepted additive secure-input APIs');
  }
  if (bindings.viewSetContextMenu(1, 2).status != 8) {
    _fail('legacy bridge accepted additive view context-menu attachment');
  }
  if (bindings.viewSetQuickLookRequestEnabled(1, true).status != 8 ||
      bindings
              .viewShowDefinition(
                1,
                const NativeDefinitionPresentation(
                  text: 'word',
                  fontKind: 1,
                  fontWeight: 3,
                  fontSize: 13,
                  fontFamily: null,
                  baselineX: 1,
                  baselineY: 2,
                ),
              )
              .status !=
          8) {
    _fail('legacy bridge accepted additive Quick Look APIs');
  }
  if (bindings
          .viewSetServicesTextRequestor(
            1,
            const NativeServicesTextRequestorConfiguration(
              selectionText: 'selected',
              acceptsReturnedText: true,
              maximumReturnedTextUtf8Bytes: 1024,
            ),
          )
          .status !=
      8) {
    _fail('legacy bridge accepted additive Services requestor APIs');
  }
  if (bindings
          .viewSetDropDestination(
            1,
            const NativeDropDestinationConfiguration(
              acceptsPlainText: true,
              acceptsFileUrls: true,
              maximumTextUtf8Bytes: 1024,
              maximumFileUrlCount: 2,
              maximumFileUrlUtf8Bytes: 256,
              maximumTotalFileUrlUtf8Bytes: 512,
            ),
          )
          .status !=
      8) {
    _fail('legacy bridge accepted additive drop destination APIs');
  }
  if (bindings.applicationResolveScreen(dartAppKitScreenSelectionMain).status !=
          8 ||
      bindings
              .windowSetPresentationConfiguration(
                handle: 1,
                level: dartAppKitWindowLevelStatus,
                collectionBehaviorMask:
                    dartAppKitWindowCollectionBehaviorCanJoinAllSpaces,
              )
              .status !=
          8 ||
      bindings
              .windowPresent(
                handle: 1,
                startFrame: const NativeRect(x: 0, y: 0, width: 100, height: 1),
                targetFrame: const NativeRect(
                  x: 0,
                  y: 0,
                  width: 100,
                  height: 100,
                ),
                durationSeconds: 0,
                makeKey: false,
              )
              .status !=
          8 ||
      bindings
              .windowHide(
                handle: 1,
                targetFrame: const NativeRect(
                  x: 0,
                  y: 0,
                  width: 100,
                  height: 1,
                ),
                durationSeconds: 0,
              )
              .status !=
          8) {
    _fail('legacy bridge accepted additive window presentation APIs');
  }
  final NativeValueResult<int> configuredWindow = bindings.windowCreate(
    x: 0,
    y: 0,
    width: 100,
    height: 100,
    title: 'configured',
    styleMask: 0,
  );
  if (configuredWindow.status != 8) {
    _fail('legacy bridge accepted a non-default window style');
  }
  final NativeValueResult<int> defaultWindow = bindings.windowCreate(
    x: 0,
    y: 0,
    width: 100,
    height: 100,
    title: 'default',
    styleMask: dartAppKitDefaultWindowStyleMask,
  );
  if (defaultWindow.status != 7) {
    _fail('legacy bridge did not use legacy creation for the default style');
  }
  final NativeCallResult defaultTabAccessory = bindings.windowSetTabAccessory(
    handle: 1,
    hasAccessory: true,
    shape: dartAppKitWindowTabAccessoryShapeEllipse,
    width: 8,
    height: 8,
    red: 1,
    green: 0,
    blue: 0,
    alpha: 1,
  );
  if (defaultTabAccessory.status != 7) {
    _fail('legacy bridge did not use the legacy default tab marker');
  }
  if (bindings.windowAddTabbedWindow(1, 2).status != 8 ||
      bindings
              .windowSetFrame(handle: 1, x: 0, y: 0, width: 640, height: 480)
              .status !=
          8 ||
      bindings.windowSetFullscreen(1, true).status != 8 ||
      bindings.windowSetRepresentedFilePath(1, '/tmp').status != 8 ||
      bindings
              .windowSetTabAccessory(
                handle: 1,
                hasAccessory: true,
                shape: dartAppKitWindowTabAccessoryShapeRectangle,
                width: 12,
                height: 5,
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
  if (bindings.menuCreate('Menu', autoEnablesItems: false).status != 7) {
    _fail('legacy bridge did not retain explicit-state menu creation');
  }
  if (bindings.menuCreate('Menu', autoEnablesItems: true).status != 8) {
    _fail('legacy bridge accepted an auto-enabling menu');
  }
  if (bindings
              .menuItemCreate(title: 'Item', keyEquivalent: 'i', modifiers: 0)
              .status !=
          8 ||
      bindings.menuItemCreateSeparator().status != 8 ||
      bindings.menuAddItem(1, 2).status != 8 ||
      bindings.menuItemSetSubmenu(1, 2).status != 8 ||
      bindings.menuItemSetEnabled(1, true).status != 8 ||
      bindings.menuItemSetChecked(1, true).status != 8 ||
      bindings.applicationSetMainMenu(1).status != 8 ||
      bindings.menuItemPerformAction(1).status != 8) {
    _fail('legacy bridge did not reject additive menu APIs');
  }
  stdout.writeln('legacy event bridge fallback smoke test passed');
}
