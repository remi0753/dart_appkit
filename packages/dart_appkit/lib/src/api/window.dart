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

/// Immutable sRGB color value for native window presentation.
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

/// Built-in shapes for the simple native window-tab accessory mechanism.
enum WindowTabAccessoryShape { rectangle, ellipse }

/// A screen role resolved from current AppKit state each time it is requested.
enum AppKitScreenSelection { main, mouse, menuBar }

/// Current screen geometry plus the scale needed before first presentation.
final class AppKitResolvedScreen {
  const AppKitResolvedScreen({
    required this.screen,
    required this.backingScaleFactor,
  });

  final AppKitScreen screen;
  final double backingScaleFactor;

  @override
  bool operator ==(Object other) =>
      other is AppKitResolvedScreen &&
      other.screen == screen &&
      other.backingScaleFactor == backingScaleFactor;

  @override
  int get hashCode => Object.hash(screen, backingScaleFactor);
}

/// Stable native ordering levels for generic window presentation.
enum WindowPresentationLevel { normal, floating, status }

/// Immutable window level and Spaces behavior.
final class WindowPresentationConfiguration {
  const WindowPresentationConfiguration({
    this.level = WindowPresentationLevel.normal,
    this.canJoinAllSpaces = false,
    this.fullScreenAuxiliary = false,
    this.stationary = false,
    this.transient = false,
  });

  final WindowPresentationLevel level;
  final bool canJoinAllSpaces;
  final bool fullScreenAuxiliary;
  final bool stationary;
  final bool transient;

  int get _nativeLevel => switch (level) {
    WindowPresentationLevel.normal => dartAppKitWindowLevelNormal,
    WindowPresentationLevel.floating => dartAppKitWindowLevelFloating,
    WindowPresentationLevel.status => dartAppKitWindowLevelStatus,
  };

  int get _nativeCollectionBehaviorMask =>
      (canJoinAllSpaces
          ? dartAppKitWindowCollectionBehaviorCanJoinAllSpaces
          : 0) |
      (fullScreenAuxiliary
          ? dartAppKitWindowCollectionBehaviorFullScreenAuxiliary
          : 0) |
      (stationary ? dartAppKitWindowCollectionBehaviorStationary : 0) |
      (transient ? dartAppKitWindowCollectionBehaviorTransient : 0);

  @override
  bool operator ==(Object other) =>
      other is WindowPresentationConfiguration &&
      other.level == level &&
      other.canJoinAllSpaces == canJoinAllSpaces &&
      other.fullScreenAuxiliary == fullScreenAuxiliary &&
      other.stationary == stationary &&
      other.transient == transient;

  @override
  int get hashCode => Object.hash(
    level,
    canJoinAllSpaces,
    fullScreenAuxiliary,
    stationary,
    transient,
  );
}

extension AppKitApplicationScreenResolution on AppKitApplication {
  /// Resolves a current display without retaining stale `NSScreen` state.
  AppKitResolvedScreen resolveScreen(AppKitScreenSelection selection) {
    _ensureRunning();
    final NativeBindings nativeBindings = _bindings;
    if (nativeBindings is! NativeWindowPresentationBindings) {
      throw UnsupportedError(
        'the native bridge does not expose current screen resolution',
      );
    }
    final int nativeSelection = switch (selection) {
      AppKitScreenSelection.main => dartAppKitScreenSelectionMain,
      AppKitScreenSelection.mouse => dartAppKitScreenSelectionMouse,
      AppKitScreenSelection.menuBar => dartAppKitScreenSelectionMenuBar,
    };
    final NativeScreenSnapshot snapshot = _checkValue<NativeScreenSnapshot>(
      (nativeBindings as NativeWindowPresentationBindings)
          .applicationResolveScreen(nativeSelection),
      'AppKitApplication.resolveScreen',
    );
    bool validRect(NativeRect value) =>
        value.x.isFinite &&
        value.y.isFinite &&
        value.width.isFinite &&
        value.height.isFinite &&
        value.width > 0 &&
        value.height > 0;
    if (snapshot.displayId <= 0 ||
        !validRect(snapshot.frame) ||
        !validRect(snapshot.visibleFrame) ||
        !snapshot.backingScaleFactor.isFinite ||
        snapshot.backingScaleFactor <= 0) {
      throw StateError('native screen snapshot violates its public contract');
    }
    Rect rect(NativeRect value) =>
        Rect.fromLTWH(value.x, value.y, value.width, value.height);
    return AppKitResolvedScreen(
      screen: AppKitScreen(
        displayId: snapshot.displayId,
        frame: rect(snapshot.frame),
        visibleFrame: rect(snapshot.visibleFrame),
      ),
      backingScaleFactor: snapshot.backingScaleFactor,
    );
  }
}

/// Immutable presentation for one simple native window-tab accessory.
final class WindowTabAccessory {
  factory WindowTabAccessory({
    required WindowTabColor color,
    double width = 8,
    double height = 8,
    WindowTabAccessoryShape shape = WindowTabAccessoryShape.ellipse,
  }) {
    for (final MapEntry<String, double> dimension in <String, double>{
      'width': width,
      'height': height,
    }.entries) {
      if (!dimension.value.isFinite ||
          dimension.value <= 0 ||
          dimension.value > dartAppKitWindowTabAccessoryMaximumExtent) {
        throw RangeError.value(
          dimension.value,
          dimension.key,
          'must be finite and in (0, '
          '$dartAppKitWindowTabAccessoryMaximumExtent]',
        );
      }
    }
    return WindowTabAccessory._(
      color: color,
      width: width,
      height: height,
      shape: shape,
    );
  }

  const WindowTabAccessory._({
    required this.color,
    required this.width,
    required this.height,
    required this.shape,
  });

  final WindowTabColor color;
  final double width;
  final double height;
  final WindowTabAccessoryShape shape;

  @override
  bool operator ==(Object other) =>
      other is WindowTabAccessory &&
      other.color == color &&
      other.width == width &&
      other.height == height &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(color, width, height, shape);
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
  WindowTabAccessory? _tabAccessory;
  double? _backingScaleFactor;
  AppKitScreen? _screen;
  bool _fullscreen = false;
  bool? _requestedFullscreen;
  WindowPresentationConfiguration _presentationConfiguration =
      const WindowPresentationConfiguration();

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

  /// Current drawable content layout inside the native window frame.
  Rect get contentLayoutRect {
    ensureAlive();
    final NativeRect native = _checkValue<NativeRect>(
      _bindings.windowGetContentLayoutRect(_handle),
      'Window.contentLayoutRect',
    );
    return Rect.fromLTWH(native.x, native.y, native.width, native.height);
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

  /// Optional simple accessory shown by the native tab.
  WindowTabAccessory? get tabAccessory {
    ensureAlive();
    return _tabAccessory;
  }

  set tabAccessory(WindowTabAccessory? value) {
    ensureAlive();
    if (_tabAccessory == value) return;
    final WindowTabColor? color = value?.color;
    final int shape = switch (value?.shape) {
      null || WindowTabAccessoryShape.rectangle =>
        dartAppKitWindowTabAccessoryShapeRectangle,
      WindowTabAccessoryShape.ellipse =>
        dartAppKitWindowTabAccessoryShapeEllipse,
    };
    _checkCall(
      _bindings.windowSetTabAccessory(
        handle: _handle,
        hasAccessory: value != null,
        shape: shape,
        width: value?.width ?? 0,
        height: value?.height ?? 0,
        red: color?.red ?? 0,
        green: color?.green ?? 0,
        blue: color?.blue ?? 0,
        alpha: color?.alpha ?? 0,
      ),
      'Window.tabAccessory',
    );
    _tabAccessory = value;
  }

  /// Compatibility helper for an 8×8 elliptical [tabAccessory].
  WindowTabColor? get tabColor {
    ensureAlive();
    return _tabAccessory?.color;
  }

  set tabColor(WindowTabColor? value) {
    tabAccessory = value == null ? null : WindowTabAccessory(color: value);
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

  WindowPresentationConfiguration get presentationConfiguration {
    ensureAlive();
    return _presentationConfiguration;
  }

  set presentationConfiguration(WindowPresentationConfiguration value) {
    ensureAlive();
    if (_presentationConfiguration == value) return;
    final NativeWindowPresentationBindings bindings =
        _requirePresentationBindings();
    _checkCall(
      bindings.windowSetPresentationConfiguration(
        handle: _handle,
        level: value._nativeLevel,
        collectionBehaviorMask: value._nativeCollectionBehaviorMask,
      ),
      'Window.presentationConfiguration',
    );
    _presentationConfiguration = value;
  }

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

  /// Shows and optionally focuses this window with a bounded frame animation.
  void present({
    required Rect startFrame,
    required Rect targetFrame,
    Duration duration = Duration.zero,
    bool makeKey = true,
  }) {
    ensureAlive();
    _validateFrame(startFrame);
    _validateFrame(targetFrame);
    final double seconds = _validatePresentationDuration(duration);
    _checkCall(
      _requirePresentationBindings().windowPresent(
        handle: _handle,
        startFrame: _nativeRect(startFrame),
        targetFrame: _nativeRect(targetFrame),
        durationSeconds: seconds,
        makeKey: makeKey,
      ),
      'Window.present',
    );
    _frame = targetFrame;
  }

  /// Orders this window out without closing or releasing its content.
  void hide({required Rect targetFrame, Duration duration = Duration.zero}) {
    ensureAlive();
    _validateFrame(targetFrame);
    final double seconds = _validatePresentationDuration(duration);
    _checkCall(
      _requirePresentationBindings().windowHide(
        handle: _handle,
        targetFrame: _nativeRect(targetFrame),
        durationSeconds: seconds,
      ),
      'Window.hide',
    );
    _frame = targetFrame;
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
    _tabAccessory = null;
    _fullscreen = false;
    _requestedFullscreen = null;
    _presentationConfiguration = const WindowPresentationConfiguration();
    unawaited(_eventController.close());
  }

  NativeWindowPresentationBindings _requirePresentationBindings() {
    final NativeBindings nativeBindings = _bindings;
    if (nativeBindings is! NativeWindowPresentationBindings) {
      throw UnsupportedError(
        'the native bridge does not expose animated window presentation',
      );
    }
    return nativeBindings as NativeWindowPresentationBindings;
  }

  static NativeRect _nativeRect(Rect value) => NativeRect(
    x: value.left,
    y: value.top,
    width: value.width,
    height: value.height,
  );

  static double _validatePresentationDuration(Duration value) {
    const Duration maximum = Duration(seconds: 5);
    if (value.isNegative || value.inMicroseconds > maximum.inMicroseconds) {
      throw RangeError.range(
        value.inMicroseconds,
        0,
        maximum.inMicroseconds,
        'duration.inMicroseconds',
      );
    }
    return value.inMicroseconds / Duration.microsecondsPerSecond;
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
