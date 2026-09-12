import 'dart:ffi';
import 'dart:typed_data';

const int dartAppKitAbiVersion = 1;
const int dartAppKitMinimumEventProtocolVersion = 1;
const int dartAppKitCurrentEventProtocolVersion = 12;
const int dartAppKitStatusGlobalHotKeyConflict = 11;
const int dartAppKitStatusGlobalHotKeyRegistrationFailed = 12;
const int dartAppKitStatusSecureEventInputFailed = 13;
const int dartAppKitSecureInputIndicatorHidden = 0;
const int dartAppKitSecureInputIndicatorAutomatic = 1;
const int dartAppKitSecureInputIndicatorManual = 2;
const int dartAppKitPasteboardMaximumTextUtf8Bytes = 64 * 1024 * 1024;
const int dartAppKitExternalUrlMaximumUtf8Bytes = 4096;
const int dartAppKitExternalUrlSchemeMaximumUtf8Bytes = 64;
const int dartAppKitUserNotificationIdentifierMaximumUtf8Bytes = 128;
const int dartAppKitUserNotificationTextMaximumUtf8Bytes = 4096;
const int dartAppKitDockBadgeLabelMaximumUtf8Bytes = 32;
const int dartAppKitExternalUrlPolicyRequireAuthority = 1 << 0;
const int dartAppKitExternalUrlPolicyForbidAuthority = 1 << 1;
const int dartAppKitExternalUrlPolicyRequireHost = 1 << 2;
const int dartAppKitExternalUrlPolicyForbidCredentials = 1 << 3;
const int dartAppKitExternalUrlPolicyRequirePath = 1 << 4;
const int dartAppKitWindowStyleTitled = 1 << 0;
const int dartAppKitWindowStyleClosable = 1 << 1;
const int dartAppKitWindowStyleMiniaturizable = 1 << 2;
const int dartAppKitWindowStyleResizable = 1 << 3;
const int dartAppKitDefaultWindowStyleMask =
    dartAppKitWindowStyleTitled |
    dartAppKitWindowStyleClosable |
    dartAppKitWindowStyleMiniaturizable |
    dartAppKitWindowStyleResizable;
const double dartAppKitWindowTabAccessoryMaximumExtent = 256;
const int dartAppKitWindowTabAccessoryShapeRectangle = 0;
const int dartAppKitWindowTabAccessoryShapeEllipse = 1;
const int dartAppKitScreenSelectionMain = 0;
const int dartAppKitScreenSelectionMouse = 1;
const int dartAppKitScreenSelectionMenuBar = 2;
const int dartAppKitWindowLevelNormal = 0;
const int dartAppKitWindowLevelFloating = 1;
const int dartAppKitWindowLevelStatus = 2;
const int dartAppKitWindowCollectionBehaviorCanJoinAllSpaces = 1 << 0;
const int dartAppKitWindowCollectionBehaviorFullScreenAuxiliary = 1 << 1;
const int dartAppKitWindowCollectionBehaviorStationary = 1 << 2;
const int dartAppKitWindowCollectionBehaviorTransient = 1 << 3;
const double dartAppKitWindowPresentationAnimationMaximumSeconds = 5;
const int dartAppKitViewAutoresizingWidth = 1 << 0;
const int dartAppKitViewAutoresizingHeight = 1 << 1;
const int dartAppKitDefaultViewAutoresizingMask =
    dartAppKitViewAutoresizingWidth | dartAppKitViewAutoresizingHeight;
const double dartAppKitTextViewFontMaximumSize = 512;
const int dartAppKitTextViewFontFamilyMaximumUtf8Bytes = 256;
const int dartAppKitDefinitionMaximumTextUtf8Bytes = 4096;
const int dartAppKitServicesMaximumTextUtf8Bytes =
    dartAppKitPasteboardMaximumTextUtf8Bytes;
const int dartAppKitDropMaximumTextUtf8Bytes =
    dartAppKitPasteboardMaximumTextUtf8Bytes;
const int dartAppKitDropMaximumFileUrlCount = 256;
const int dartAppKitDropMaximumFileUrlUtf8Bytes = 1024 * 1024;
const int dartAppKitDropMaximumTotalFileUrlUtf8Bytes =
    dartAppKitPasteboardMaximumTextUtf8Bytes;
const int dartAppKitFolderServiceMaximumFileUrlCount =
    dartAppKitDropMaximumFileUrlCount;
const int dartAppKitFolderServiceMaximumFileUrlUtf8Bytes =
    dartAppKitDropMaximumFileUrlUtf8Bytes;
const int dartAppKitFolderServiceMaximumTotalFileUrlUtf8Bytes =
    dartAppKitDropMaximumTotalFileUrlUtf8Bytes;
const String dartAppKitFolderServiceOpenTabMessage = 'openTab';
const String dartAppKitFolderServiceOpenWindowMessage = 'openWindow';
const double dartAppKitTextViewPaddingMaximumExtent = 4096;
const int dartAppKitTextEditorMaximumTextUtf8Bytes = 16 * 1024 * 1024;
const int dartAppKitTextEditorMaximumStyleRuns = 64 * 1024;

final class NativeViewConfiguration {
  const NativeViewConfiguration({
    required this.acceptsFirstResponder,
    required this.autoresizingMask,
  });

  final bool acceptsFirstResponder;
  final int autoresizingMask;

  static const NativeViewConfiguration compatibilityDefault =
      NativeViewConfiguration(
        acceptsFirstResponder: true,
        autoresizingMask: dartAppKitDefaultViewAutoresizingMask,
      );

  bool get isCompatibilityDefault =>
      acceptsFirstResponder &&
      autoresizingMask == dartAppKitDefaultViewAutoresizingMask;
}

final class NativeDefinitionPresentation {
  const NativeDefinitionPresentation({
    required this.text,
    required this.fontKind,
    required this.fontWeight,
    required this.fontSize,
    required this.fontFamily,
    required this.baselineX,
    required this.baselineY,
  });

  final String text;
  final int fontKind;
  final int fontWeight;
  final double fontSize;
  final String? fontFamily;
  final double baselineX;
  final double baselineY;
}

final class NativeServicesTextRequestorConfiguration {
  const NativeServicesTextRequestorConfiguration({
    required this.selectionText,
    required this.acceptsReturnedText,
    required this.maximumReturnedTextUtf8Bytes,
  });

  final String? selectionText;
  final bool acceptsReturnedText;
  final int maximumReturnedTextUtf8Bytes;
}

final class NativeDropDestinationConfiguration {
  const NativeDropDestinationConfiguration({
    required this.acceptsPlainText,
    required this.acceptsFileUrls,
    required this.maximumTextUtf8Bytes,
    required this.maximumFileUrlCount,
    required this.maximumFileUrlUtf8Bytes,
    required this.maximumTotalFileUrlUtf8Bytes,
  });

  final bool acceptsPlainText;
  final bool acceptsFileUrls;
  final int maximumTextUtf8Bytes;
  final int maximumFileUrlCount;
  final int maximumFileUrlUtf8Bytes;
  final int maximumTotalFileUrlUtf8Bytes;
}

final class NativeFolderServicesProviderConfiguration {
  const NativeFolderServicesProviderConfiguration({
    required this.maximumFileUrlCount,
    required this.maximumFileUrlUtf8Bytes,
    required this.maximumTotalFileUrlUtf8Bytes,
  });

  final int maximumFileUrlCount;
  final int maximumFileUrlUtf8Bytes;
  final int maximumTotalFileUrlUtf8Bytes;
}

final class NativeTextViewConfiguration {
  const NativeTextViewConfiguration({
    required this.view,
    required this.fontKind,
    required this.fontWeight,
    required this.fontSize,
    required this.fontFamily,
    required this.paddingTop,
    required this.paddingRight,
    required this.paddingBottom,
    required this.paddingLeft,
    required this.foregroundColorKind,
    required this.foregroundRed,
    required this.foregroundGreen,
    required this.foregroundBlue,
    required this.foregroundAlpha,
    required this.backgroundColorKind,
    required this.backgroundRed,
    required this.backgroundGreen,
    required this.backgroundBlue,
    required this.backgroundAlpha,
  });

  final NativeViewConfiguration view;
  final int fontKind;
  final int fontWeight;
  final double fontSize;
  final String? fontFamily;
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeft;
  final int foregroundColorKind;
  final double foregroundRed;
  final double foregroundGreen;
  final double foregroundBlue;
  final double foregroundAlpha;
  final int backgroundColorKind;
  final double backgroundRed;
  final double backgroundGreen;
  final double backgroundBlue;
  final double backgroundAlpha;

  static const NativeTextViewConfiguration compatibilityDefault =
      NativeTextViewConfiguration(
        view: NativeViewConfiguration.compatibilityDefault,
        fontKind: 1,
        fontWeight: 3,
        fontSize: 18,
        fontFamily: null,
        paddingTop: 20,
        paddingRight: 20,
        paddingBottom: 20,
        paddingLeft: 20,
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

  bool get isCompatibilityDefault =>
      view.isCompatibilityDefault &&
      fontKind == 1 &&
      fontWeight == 3 &&
      fontSize == 18 &&
      fontFamily == null &&
      paddingTop == 20 &&
      paddingRight == 20 &&
      paddingBottom == 20 &&
      paddingLeft == 20 &&
      foregroundColorKind == 0 &&
      backgroundColorKind == 1;
}

final class NativeTextEditorConfiguration {
  const NativeTextEditorConfiguration({
    required this.presentation,
    required this.initiallyEditable,
  });

  final NativeTextViewConfiguration presentation;
  final bool initiallyEditable;
}

final class NativeTextEditorStyleRun {
  const NativeTextEditorStyleRun({
    required this.start,
    required this.length,
    required this.foregroundColorKind,
    required this.foregroundRed,
    required this.foregroundGreen,
    required this.foregroundBlue,
    required this.foregroundAlpha,
    required this.underlineStyle,
    required this.underlineColorKind,
    required this.underlineRed,
    required this.underlineGreen,
    required this.underlineBlue,
    required this.underlineAlpha,
  });

  final int start;
  final int length;
  final int foregroundColorKind;
  final double foregroundRed;
  final double foregroundGreen;
  final double foregroundBlue;
  final double foregroundAlpha;
  final int underlineStyle;
  final int underlineColorKind;
  final double underlineRed;
  final double underlineGreen;
  final double underlineBlue;
  final double underlineAlpha;
}

final class NativeTextEditorLineHighlight {
  const NativeTextEditorLineHighlight({
    required this.location,
    required this.colorKind,
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
  });

  final int location;
  final int colorKind;
  final double red;
  final double green;
  final double blue;
  final double alpha;
}

final class NativeTextEditorDocument {
  const NativeTextEditorDocument({
    required this.text,
    required this.selectionStart,
    required this.selectionLength,
    required this.styleRuns,
  });

  final String text;
  final int selectionStart;
  final int selectionLength;
  final List<NativeTextEditorStyleRun> styleRuns;
}

final class NativeTextEditorSnapshot {
  const NativeTextEditorSnapshot({
    required this.text,
    required this.selectionStart,
    required this.selectionLength,
    required this.isEditable,
    required this.hasMarkedText,
  });

  final String text;
  final int selectionStart;
  final int selectionLength;
  final bool isEditable;
  final bool hasMarkedText;
}

final class NativeCallResult {
  const NativeCallResult.success() : status = 0, message = '';

  const NativeCallResult.failure(this.status, this.message)
    : assert(status != 0);

  final int status;
  final String message;

  bool get isSuccess => status == 0;
}

final class NativeValueResult<T> {
  const NativeValueResult.success(T this.value) : status = 0, message = '';

  const NativeValueResult.failure(this.status, this.message)
    : assert(status != 0),
      value = null;

  final int status;
  final String message;
  final T? value;

  bool get isSuccess => status == 0;
}

final class NativePasteboardTextSnapshot {
  const NativePasteboardTextSnapshot({
    required this.text,
    required this.changeCount,
  });

  final String? text;
  final int changeCount;
}

final class NativeRect {
  const NativeRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

final class NativeScreenSnapshot {
  const NativeScreenSnapshot({
    required this.displayId,
    required this.frame,
    required this.visibleFrame,
    required this.backingScaleFactor,
  });

  final int displayId;
  final NativeRect frame;
  final NativeRect visibleFrame;
  final double backingScaleFactor;
}

final class NativeSecureEventInputSnapshot {
  const NativeSecureEventInputSnapshot({
    required this.desired,
    required this.ownedEnabled,
    required this.systemEnabled,
    required this.lastOsStatus,
  });

  final bool desired;
  final bool ownedEnabled;
  final bool systemEnabled;
  final int lastOsStatus;
}

abstract interface class NativeBindings {
  int abiVersion();

  NativeCallResult applicationSetEventPort(int port);
  NativeValueResult<int> applicationSetEventPortVersioned({
    required int port,
    required int minimumVersion,
    required int maximumVersion,
  });
  NativeCallResult applicationTerminate();
  NativeCallResult applicationSetTerminationRequestDeferral(bool enabled);
  NativeCallResult applicationReplyToTerminationRequest({
    required int operationId,
    required bool allow,
  });
  NativeValueResult<int> applicationOpenExternalUrl(
    String url, {
    required String scheme,
    required int policyFlags,
  });
  NativeCallResult applicationPostUserNotification({
    required String identifier,
    required String title,
    required String body,
  });
  NativeCallResult applicationRemoveUserNotification(String identifier);
  NativeCallResult applicationSetDockBadgeLabel(String? label);

  NativeValueResult<NativePasteboardTextSnapshot> pasteboardReadText();
  NativeValueResult<int> pasteboardWriteText(String text);
  NativeValueResult<int> pasteboardClear();
  NativeValueResult<int> pasteboardGetChangeCount();

  NativeValueResult<int> menuCreate(
    String title, {
    required bool autoEnablesItems,
  });
  NativeValueResult<int> menuItemCreate({
    required String title,
    required String keyEquivalent,
    required int modifiers,
  });
  NativeValueResult<int> menuItemCreateSeparator();
  NativeCallResult menuAddItem(int menuHandle, int itemHandle);
  NativeCallResult menuItemSetSubmenu(int itemHandle, int submenuHandle);
  NativeCallResult menuItemSetEnabled(int itemHandle, bool enabled);
  NativeCallResult applicationSetMainMenu(int menuHandle);
  NativeCallResult menuItemPerformAction(int itemHandle);

  NativeValueResult<int> windowCreate({
    required double x,
    required double y,
    required double width,
    required double height,
    required String title,
    required int styleMask,
  });
  NativeCallResult windowShow(int handle);
  NativeCallResult windowClose(int handle);
  NativeCallResult windowSetFrame({
    required int handle,
    required double x,
    required double y,
    required double width,
    required double height,
  });
  NativeValueResult<NativeRect> windowGetContentLayoutRect(int handle);
  NativeCallResult windowSetFullscreen(int handle, bool enabled);
  NativeCallResult windowRequestClose(int handle);
  NativeCallResult windowSetCloseRequestDeferral(int handle, bool enabled);
  NativeCallResult windowSetKeyEventRouting(int handle, int routing);
  NativeCallResult windowReplyToCloseRequest({
    required int handle,
    required int operationId,
    required bool allow,
  });
  NativeCallResult windowSetTitle(int handle, String title);
  NativeCallResult windowSetRepresentedFilePath(int handle, String? path);
  NativeCallResult windowSetTabAccessory({
    required int handle,
    required bool hasAccessory,
    required int shape,
    required double width,
    required double height,
    required double red,
    required double green,
    required double blue,
    required double alpha,
  });
  NativeCallResult windowAddTabbedWindow(int handle, int tabbedWindowHandle);
  NativeCallResult windowRemoveFromTabGroup(int handle);
  NativeCallResult windowSelectTab(int handle);
  NativeCallResult windowMakeFirstResponder(int handle, int viewHandle);

  NativeValueResult<int> viewCreate(NativeViewConfiguration configuration);
  NativeValueResult<int> splitViewCreate(int axis);
  NativeCallResult splitViewSetChildren(
    int splitViewHandle,
    int firstViewHandle,
    int secondViewHandle,
  );
  NativeCallResult splitViewSetPosition({
    required int handle,
    required double fraction,
    required double firstMinimumExtent,
    required double secondMinimumExtent,
  });
  NativeCallResult splitViewEqualize(int handle);
  NativeCallResult splitViewSetZoomedChild(int handle, int child);
  NativeValueResult<int> customViewCreate(String providerIdentifier);
  NativeCallResult customViewPerformOperation(int handle, Uint8List payload);
  NativeValueResult<int> textViewCreate(
    NativeTextViewConfiguration configuration,
  );
  NativeCallResult textViewSetText(int handle, String text);
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle);

  NativeCallResult release(int handle);
  NativeValueResult<int> debugIsMainThread();
  NativeValueResult<int> debugLiveObjectCount();
  NativeCallResult debugRequestApplicationTermination();

  void attachFinalizer(Finalizable value, int handle, Object detachKey);
  void detachFinalizer(Object detachKey);
}

/// Optional native surface kept separate so existing binding fakes stay valid.
abstract interface class NativeTextEditorBindings {
  NativeValueResult<int> textEditorCreate(
    NativeTextEditorConfiguration configuration,
  );
  NativeCallResult textEditorSetDocument(
    int handle,
    NativeTextEditorDocument document,
  );
  NativeCallResult textEditorSetStyleRuns(
    int handle,
    List<NativeTextEditorStyleRun> styleRuns,
  );
  NativeCallResult textEditorSetLineHighlight(
    int handle,
    NativeTextEditorLineHighlight? highlight,
  );
  NativeCallResult textEditorSetEditable(int handle, bool editable);
  NativeCallResult textEditorSetSelection(
    int handle, {
    required int start,
    required int length,
  });
  NativeCallResult textEditorScrollSelectionToVisible(int handle);
  NativeValueResult<NativeTextEditorSnapshot> textEditorSnapshot(int handle);
}

/// Optional split-view observation surface kept separate for older bridges and
/// test bindings that implement only the mutation API.
abstract interface class NativeSplitViewPositionBindings {
  NativeValueResult<double> splitViewGetFraction(int handle);
}

/// Optional global-hot-key surface kept separate for older native bridges.
abstract interface class NativeGlobalHotKeyBindings {
  NativeValueResult<int> globalHotKeyRegister({
    required int keyCode,
    required int modifiers,
  });
}

/// Optional native checked state for existing menu-item handles.
abstract interface class NativeMenuItemStateBindings {
  NativeCallResult menuItemSetChecked(int handle, bool checked);
}

/// Optional view-local context-menu attachment surface for older bridges.
abstract interface class NativeViewContextMenuBindings {
  NativeCallResult viewSetContextMenu(int viewHandle, int menuHandle);
}

/// Optional pressure-request and definition-presentation surface.
abstract interface class NativeQuickLookBindings {
  NativeCallResult viewSetQuickLookRequestEnabled(int handle, bool enabled);
  NativeCallResult viewShowDefinition(
    int handle,
    NativeDefinitionPresentation presentation,
  );
}

/// Optional cached plain-text Services requestor surface.
abstract interface class NativeServicesTextRequestorBindings {
  NativeCallResult viewSetServicesTextRequestor(
    int handle,
    NativeServicesTextRequestorConfiguration? configuration,
  );
}

/// Optional bounded copy-only text/file-URL drop-destination surface.
abstract interface class NativeDropDestinationBindings {
  NativeCallResult viewSetDropDestination(
    int handle,
    NativeDropDestinationConfiguration? configuration,
  );
}

/// Optional application local-folder Services provider surface.
abstract interface class NativeFolderServicesProviderBindings {
  NativeCallResult applicationSetFolderServicesProvider(
    NativeFolderServicesProviderConfiguration? configuration,
  );
}

/// Optional balanced Secure Event Input and view-indicator surface.
abstract interface class NativeSecureEventInputBindings {
  NativeValueResult<int> secureEventInputCreate();
  NativeCallResult secureEventInputSetDesired(int handle, bool desired);
  NativeValueResult<NativeSecureEventInputSnapshot> secureEventInputGetSnapshot(
    int handle,
  );
  NativeCallResult viewSetSecureInputIndicator(int handle, int state);
}

/// Optional current-screen and animated window-presentation surface.
abstract interface class NativeWindowPresentationBindings {
  NativeValueResult<NativeScreenSnapshot> applicationResolveScreen(
    int selection,
  );

  NativeCallResult windowSetPresentationConfiguration({
    required int handle,
    required int level,
    required int collectionBehaviorMask,
  });

  NativeCallResult windowPresent({
    required int handle,
    required NativeRect startFrame,
    required NativeRect targetFrame,
    required double durationSeconds,
    required bool makeKey,
  });

  NativeCallResult windowHide({
    required int handle,
    required NativeRect targetFrame,
    required double durationSeconds,
  });
}
