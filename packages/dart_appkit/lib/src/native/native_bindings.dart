import 'dart:ffi';
import 'dart:typed_data';

const int dartAppKitAbiVersion = 1;
const int dartAppKitMinimumEventProtocolVersion = 1;
const int dartAppKitCurrentEventProtocolVersion = 6;
const int dartAppKitPasteboardMaximumTextUtf8Bytes = 64 * 1024 * 1024;
const int dartAppKitExternalUrlMaximumUtf8Bytes = 4096;
const int dartAppKitExternalUrlSchemeMaximumUtf8Bytes = 64;
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

  NativeValueResult<NativePasteboardTextSnapshot> pasteboardReadText();
  NativeValueResult<int> pasteboardWriteText(String text);
  NativeValueResult<int> pasteboardClear();
  NativeValueResult<int> pasteboardGetChangeCount();

  NativeValueResult<int> menuCreate(String title);
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

  NativeValueResult<int> viewCreate();
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
  NativeValueResult<int> textViewCreate();
  NativeCallResult textViewSetText(int handle, String text);
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle);

  NativeCallResult release(int handle);
  NativeValueResult<int> debugIsMainThread();
  NativeValueResult<int> debugLiveObjectCount();
  NativeCallResult debugRequestApplicationTermination();

  void attachFinalizer(Finalizable value, int handle, Object detachKey);
  void detachFinalizer(Object detachKey);
}
