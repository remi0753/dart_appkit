part of '../api.dart';

enum SecureEventInputFailure { unavailable, alreadyOwned, systemFailure }

final class SecureEventInputException implements Exception {
  const SecureEventInputException({
    required this.operation,
    required this.reason,
    required this.nativeStatus,
    required this.nativeMessage,
  });

  final String operation;
  final SecureEventInputFailure reason;
  final int nativeStatus;
  final String nativeMessage;

  @override
  String toString() {
    final String detail = nativeMessage.isEmpty
        ? 'native status $nativeStatus'
        : nativeMessage;
    return 'SecureEventInputException($operation, $reason): $detail';
  }
}

final class SecureEventInputSnapshot {
  const SecureEventInputSnapshot({
    required this.desired,
    required this.ownedEnabled,
    required this.systemEnabled,
    required this.lastOsStatus,
  });

  /// Whether this resource should own Secure Event Input while active.
  final bool desired;

  /// Whether this bridge successfully acquired its balanced reference.
  final bool ownedEnabled;

  /// Observed global state, which may also be owned by another process.
  final bool systemEnabled;

  /// Last Carbon OSStatus observed while applying the retained request.
  final int lastOsStatus;
}

/// Bridge-wide balanced owner for macOS Secure Event Input.
///
/// The native owner automatically yields its reference while the application
/// is inactive and reacquires it on activation while the request remains true.
/// Dispose this resource during application shutdown.
final class SecureEventInput extends _NativeResource {
  factory SecureEventInput() {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final NativeBindings bindings = application._bindings;
    if (bindings is! NativeSecureEventInputBindings) {
      throw const SecureEventInputException(
        operation: 'SecureEventInput.create',
        reason: SecureEventInputFailure.unavailable,
        nativeStatus: 8,
        nativeMessage: 'native bridge does not support Secure Event Input',
      );
    }
    final NativeSecureEventInputBindings secureBindings =
        bindings as NativeSecureEventInputBindings;
    final NativeValueResult<int> result = secureBindings
        .secureEventInputCreate();
    if (!result.isSuccess || result.value == null) {
      throw _secureEventInputException(
        'SecureEventInput.create',
        result.status,
        result.message,
      );
    }
    return SecureEventInput._(bindings, result.value!);
  }

  SecureEventInput._(NativeBindings bindings, int handle)
    : super(bindings, handle);

  NativeSecureEventInputBindings get _secureBindings =>
      _bindings as NativeSecureEventInputBindings;

  void setDesired(bool desired) {
    ensureAlive();
    final NativeCallResult result = _secureBindings.secureEventInputSetDesired(
      _handle,
      desired,
    );
    if (!result.isSuccess) {
      throw _secureEventInputException(
        'SecureEventInput.setDesired',
        result.status,
        result.message,
      );
    }
  }

  SecureEventInputSnapshot snapshot() {
    ensureAlive();
    final NativeValueResult<NativeSecureEventInputSnapshot> result =
        _secureBindings.secureEventInputGetSnapshot(_handle);
    if (!result.isSuccess || result.value == null) {
      throw _secureEventInputException(
        'SecureEventInput.snapshot',
        result.status,
        result.message,
      );
    }
    final NativeSecureEventInputSnapshot native = result.value!;
    return SecureEventInputSnapshot(
      desired: native.desired,
      ownedEnabled: native.ownedEnabled,
      systemEnabled: native.systemEnabled,
      lastOsStatus: native.lastOsStatus,
    );
  }
}

SecureEventInputException _secureEventInputException(
  String operation,
  int status,
  String message,
) {
  final SecureEventInputFailure reason = switch (status) {
    8 => SecureEventInputFailure.unavailable,
    10 => SecureEventInputFailure.alreadyOwned,
    _ => SecureEventInputFailure.systemFailure,
  };
  return SecureEventInputException(
    operation: operation,
    reason: reason,
    nativeStatus: status,
    nativeMessage: message,
  );
}

int nativeSecureEventInputHandleForTesting(SecureEventInput secureInput) =>
    secureInput._handle;
