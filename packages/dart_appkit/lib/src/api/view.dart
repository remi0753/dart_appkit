part of '../api.dart';

/// Immutable behavior selected when a plain or simple text [View] is created.
final class ViewConfiguration {
  const ViewConfiguration({
    this.acceptsFirstResponder = true,
    this.autoresizesWidth = true,
    this.autoresizesHeight = true,
  });

  final bool acceptsFirstResponder;
  final bool autoresizesWidth;
  final bool autoresizesHeight;

  NativeViewConfiguration get _native => NativeViewConfiguration(
    acceptsFirstResponder: acceptsFirstResponder,
    autoresizingMask:
        (autoresizesWidth ? dartAppKitViewAutoresizingWidth : 0) |
        (autoresizesHeight ? dartAppKitViewAutoresizingHeight : 0),
  );

  @override
  bool operator ==(Object other) =>
      other is ViewConfiguration &&
      other.acceptsFirstResponder == acceptsFirstResponder &&
      other.autoresizesWidth == autoresizesWidth &&
      other.autoresizesHeight == autoresizesHeight;

  @override
  int get hashCode =>
      Object.hash(acceptsFirstResponder, autoresizesWidth, autoresizesHeight);
}

base class View extends _NativeResource {
  factory View({ViewConfiguration configuration = const ViewConfiguration()}) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int handle = _checkValue<int>(
      application._bindings.viewCreate(configuration._native),
      'View.create',
    );
    return View._(application._bindings, handle, configuration);
  }

  /// Creates a provider-owned native view.
  ///
  /// Its focus, autoresizing, and presentation remain the provider's policy;
  /// [ViewConfiguration] applies only to package-created base and text views.
  factory View.custom(String providerIdentifier) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int handle = _checkValue<int>(
      application._bindings.customViewCreate(providerIdentifier),
      'View.custom',
    );
    return View._(application._bindings, handle, null);
  }

  View._(NativeBindings bindings, int handle, this.viewConfiguration)
    : super(bindings, handle);

  /// Package-owned base behavior, or `null` for provider/container views.
  final ViewConfiguration? viewConfiguration;

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
