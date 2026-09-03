part of '../api.dart';

abstract interface class _EventSource {
  int get port;
  Stream<Object?> get events;
  void close();
}

final class _ReceivePortEventSource implements _EventSource {
  _ReceivePortEventSource() : _receivePort = ReceivePort();

  final ReceivePort _receivePort;

  @override
  int get port => _receivePort.sendPort.nativePort;

  @override
  Stream<Object?> get events => _receivePort;

  @override
  void close() => _receivePort.close();
}

final class _ProvidedEventSource implements _EventSource {
  _ProvidedEventSource(this.events, this.port, this._onClose);

  @override
  final Stream<Object?> events;

  @override
  final int port;

  final void Function()? _onClose;

  @override
  void close() => _onClose?.call();
}

final class AppKitApplication {
  AppKitApplication._(
    this._bindings,
    this._eventSource,
    this.eventProtocolVersion,
  ) : _events = StreamController<AppKitEvent>.broadcast(sync: true);

  static AppKitApplication? _current;

  final NativeBindings _bindings;
  final _EventSource _eventSource;
  final StreamController<AppKitEvent> _events;
  final int eventProtocolVersion;
  final Map<int, WeakReference<Window>> _windows =
      <int, WeakReference<Window>>{};

  late final StreamSubscription<Object?> _eventSubscription;
  bool _terminated = false;

  static Future<AppKitApplication> attach() async {
    final AppKitApplication? existing = _current;
    if (existing != null && !existing._terminated) {
      return existing;
    }

    final _ReceivePortEventSource source = _ReceivePortEventSource();
    try {
      final NativeBindings bindings = FfiNativeBindings.process();
      return _attach(bindings, source);
    } on Object catch (error) {
      source.close();
      if (error is AppKitInitializationException ||
          error is AppKitNativeException) {
        rethrow;
      }
      throw AppKitInitializationException(
        'could not resolve or initialize native bridge symbols: $error',
      );
    }
  }

  static AppKitApplication _attach(
    NativeBindings bindings,
    _EventSource source,
  ) {
    if (_current != null && !_current!._terminated) {
      throw const AppKitInitializationException(
        'an AppKit application is already attached in this isolate',
      );
    }

    final int actualAbi = bindings.abiVersion();
    if (actualAbi != dartAppKitAbiVersion) {
      throw AppKitInitializationException(
        'native ABI version $actualAbi does not match Dart ABI '
        '$dartAppKitAbiVersion',
      );
    }

    final int isMain = _checkValue<int>(
      bindings.debugIsMainThread(),
      'AppKitApplication.attach.mainThreadCheck',
    );
    if (isMain != 1) {
      throw const AppKitInitializationException(
        'the root UI isolate is not executing on the macOS main thread',
      );
    }
    final int eventProtocolVersion = _checkValue<int>(
      bindings.applicationSetEventPortVersioned(
        port: source.port,
        minimumVersion: dartAppKitMinimumEventProtocolVersion,
        maximumVersion: dartAppKitCurrentEventProtocolVersion,
      ),
      'AppKitApplication.attach.eventPort',
    );

    final AppKitApplication application = AppKitApplication._(
      bindings,
      source,
      eventProtocolVersion,
    );
    application._eventSubscription = source.events.listen(
      application._handleRawEvent,
      onError: application._events.addError,
    );
    _current = application;
    return application;
  }

  static AppKitApplication _requireCurrent() {
    final AppKitApplication? application = _current;
    if (application == null || application._terminated) {
      throw StateError('call AppKitApplication.attach() before creating UI');
    }
    return application;
  }

  Stream<AppKitEvent> get events => _events.stream;
  bool get isTerminated => _terminated;

  int get debugLiveObjectCount {
    _ensureRunning();
    return _checkValue<int>(
      _bindings.debugLiveObjectCount(),
      'AppKitApplication.debugLiveObjectCount',
    );
  }

  void _ensureRunning() {
    if (_terminated) {
      throw StateError('AppKitApplication has already terminated');
    }
  }

  void _registerWindow(Window window) {
    _ensureRunning();
    if (_windows.containsKey(window._handle)) {
      throw StateError('native window handle ${window._handle} is duplicated');
    }
    _windows[window._handle] = WeakReference<Window>(window);
  }

  void _unregisterWindow(Window window) {
    final WeakReference<Window>? reference = _windows[window._handle];
    if (identical(reference?.target, window) || reference?.target == null) {
      _windows.remove(window._handle);
    }
  }

  void _handleRawEvent(Object? message) {
    if (_terminated) {
      return;
    }
    try {
      final AppKitEvent event = _EventCodec.decode(message);
      final WeakReference<Window>? reference = _windows[event.windowHandle];
      final Window? window = reference?.target;
      if (window == null) {
        _windows.remove(event.windowHandle);
      } else {
        window._updateState(event);
      }
      _events.add(event);
      if (window != null) {
        window._dispatch(event);
      }
    } on Object catch (error, stackTrace) {
      _events.addError(error, stackTrace);
    }
  }

  Future<void> terminate() async {
    if (_terminated) {
      return;
    }
    _checkCall(_bindings.applicationTerminate(), 'AppKitApplication.terminate');
    _terminated = true;
    if (identical(_current, this)) {
      _current = null;
    }
    await _eventSubscription.cancel();
    _eventSource.close();
    await _events.close();
    _windows.clear();
  }
}

Future<AppKitApplication> attachApplicationForTesting({
  required NativeBindings bindings,
  required Stream<Object?> events,
  int eventPort = 4242,
  void Function()? onClose,
}) async {
  final _ProvidedEventSource source = _ProvidedEventSource(
    events,
    eventPort,
    onClose,
  );
  return AppKitApplication._attach(bindings, source);
}
