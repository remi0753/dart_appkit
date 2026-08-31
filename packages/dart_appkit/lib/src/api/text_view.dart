part of '../api.dart';

final class TextView extends _NativeResource {
  factory TextView() {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int handle = _checkValue<int>(
      application._bindings.textViewCreate(),
      'TextView.create',
    );
    return TextView._(application._bindings, handle);
  }

  TextView._(super.bindings, super.handle) : super();

  String _text = '';

  String get text {
    ensureAlive();
    return _text;
  }

  set text(String value) {
    ensureAlive();
    _checkCall(_bindings.textViewSetText(_handle, value), 'TextView.text');
    _text = value;
  }
}
