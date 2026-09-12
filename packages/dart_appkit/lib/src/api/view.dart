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

/// One immutable native snapshot used by synchronous plain-text Services.
final class ServicesTextRequestorConfiguration {
  const ServicesTextRequestorConfiguration({
    this.selectionText,
    this.acceptsReturnedText = true,
    this.maximumReturnedTextUtf8Bytes = maximumTextUtf8Bytes,
  });

  static const int maximumTextUtf8Bytes =
      dartAppKitServicesMaximumTextUtf8Bytes;

  final String? selectionText;
  final bool acceptsReturnedText;
  final int maximumReturnedTextUtf8Bytes;

  NativeServicesTextRequestorConfiguration get _native {
    if (selectionText == null && !acceptsReturnedText) {
      throw ArgumentError(
        'a Services requestor must send a selection, accept returned text, or both',
      );
    }
    RangeError.checkValueInInterval(
      maximumReturnedTextUtf8Bytes,
      1,
      maximumTextUtf8Bytes,
      'maximumReturnedTextUtf8Bytes',
    );
    final String? selection = selectionText;
    if (selection != null &&
        utf8.encode(selection).length > maximumTextUtf8Bytes) {
      throw ArgumentError.value(
        selection,
        'selectionText',
        'exceeds the Services UTF-8 byte limit',
      );
    }
    return NativeServicesTextRequestorConfiguration(
      selectionText: selection,
      acceptsReturnedText: acceptsReturnedText,
      maximumReturnedTextUtf8Bytes: maximumReturnedTextUtf8Bytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServicesTextRequestorConfiguration &&
      other.selectionText == selectionText &&
      other.acceptsReturnedText == acceptsReturnedText &&
      other.maximumReturnedTextUtf8Bytes == maximumReturnedTextUtf8Bytes;

  @override
  int get hashCode => Object.hash(
    selectionText,
    acceptsReturnedText,
    maximumReturnedTextUtf8Bytes,
  );
}

/// One immutable copy-only text/file-URL drop-destination policy.
final class DropDestinationConfiguration {
  const DropDestinationConfiguration({
    this.acceptsPlainText = true,
    this.acceptsFileUrls = true,
    this.maximumTextUtf8Bytes = maximumTextUtf8BytesLimit,
    this.maximumFileUrlCount = maximumFileUrlCountLimit,
    this.maximumFileUrlUtf8Bytes = maximumFileUrlUtf8BytesLimit,
    this.maximumTotalFileUrlUtf8Bytes = maximumTotalFileUrlUtf8BytesLimit,
  });

  static const int maximumTextUtf8BytesLimit =
      dartAppKitDropMaximumTextUtf8Bytes;
  static const int maximumFileUrlCountLimit = dartAppKitDropMaximumFileUrlCount;
  static const int maximumFileUrlUtf8BytesLimit =
      dartAppKitDropMaximumFileUrlUtf8Bytes;
  static const int maximumTotalFileUrlUtf8BytesLimit =
      dartAppKitDropMaximumTotalFileUrlUtf8Bytes;

  final bool acceptsPlainText;
  final bool acceptsFileUrls;
  final int maximumTextUtf8Bytes;
  final int maximumFileUrlCount;
  final int maximumFileUrlUtf8Bytes;
  final int maximumTotalFileUrlUtf8Bytes;

  NativeDropDestinationConfiguration get _native {
    if (!acceptsPlainText && !acceptsFileUrls) {
      throw ArgumentError(
        'a drop destination must accept plain text, file URLs, or both',
      );
    }
    RangeError.checkValueInInterval(
      maximumTextUtf8Bytes,
      1,
      maximumTextUtf8BytesLimit,
      'maximumTextUtf8Bytes',
    );
    RangeError.checkValueInInterval(
      maximumFileUrlCount,
      1,
      maximumFileUrlCountLimit,
      'maximumFileUrlCount',
    );
    RangeError.checkValueInInterval(
      maximumFileUrlUtf8Bytes,
      1,
      maximumFileUrlUtf8BytesLimit,
      'maximumFileUrlUtf8Bytes',
    );
    RangeError.checkValueInInterval(
      maximumTotalFileUrlUtf8Bytes,
      maximumFileUrlUtf8Bytes,
      maximumTotalFileUrlUtf8BytesLimit,
      'maximumTotalFileUrlUtf8Bytes',
    );
    return NativeDropDestinationConfiguration(
      acceptsPlainText: acceptsPlainText,
      acceptsFileUrls: acceptsFileUrls,
      maximumTextUtf8Bytes: maximumTextUtf8Bytes,
      maximumFileUrlCount: maximumFileUrlCount,
      maximumFileUrlUtf8Bytes: maximumFileUrlUtf8Bytes,
      maximumTotalFileUrlUtf8Bytes: maximumTotalFileUrlUtf8Bytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DropDestinationConfiguration &&
      other.acceptsPlainText == acceptsPlainText &&
      other.acceptsFileUrls == acceptsFileUrls &&
      other.maximumTextUtf8Bytes == maximumTextUtf8Bytes &&
      other.maximumFileUrlCount == maximumFileUrlCount &&
      other.maximumFileUrlUtf8Bytes == maximumFileUrlUtf8Bytes &&
      other.maximumTotalFileUrlUtf8Bytes == maximumTotalFileUrlUtf8Bytes;

  @override
  int get hashCode => Object.hash(
    acceptsPlainText,
    acceptsFileUrls,
    maximumTextUtf8Bytes,
    maximumFileUrlCount,
    maximumFileUrlUtf8Bytes,
    maximumTotalFileUrlUtf8Bytes,
  );
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
      _servicesTextEventController =
          StreamController<ViewServicesTextReceivedEvent>.broadcast(sync: true),
      _dropEventController = StreamController<ViewDropPerformedEvent>.broadcast(
        sync: true,
      ),
      super(_application._bindings, handle) {
    _application._registerView(this);
  }

  final AppKitApplication _application;

  /// Package-owned base behavior, or `null` for provider/container views.
  final ViewConfiguration? viewConfiguration;
  final StreamController<ViewQuickLookRequestedEvent> _quickLookEventController;
  final StreamController<ViewServicesTextReceivedEvent>
  _servicesTextEventController;
  final StreamController<ViewDropPerformedEvent> _dropEventController;

  SecureInputIndicatorState _secureInputIndicatorState =
      SecureInputIndicatorState.hidden;
  Menu? _contextMenu;
  bool _quickLookRequestsEnabled = false;
  ServicesTextRequestorConfiguration? _servicesTextRequestor;
  DropDestinationConfiguration? _dropDestination;

  Stream<ViewQuickLookRequestedEvent> get onQuickLookRequested =>
      _quickLookEventController.stream;

  Stream<ViewServicesTextReceivedEvent> get onServicesTextReceived =>
      _servicesTextEventController.stream;

  Stream<ViewDropPerformedEvent> get onDropPerformed =>
      _dropEventController.stream;

  DropDestinationConfiguration? get dropDestination {
    ensureAlive();
    return _dropDestination;
  }

  set dropDestination(DropDestinationConfiguration? value) {
    ensureAlive();
    if (value == _dropDestination) {
      return;
    }
    if (value != null && _application.eventProtocolVersion < 11) {
      throw UnsupportedError(
        'drop destinations require native event protocol 11',
      );
    }
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeDropDestinationBindings) {
      throw const AppKitNativeException(
        operation: 'View.dropDestination',
        status: 8,
        nativeMessage: 'native bridge does not support drop destinations',
      );
    }
    _checkCall(
      (bindings as NativeDropDestinationBindings).viewSetDropDestination(
        _handle,
        value?._native,
      ),
      'View.dropDestination',
    );
    _dropDestination = value;
  }

  ServicesTextRequestorConfiguration? get servicesTextRequestor {
    ensureAlive();
    return _servicesTextRequestor;
  }

  set servicesTextRequestor(ServicesTextRequestorConfiguration? value) {
    ensureAlive();
    if (value == _servicesTextRequestor) {
      return;
    }
    if (value != null && _application.eventProtocolVersion < 10) {
      throw UnsupportedError(
        'Services returned text requires native event protocol 10',
      );
    }
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeServicesTextRequestorBindings) {
      throw const AppKitNativeException(
        operation: 'View.servicesTextRequestor',
        status: 8,
        nativeMessage: 'native bridge does not support Services requestors',
      );
    }
    _checkCall(
      (bindings as NativeServicesTextRequestorBindings)
          .viewSetServicesTextRequestor(_handle, value?._native),
      'View.servicesTextRequestor',
    );
    _servicesTextRequestor = value;
  }

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

  void _dispatchServicesText(ViewServicesTextReceivedEvent event) {
    if (!isDisposed) {
      _servicesTextEventController.add(event);
    }
  }

  void _dispatchDrop(ViewDropPerformedEvent event) {
    if (!isDisposed) {
      _dropEventController.add(event);
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
    unawaited(_servicesTextEventController.close());
    unawaited(_dropEventController.close());
  }
}
