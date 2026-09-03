part of '../api.dart';

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

  Stream<WindowEvent> get events => _eventController.stream;

  Stream<WindowClosedEvent> get onClosed => events
      .where((WindowEvent event) => event is WindowClosedEvent)
      .map((WindowEvent event) => event as WindowClosedEvent);

  Stream<WindowResizedEvent> get onResized => events
      .where((WindowEvent event) => event is WindowResizedEvent)
      .map((WindowEvent event) => event as WindowResizedEvent);

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

  void _dispatch(AppKitEvent event) {
    if (isDisposed || event is! WindowEvent) {
      return;
    }
    if (event is WindowClosedEvent) {
      _closed = true;
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
    unawaited(_eventController.close());
  }
}
