part of '../api.dart';

enum GlobalHotKeyRegistrationFailure { unsupportedKey, conflict, systemFailure }

final class GlobalHotKeyRegistrationException implements Exception {
  const GlobalHotKeyRegistrationException({
    required this.reason,
    required this.keyCode,
    required this.modifiers,
    required this.nativeStatus,
    required this.nativeMessage,
  });

  final GlobalHotKeyRegistrationFailure reason;
  final int keyCode;
  final ModifierKeys modifiers;
  final int nativeStatus;
  final String nativeMessage;

  @override
  String toString() =>
      'GlobalHotKeyRegistrationException($reason, keyCode $keyCode, '
      'modifiers ${modifiers.bits}, native status $nativeStatus): '
      '$nativeMessage';
}

/// One immutable, exclusive system-wide physical-key registration.
final class GlobalHotKey extends _NativeResource {
  factory GlobalHotKey({
    required int keyCode,
    required ModifierKeys modifiers,
  }) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    if (application.eventProtocolVersion < 8) {
      throw UnsupportedError('global hot keys require native event protocol 8');
    }
    if (keyCode < minimumKeyCode || keyCode > maximumKeyCode) {
      throw GlobalHotKeyRegistrationException(
        reason: GlobalHotKeyRegistrationFailure.unsupportedKey,
        keyCode: keyCode,
        modifiers: modifiers,
        nativeStatus: 1,
        nativeMessage:
            'macOS virtual key code must be between $minimumKeyCode and '
            '$maximumKeyCode',
      );
    }
    if (modifiers.bits == 0 ||
        modifiers.bits < 0 ||
        (modifiers.bits & ~supportedModifierBits) != 0) {
      throw ArgumentError.value(
        modifiers.bits,
        'modifiers',
        'must contain Shift, Control, Option, or Command only',
      );
    }
    final NativeBindings nativeBindings = application._bindings;
    if (nativeBindings is! NativeGlobalHotKeyBindings) {
      throw UnsupportedError(
        'the native bridge does not expose global hot-key registration',
      );
    }
    final NativeValueResult<int> result =
        (nativeBindings as NativeGlobalHotKeyBindings).globalHotKeyRegister(
          keyCode: keyCode,
          modifiers: modifiers.bits,
        );
    if (!result.isSuccess || result.value == null) {
      throw GlobalHotKeyRegistrationException(
        reason: result.status == dartAppKitStatusGlobalHotKeyConflict
            ? GlobalHotKeyRegistrationFailure.conflict
            : GlobalHotKeyRegistrationFailure.systemFailure,
        keyCode: keyCode,
        modifiers: modifiers,
        nativeStatus: result.status,
        nativeMessage: result.message,
      );
    }
    final GlobalHotKey hotKey = GlobalHotKey._(
      application,
      result.value!,
      keyCode,
      modifiers,
    );
    application._registerGlobalHotKey(hotKey);
    return hotKey;
  }

  GlobalHotKey._(this._application, int handle, this.keyCode, this.modifiers)
    : _eventController = StreamController<GlobalHotKeyPressedEvent>.broadcast(
        sync: true,
      ),
      super(_application._bindings, handle);

  static const int minimumKeyCode = 0;
  static const int maximumKeyCode = 127;
  static const int supportedModifierBits =
      ModifierKeys.shiftBit |
      ModifierKeys.controlBit |
      ModifierKeys.optionBit |
      ModifierKeys.commandBit;

  final AppKitApplication _application;
  final StreamController<GlobalHotKeyPressedEvent> _eventController;
  final int keyCode;
  final ModifierKeys modifiers;

  Stream<GlobalHotKeyPressedEvent> get onPressed => _eventController.stream;

  void _dispatch(GlobalHotKeyPressedEvent event) {
    if (!isDisposed) {
      _eventController.add(event);
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    super.dispose();
    _application._unregisterGlobalHotKey(this);
    unawaited(_eventController.close());
  }
}
