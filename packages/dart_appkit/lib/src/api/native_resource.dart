part of '../api.dart';

final class AppKitNativeException implements Exception {
  const AppKitNativeException({
    required this.operation,
    required this.status,
    required this.nativeMessage,
  });

  final String operation;
  final int status;
  final String nativeMessage;

  @override
  String toString() {
    final String detail = nativeMessage.isEmpty
        ? 'native status $status'
        : nativeMessage;
    return 'AppKitNativeException($operation, status $status): $detail';
  }
}

final class AppKitInitializationException implements Exception {
  const AppKitInitializationException(this.message);

  final String message;

  @override
  String toString() => 'AppKitInitializationException: $message';
}

void _checkCall(NativeCallResult result, String operation) {
  if (!result.isSuccess) {
    throw AppKitNativeException(
      operation: operation,
      status: result.status,
      nativeMessage: result.message,
    );
  }
}

T _checkValue<T>(NativeValueResult<T> result, String operation) {
  if (!result.isSuccess || result.value == null) {
    throw AppKitNativeException(
      operation: operation,
      status: result.status,
      nativeMessage: result.message,
    );
  }
  return result.value as T;
}

abstract base class _NativeResource implements Finalizable {
  _NativeResource(this._bindings, this._handle) {
    if (_handle <= 0) {
      throw ArgumentError.value(_handle, 'handle', 'must be positive');
    }
    _bindings.attachFinalizer(this, _handle, this);
  }

  final NativeBindings _bindings;
  final int _handle;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void ensureAlive() {
    if (_disposed) {
      throw StateError('$runtimeType has already been disposed');
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _checkCall(_bindings.release(_handle), '$runtimeType.dispose');
    _bindings.detachFinalizer(this);
    _disposed = true;
  }
}
