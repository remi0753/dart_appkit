import 'dart:ffi';

const int dartAppKitAbiVersion = 1;

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

abstract interface class NativeBindings {
  int abiVersion();

  NativeCallResult applicationSetEventPort(int port);
  NativeCallResult applicationTerminate();

  NativeValueResult<int> windowCreate({
    required double x,
    required double y,
    required double width,
    required double height,
    required String title,
  });
  NativeCallResult windowShow(int handle);
  NativeCallResult windowClose(int handle);
  NativeCallResult windowSetTitle(int handle, String title);

  NativeValueResult<int> textViewCreate();
  NativeCallResult textViewSetText(int handle, String text);
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle);

  NativeCallResult release(int handle);
  NativeValueResult<int> debugIsMainThread();
  NativeValueResult<int> debugLiveObjectCount();

  void attachFinalizer(Finalizable value, int handle, Object detachKey);
  void detachFinalizer(Object detachKey);
}
