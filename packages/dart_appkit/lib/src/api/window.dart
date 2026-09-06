part of '../api.dart';

/// Controls native responder dispatch after window key-event arbitration.
enum KeyEventRouting {
  /// Post key events to Dart and continue normal AppKit responder dispatch.
  dartAndAppKit,

  /// Let native menu shortcuts run, then post remaining keys only to Dart.
  dartOnly,

  /// Deliver keys only through the AppKit first-responder/input-client chain.
  appKitOnly,
}

final class Window extends _NativeResource {
  factory Window({required Rect frame, required String title}) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int handle = _checkValue<int>(
      application._bindings.windowCreate(
        x: frame.left,
        y: frame.top,
        width: frame.width,
        height: frame.height,
        title: title,
      ),
      'Window.create',
    );
    final Window window = Window._(application, handle, frame, title);
    application._registerWindow(window);
    return window;
  }

  Window._(this._application, int handle, this.frame, this._title)
    : _eventController = StreamController<WindowEvent>.broadcast(sync: true),
      super(_application._bindings, handle);

  final AppKitApplication _application;
  final StreamController<WindowEvent> _eventController;
  final Rect frame;

  String _title;
  View? _contentView;
  bool _closed = false;
  bool _focused = false;
  bool _visible = false;
  bool _occluded = true;
  bool _defersCloseRequests = false;
  KeyEventRouting _keyEventRouting = KeyEventRouting.dartAndAppKit;
  double? _backingScaleFactor;
  AppKitScreen? _screen;

  Stream<WindowEvent> get events => _eventController.stream;

  Stream<WindowClosedEvent> get onClosed => events
      .where((WindowEvent event) => event is WindowClosedEvent)
      .map((WindowEvent event) => event as WindowClosedEvent);

  Stream<WindowResizedEvent> get onResized => events
      .where((WindowEvent event) => event is WindowResizedEvent)
      .map((WindowEvent event) => event as WindowResizedEvent);

  Stream<WindowCloseRequestedEvent> get onCloseRequested => events
      .where((WindowEvent event) => event is WindowCloseRequestedEvent)
      .map((WindowEvent event) => event as WindowCloseRequestedEvent);

  Stream<WindowFocusChangedEvent> get onFocusChanged => events
      .where((WindowEvent event) => event is WindowFocusChangedEvent)
      .map((WindowEvent event) => event as WindowFocusChangedEvent);

  Stream<WindowVisibilityChangedEvent> get onVisibilityChanged => events
      .where((WindowEvent event) => event is WindowVisibilityChangedEvent)
      .map((WindowEvent event) => event as WindowVisibilityChangedEvent);

  Stream<WindowOcclusionChangedEvent> get onOcclusionChanged => events
      .where((WindowEvent event) => event is WindowOcclusionChangedEvent)
      .map((WindowEvent event) => event as WindowOcclusionChangedEvent);

  Stream<WindowBackingScaleChangedEvent> get onBackingScaleChanged => events
      .where((WindowEvent event) => event is WindowBackingScaleChangedEvent)
      .map((WindowEvent event) => event as WindowBackingScaleChangedEvent);

  Stream<WindowScreenChangedEvent> get onScreenChanged => events
      .where((WindowEvent event) => event is WindowScreenChangedEvent)
      .map((WindowEvent event) => event as WindowScreenChangedEvent);

  String get title {
    ensureAlive();
    return _title;
  }

  set title(String value) {
    ensureAlive();
    _checkCall(_bindings.windowSetTitle(_handle, value), 'Window.title');
    _title = value;
  }

  View? get contentView {
    ensureAlive();
    return _contentView;
  }

  set contentView(View value) {
    ensureAlive();
    value.ensureAlive();
    if (!identical(value._bindings, _bindings)) {
      throw StateError(
        'content view belongs to a different AppKit application',
      );
    }
    _checkCall(
      _bindings.windowSetContentView(_handle, value._handle),
      'Window.contentView',
    );
    _contentView = value;
  }

  bool get isClosed => _closed;
  bool get isFocused => _focused;
  bool get isVisible => _visible;
  bool get isOccluded => _occluded;
  double? get backingScaleFactor => _backingScaleFactor;
  AppKitScreen? get screen => _screen;

  bool get defersCloseRequests => _defersCloseRequests;

  KeyEventRouting get keyEventRouting {
    ensureAlive();
    return _keyEventRouting;
  }

  set keyEventRouting(KeyEventRouting value) {
    ensureAlive();
    if (value == _keyEventRouting) {
      return;
    }
    final int nativeValue = switch (value) {
      KeyEventRouting.dartAndAppKit => 0,
      KeyEventRouting.dartOnly => 1,
      KeyEventRouting.appKitOnly => 2,
    };
    _checkCall(
      _bindings.windowSetKeyEventRouting(_handle, nativeValue),
      'Window.keyEventRouting',
    );
    _keyEventRouting = value;
  }

  set defersCloseRequests(bool value) {
    ensureAlive();
    if (value && _application.eventProtocolVersion < 4) {
      throw UnsupportedError(
        'close request deferral requires native event protocol 4',
      );
    }
    if (value == _defersCloseRequests) {
      return;
    }
    _checkCall(
      _bindings.windowSetCloseRequestDeferral(_handle, value),
      'Window.defersCloseRequests',
    );
    _defersCloseRequests = value;
  }

  void show() {
    ensureAlive();
    _checkCall(_bindings.windowShow(_handle), 'Window.show');
  }

  void close() {
    ensureAlive();
    if (_closed) {
      return;
    }
    _checkCall(_bindings.windowClose(_handle), 'Window.close');
  }

  void requestClose() {
    ensureAlive();
    if (_closed) {
      return;
    }
    _checkCall(_bindings.windowRequestClose(_handle), 'Window.requestClose');
  }

  void replyToCloseRequest(
    WindowCloseRequestedEvent request, {
    required bool allow,
  }) {
    ensureAlive();
    if (request.windowHandle != _handle) {
      throw ArgumentError.value(
        request.windowHandle,
        'request',
        'close request belongs to another window',
      );
    }
    _checkCall(
      _bindings.windowReplyToCloseRequest(
        handle: _handle,
        operationId: request.operationId,
        allow: allow,
      ),
      'Window.replyToCloseRequest',
    );
  }

  void _updateState(AppKitEvent event) {
    if (isDisposed || event is! WindowEvent) {
      return;
    }
    switch (event) {
      case WindowClosedEvent():
        _closed = true;
        _focused = false;
        _visible = false;
      case WindowFocusChangedEvent(:final isFocused):
        _focused = isFocused;
      case WindowVisibilityChangedEvent(:final isVisible):
        _visible = isVisible;
      case WindowOcclusionChangedEvent(:final isOccluded):
        _occluded = isOccluded;
      case WindowBackingScaleChangedEvent(:final backingScaleFactor):
        _backingScaleFactor = backingScaleFactor;
      case WindowScreenChangedEvent(:final screen):
        _screen = screen;
      case WindowCloseRequestedEvent() ||
          WindowResizedEvent() ||
          AppKitMouseEvent() ||
          AppKitKeyEvent():
        break;
    }
  }

  void _dispatch(AppKitEvent event) {
    if (isDisposed || event is! WindowEvent) {
      return;
    }
    _eventController.add(event);
  }

  @override
  void dispose() {
    if (isDisposed) {
      return;
    }
    _application._unregisterWindow(this);
    super.dispose();
    _contentView = null;
    _defersCloseRequests = false;
    _keyEventRouting = KeyEventRouting.dartAndAppKit;
    unawaited(_eventController.close());
  }
}
