part of '../api.dart';

base class View extends _NativeResource {
  factory View() {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int handle = _checkValue<int>(
      application._bindings.viewCreate(),
      'View.create',
    );
    return View._(application._bindings, handle);
  }

  factory View.custom(String providerIdentifier) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int handle = _checkValue<int>(
      application._bindings.customViewCreate(providerIdentifier),
      'View.custom',
    );
    return View._(application._bindings, handle);
  }

  View._(NativeBindings bindings, int handle) : super(bindings, handle);

  /// Performs the opaque, synchronous operation registered by this custom
  /// view's native provider. The payload is copied for the call and is never
  /// retained by dart_appkit.
  void performCustomOperation(Uint8List payload) {
    ensureAlive();
    _checkCall(
      _bindings.customViewPerformOperation(_handle, payload),
      'View.performCustomOperation',
    );
  }
}
