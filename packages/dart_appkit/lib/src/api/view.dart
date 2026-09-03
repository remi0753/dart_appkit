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

  View._(NativeBindings bindings, int handle) : super(bindings, handle);
}
