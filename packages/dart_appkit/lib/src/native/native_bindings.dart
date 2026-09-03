import 'dart:ffi';

const int dartAppKitAbiVersion = 1;
const int dartAppKitMinimumEventProtocolVersion = 1;
const int dartAppKitCurrentEventProtocolVersion = 4;

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
  });
  NativeCallResult windowShow(int handle);
  NativeCallResult windowClose(int handle);
  NativeCallResult windowRequestClose(int handle);
  NativeCallResult windowSetCloseRequestDeferral(int handle, bool enabled);
  NativeCallResult windowReplyToCloseRequest({
    required int handle,
    required int operationId,
    required bool allow,
  });
  NativeCallResult windowSetTitle(int handle, String title);

  NativeValueResult<int> viewCreate();
  NativeValueResult<int> customViewCreate(String providerIdentifier);
  NativeValueResult<int> textViewCreate();
  NativeCallResult textViewSetText(int handle, String text);
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle);

  NativeCallResult release(int handle);
  NativeValueResult<int> debugIsMainThread();
  NativeValueResult<int> debugLiveObjectCount();

  void attachFinalizer(Finalizable value, int handle, Object detachKey);
  void detachFinalizer(Object detachKey);
}
