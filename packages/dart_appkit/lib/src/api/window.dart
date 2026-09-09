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

/// Immutable native style selected when a [Window] is created.
final class WindowConfiguration {
  const WindowConfiguration({
    this.titled = true,
    this.closable = true,
    this.miniaturizable = true,
    this.resizable = true,
  });

  final bool titled;
  final bool closable;
  final bool miniaturizable;
  final bool resizable;

  int get _nativeStyleMask =>
      (titled ? dartAppKitWindowStyleTitled : 0) |
      (closable ? dartAppKitWindowStyleClosable : 0) |
      (miniaturizable ? dartAppKitWindowStyleMiniaturizable : 0) |
      (resizable ? dartAppKitWindowStyleResizable : 0);

  @override
  bool operator ==(Object other) =>
      other is WindowConfiguration &&
      other.titled == titled &&
      other.closable == closable &&
      other.miniaturizable == miniaturizable &&
      other.resizable == resizable;

  @override
  int get hashCode => Object.hash(titled, closable, miniaturizable, resizable);
}

/// Immutable sRGB components for one native window-tab marker.
final class WindowTabColor {
  factory WindowTabColor({
    required double red,
    required double green,
    required double blue,
    double alpha = 1,
  }) {
    for (final MapEntry<String, double> component in <String, double>{
      'red': red,
      'green': green,
      'blue': blue,
      'alpha': alpha,
    }.entries) {
      if (!component.value.isFinite ||
          component.value < 0 ||
          component.value > 1) {
        throw RangeError.range(component.value, 0, 1, component.key);
      }
    }
    return WindowTabColor._(red: red, green: green, blue: blue, alpha: alpha);
  }

  const WindowTabColor._({
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
  });

  final double red;
  final double green;
  final double blue;
  final double alpha;

  @override
  bool operator ==(Object other) =>
      other is WindowTabColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(red, green, blue, alpha);
}

final class Window extends _NativeResource {
  factory Window({
    required Rect frame,
    required String title,
    WindowConfiguration configuration = const WindowConfiguration(),
  }) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int handle = _checkValue<int>(
      application._bindings.windowCreate(
        x: frame.left,
        y: frame.top,
        width: frame.width,
        height: frame.height,
        title: title,
        styleMask: configuration._nativeStyleMask,
      ),
      'Window.create',
    );
    final Window window = Window._(
      application,
      handle,
      frame,
      title,
      configuration,
    );
    application._registerWindow(window);
    return window;
  }

  Window._(
    this._application,
    int handle,
    this._frame,
    this._title,
    this.configuration,
  ) : _eventController = StreamController<WindowEvent>.broadcast(sync: true),
      super(_application._bindings, handle);

  final AppKitApplication _application;
  final StreamController<WindowEvent> _eventController;
  final WindowConfiguration configuration;
  Rect _frame;

  String _title;
  View? _contentView;
  bool _closed = false;
  bool _focused = false;
  bool _visible = false;
  bool _occluded = true;
  bool _defersCloseRequests = false;
  KeyEventRouting _keyEventRouting = KeyEventRouting.dartAndAppKit;
  String? _representedFilePath;
  WindowTabColor? _tabColor;
  double? _backingScaleFactor;
  AppKitScreen? _screen;
  bool _fullscreen = false;
  bool? _requestedFullscreen;

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

  Stream<WindowFrameChangedEvent> get onFrameChanged => events
      .where((WindowEvent event) => event is WindowFrameChangedEvent)
      .map((WindowEvent event) => event as WindowFrameChangedEvent);

  Stream<WindowFullscreenChangedEvent> get onFullscreenChanged => events
      .where((WindowEvent event) => event is WindowFullscreenChangedEvent)
      .map((WindowEvent event) => event as WindowFullscreenChangedEvent);

  Rect get frame {
    ensureAlive();
    return _frame;
  }

  set frame(Rect value) {
    ensureAlive();
    _validateFrame(value);
    if (_frame == value) return;
    _checkCall(
      _bindings.windowSetFrame(
        handle: _handle,
        x: value.left,
        y: value.top,
        width: value.width,
        height: value.height,
      ),
      'Window.frame',
    );
    _frame = value;
  }

  String get title {
    ensureAlive();
    return _title;
  }

  set title(String value) {
    ensureAlive();
    _checkCall(_bindings.windowSetTitle(_handle, value), 'Window.title');
    _title = value;
  }

  /// Absolute local path represented by the standard window proxy icon.
  String? get representedFilePath {
    ensureAlive();
    return _representedFilePath;
  }

  set representedFilePath(String? value) {
    ensureAlive();
    if (value != null && !_isValidRepresentedFilePath(value)) {
      throw ArgumentError.value(
        value,
        'representedFilePath',
        'must be a valid absolute UTF-8 path of at most 4096 bytes',
      );
    }
    if (_representedFilePath == value) return;
    _checkCall(
      _bindings.windowSetRepresentedFilePath(_handle, value),
      'Window.representedFilePath',
    );
    _representedFilePath = value;
  }

  /// Optional color shown as a native tab accessory marker.
  WindowTabColor? get tabColor {
    ensureAlive();
    return _tabColor;
  }

  set tabColor(WindowTabColor? value) {
    ensureAlive();
    if (_tabColor == value) return;
    _checkCall(
      _bindings.windowSetTabColor(
        handle: _handle,
        hasColor: value != null,
        red: value?.red ?? 0,
        green: value?.green ?? 0,
        blue: value?.blue ?? 0,
        alpha: value?.alpha ?? 0,
      ),
      'Window.tabColor',
    );
    _tabColor = value;
  }

  void addTabbedWindow(Window tabbedWindow) {
    ensureAlive();
    tabbedWindow.ensureAlive();
    if (identical(tabbedWindow, this)) {
      throw ArgumentError.value(
        tabbedWindow,
        'tabbedWindow',
        'a window cannot tab with itself',
      );
    }
    if (!identical(tabbedWindow._bindings, _bindings)) {
      throw StateError('tabbed window belongs to a different application');
    }
    _checkCall(
      _bindings.windowAddTabbedWindow(_handle, tabbedWindow._handle),
      'Window.addTabbedWindow',
    );
  }

  void removeFromTabGroup() {
    ensureAlive();
    _checkCall(
      _bindings.windowRemoveFromTabGroup(_handle),
      'Window.removeFromTabGroup',
    );
  }

  void selectTab() {
    ensureAlive();
    _checkCall(_bindings.windowSelectTab(_handle), 'Window.selectTab');
  }

  void makeFirstResponder(View view) {
    ensureAlive();
    view.ensureAlive();
    if (!identical(view._bindings, _bindings)) {
      throw StateError(
        'first responder view belongs to a different application',
      );
    }
    _checkCall(
      _bindings.windowMakeFirstResponder(_handle, view._handle),
      'Window.makeFirstResponder',
    );
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
  bool get isFullscreen => _fullscreen;

  /// Requests native fullscreen entry or exit.
  ///
  /// Completion is asynchronous; [isFullscreen] changes only when AppKit
  /// publishes the corresponding [WindowFullscreenChangedEvent].
  void setFullscreen(bool enabled) {
    ensureAlive();
    if (_requestedFullscreen == enabled ||
        _requestedFullscreen == null && _fullscreen == enabled) {
      return;
    }
    _checkCall(
      _bindings.windowSetFullscreen(_handle, enabled),
      'Window.setFullscreen',
    );
    _requestedFullscreen = enabled;
  }

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
      case WindowFrameChangedEvent(:final frame):
        _frame = frame;
      case WindowFullscreenChangedEvent(:final isFullscreen):
        _fullscreen = isFullscreen;
        _requestedFullscreen = null;
      case WindowCloseRequestedEvent() ||
          WindowResizedEvent() ||
          AppKitMouseEvent() ||
          AppKitScrollEvent() ||
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
    _representedFilePath = null;
    _tabColor = null;
    _fullscreen = false;
    _requestedFullscreen = null;
    unawaited(_eventController.close());
  }

  static bool _isValidRepresentedFilePath(String value) {
    if (!value.startsWith('/') || value.isEmpty) return false;
    final List<int> codeUnits = value.codeUnits;
    for (var index = 0; index < codeUnits.length; index++) {
      final int codeUnit = codeUnits[index];
      if (codeUnit == 0) return false;
      if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
        if (++index >= codeUnits.length ||
            codeUnits[index] < 0xdc00 ||
            codeUnits[index] > 0xdfff) {
          return false;
        }
      } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
        return false;
      }
    }
    return utf8.encode(value).length <= 4096;
  }

  static void _validateFrame(Rect value) {
    if (!value.left.isFinite ||
        !value.top.isFinite ||
        !value.width.isFinite ||
        !value.height.isFinite ||
        value.width <= 0 ||
        value.height <= 0) {
      throw ArgumentError.value(
        value,
        'frame',
        'must have finite coordinates and positive finite dimensions',
      );
    }
  }
}
