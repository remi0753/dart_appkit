part of '../api.dart';

/// One bounded AppKit dictionary lookup request and its baseline geometry.
final class DefinitionPresentation {
  const DefinitionPresentation({
    required this.text,
    required this.baselineX,
    required this.baselineY,
    this.font = const TextViewFont.monospacedSystem(),
  });

  static const int maximumTextUtf8Bytes =
      dartAppKitDefinitionMaximumTextUtf8Bytes;

  final String text;
  final double baselineX;
  final double baselineY;
  final TextViewFont font;

  NativeDefinitionPresentation get _native {
    if (text.isEmpty || !_isSafeDisplayText(text, maximumTextUtf8Bytes)) {
      throw ArgumentError.value(
        text,
        'text',
        'must be non-empty bounded text without controls or invisible scalars',
      );
    }
    if (!baselineX.isFinite || !baselineY.isFinite) {
      throw ArgumentError('definition baseline coordinates must be finite');
    }
    font._validate();
    return NativeDefinitionPresentation(
      text: text,
      fontKind: font.kind.index,
      fontWeight: font.weight.index,
      fontSize: font.size,
      fontFamily: font.family,
      baselineX: baselineX,
      baselineY: baselineY,
    );
  }
}

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
    return View._(application, handle, configuration);
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
    return View._(application, handle, null);
  }

  View._(this._application, int handle, this.viewConfiguration)
    : _quickLookEventController =
          StreamController<ViewQuickLookRequestedEvent>.broadcast(sync: true),
      super(_application._bindings, handle) {
    _application._registerView(this);
  }

  final AppKitApplication _application;

  /// Package-owned base behavior, or `null` for provider/container views.
  final ViewConfiguration? viewConfiguration;
  final StreamController<ViewQuickLookRequestedEvent> _quickLookEventController;

  SecureInputIndicatorState _secureInputIndicatorState =
      SecureInputIndicatorState.hidden;
  Menu? _contextMenu;
  bool _quickLookRequestsEnabled = false;

  Stream<ViewQuickLookRequestedEvent> get onQuickLookRequested =>
      _quickLookEventController.stream;

  bool get quickLookRequestsEnabled {
    ensureAlive();
    return _quickLookRequestsEnabled;
  }

  set quickLookRequestsEnabled(bool value) {
    ensureAlive();
    if (value == _quickLookRequestsEnabled) {
      return;
    }
    if (value && _application.eventProtocolVersion < 9) {
      throw UnsupportedError(
        'Quick Look requests require native event protocol 9',
      );
    }
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeQuickLookBindings) {
      throw const AppKitNativeException(
        operation: 'View.quickLookRequestsEnabled',
        status: 8,
        nativeMessage: 'native bridge does not support Quick Look requests',
      );
    }
    _checkCall(
      (bindings as NativeQuickLookBindings).viewSetQuickLookRequestEnabled(
        _handle,
        value,
      ),
      'View.quickLookRequestsEnabled',
    );
    _quickLookRequestsEnabled = value;
  }

  /// Menu presented by AppKit for secondary-click and control-click gestures.
  Menu? get contextMenu {
    ensureAlive();
    return _contextMenu;
  }

  set contextMenu(Menu? value) {
    ensureAlive();
    value?.ensureAlive();
    if (value != null && !identical(value._bindings, _bindings)) {
      throw StateError(
        'context menu belongs to a different AppKit application',
      );
    }
    if (identical(value, _contextMenu)) {
      return;
    }
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeViewContextMenuBindings) {
      throw const AppKitNativeException(
        operation: 'View.contextMenu',
        status: 8,
        nativeMessage: 'native bridge does not support view context menus',
      );
    }
    _checkCall(
      (bindings as NativeViewContextMenuBindings).viewSetContextMenu(
        _handle,
        value?._handle ?? 0,
      ),
      'View.contextMenu',
    );
    final Menu? previous = _contextMenu;
    _contextMenu = value;
    previous?._detachContextView(this);
    value?._attachContextView(this);
  }

  /// Current non-interactive badge shown over this view.
  SecureInputIndicatorState get secureInputIndicatorState =>
      _secureInputIndicatorState;

  set secureInputIndicatorState(SecureInputIndicatorState state) {
    ensureAlive();
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeSecureEventInputBindings) {
      throw const AppKitNativeException(
        operation: 'View.secureInputIndicatorState',
        status: 8,
        nativeMessage: 'native bridge does not support secure-input indication',
      );
    }
    final NativeSecureEventInputBindings secureBindings =
        bindings as NativeSecureEventInputBindings;
    _checkCall(
      secureBindings.viewSetSecureInputIndicator(_handle, state._nativeValue),
      'View.secureInputIndicatorState',
    );
    _secureInputIndicatorState = state;
  }

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

  /// Presents one native dictionary/data-detector definition overlay.
  void showDefinition(DefinitionPresentation presentation) {
    ensureAlive();
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeQuickLookBindings) {
      throw const AppKitNativeException(
        operation: 'View.showDefinition',
        status: 8,
        nativeMessage: 'native bridge does not support definitions',
      );
    }
    _checkCall(
      (bindings as NativeQuickLookBindings).viewShowDefinition(
        _handle,
        presentation._native,
      ),
      'View.showDefinition',
    );
  }

  void _dispatchQuickLook(ViewQuickLookRequestedEvent event) {
    if (!isDisposed) {
      _quickLookEventController.add(event);
    }
  }

  void _contextMenuDisposed(Menu menu) {
    if (identical(_contextMenu, menu)) {
      _contextMenu = null;
    }
  }

  @override
  void dispose() {
    if (isDisposed) {
      return;
    }
    super.dispose();
    final Menu? menu = _contextMenu;
    _contextMenu = null;
    menu?._detachContextView(this);
    _application._unregisterView(this);
    unawaited(_quickLookEventController.close());
  }
}
