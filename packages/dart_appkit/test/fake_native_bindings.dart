import 'dart:ffi';

import 'package:dart_appkit/src/native/native_bindings.dart';

enum FakeObjectKind { window, textView }

final class FakeNativeBindings implements NativeBindings {
  int reportedAbiVersion = dartAppKitAbiVersion;
  int mainThreadValue = 1;
  int nextHandle = 100;
  int? eventPort;
  bool terminateCalled = false;

  final Map<int, FakeObjectKind> objects = <int, FakeObjectKind>{};
  final Map<int, String> windowTitles = <int, String>{};
  final Map<int, String> texts = <int, String>{};
  final Map<int, int> contentViews = <int, int>{};
  final Set<Object> attachedFinalizers = <Object>{};
  final List<String> operations = <String>[];

  String? failNextOperation;
  int failureStatus = 7;
  String failureMessage = 'injected native failure';

  NativeCallResult _status(String operation) {
    operations.add(operation);
    if (failNextOperation == operation) {
      failNextOperation = null;
      return NativeCallResult.failure(failureStatus, failureMessage);
    }
    return const NativeCallResult.success();
  }

  NativeValueResult<T> _value<T>(String operation, T value) {
    operations.add(operation);
    if (failNextOperation == operation) {
      failNextOperation = null;
      return NativeValueResult<T>.failure(failureStatus, failureMessage);
    }
    return NativeValueResult<T>.success(value);
  }

  @override
  int abiVersion() => reportedAbiVersion;

  @override
  NativeCallResult applicationSetEventPort(int port) {
    final NativeCallResult result = _status('applicationSetEventPort');
    if (result.isSuccess) {
      eventPort = port;
    }
    return result;
  }

  @override
  NativeCallResult applicationTerminate() {
    final NativeCallResult result = _status('applicationTerminate');
    if (result.isSuccess) {
      terminateCalled = true;
    }
    return result;
  }

  @override
  NativeValueResult<int> windowCreate({
    required double x,
    required double y,
    required double width,
    required double height,
    required String title,
  }) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('windowCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.window;
      windowTitles[handle] = title;
    }
    return result;
  }

  @override
  NativeCallResult windowShow(int handle) => _status('windowShow');

  @override
  NativeCallResult windowClose(int handle) => _status('windowClose');

  @override
  NativeCallResult windowSetTitle(int handle, String title) {
    final NativeCallResult result = _status('windowSetTitle');
    if (result.isSuccess) {
      windowTitles[handle] = title;
    }
    return result;
  }

  @override
  NativeValueResult<int> textViewCreate() {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('textViewCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.textView;
      texts[handle] = '';
    }
    return result;
  }

  @override
  NativeCallResult textViewSetText(int handle, String text) {
    final NativeCallResult result = _status('textViewSetText');
    if (result.isSuccess) {
      texts[handle] = text;
    }
    return result;
  }

  @override
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle) {
    final NativeCallResult result = _status('windowSetContentView');
    if (result.isSuccess) {
      contentViews[windowHandle] = viewHandle;
    }
    return result;
  }

  @override
  NativeCallResult release(int handle) {
    final NativeCallResult result = _status('release');
    if (result.isSuccess) {
      objects.remove(handle);
      windowTitles.remove(handle);
      texts.remove(handle);
      contentViews.remove(handle);
    }
    return result;
  }

  @override
  NativeValueResult<int> debugIsMainThread() =>
      _value<int>('debugIsMainThread', mainThreadValue);

  @override
  NativeValueResult<int> debugLiveObjectCount() =>
      _value<int>('debugLiveObjectCount', objects.length);

  @override
  void attachFinalizer(Finalizable value, int handle, Object detachKey) {
    attachedFinalizers.add(detachKey);
  }

  @override
  void detachFinalizer(Object detachKey) {
    attachedFinalizers.remove(detachKey);
  }
}
