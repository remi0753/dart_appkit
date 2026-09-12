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

/// Immutable copied payload for one application local notification.
final class AppKitUserNotification {
  AppKitUserNotification({
    required this.identifier,
    required this.title,
    required this.body,
  }) {
    if (!isValidIdentifier(identifier)) {
      throw ArgumentError.value(
        identifier,
        'identifier',
        'must be 1–$maximumIdentifierUtf8Bytes ASCII bytes using '
            'letters, digits, dot, plus, underscore, or hyphen',
      );
    }
    if (!_isSafeDisplayText(title, maximumTextUtf8Bytes) ||
        !_isSafeDisplayText(body, maximumTextUtf8Bytes) ||
        title.isEmpty && body.isEmpty) {
      throw ArgumentError(
        'title and body must be bounded safe display text and not both empty',
      );
    }
  }

  static const int maximumIdentifierUtf8Bytes =
      dartAppKitUserNotificationIdentifierMaximumUtf8Bytes;
  static const int maximumTextUtf8Bytes =
      dartAppKitUserNotificationTextMaximumUtf8Bytes;

  final String identifier;
  final String title;
  final String body;

  static bool isValidIdentifier(String value) {
    final List<int> bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > maximumIdentifierUtf8Bytes) {
      return false;
    }
    for (final int byte in bytes) {
      final bool valid =
          byte >= 0x30 && byte <= 0x39 ||
          byte >= 0x41 && byte <= 0x5a ||
          byte >= 0x61 && byte <= 0x7a ||
          byte == 0x2d ||
          byte == 0x2e ||
          byte == 0x2b ||
          byte == 0x5f;
      if (!valid) return false;
    }
    return true;
  }
}

bool _isSafeDisplayText(String value, int maximumUtf8Bytes) {
  if (utf8.encode(value).length > maximumUtf8Bytes) return false;
  for (final int scalar in value.runes) {
    final bool unsafe =
        scalar <= 0x1f ||
        scalar >= 0x7f && scalar <= 0x9f ||
        scalar == 0xa0 ||
        scalar == 0xad ||
        scalar == 0x61c ||
        scalar == 0x1680 ||
        scalar == 0x180e ||
        scalar >= 0x2000 && scalar <= 0x200f ||
        scalar >= 0x2028 && scalar <= 0x202f ||
        scalar >= 0x205f && scalar <= 0x206f ||
        scalar == 0x3000 ||
        scalar == 0xfeff;
    if (unsafe) return false;
  }
  return true;
}

/// Immutable bounds for the application's Finder folder Services provider.
final class FolderServicesProviderConfiguration {
  const FolderServicesProviderConfiguration({
    this.maximumFileUrlCount = maximumFileUrlCountLimit,
    this.maximumFileUrlUtf8Bytes = maximumFileUrlUtf8BytesLimit,
    this.maximumTotalFileUrlUtf8Bytes = maximumTotalFileUrlUtf8BytesLimit,
  });

  static const int maximumFileUrlCountLimit =
      dartAppKitFolderServiceMaximumFileUrlCount;
  static const int maximumFileUrlUtf8BytesLimit =
      dartAppKitFolderServiceMaximumFileUrlUtf8Bytes;
  static const int maximumTotalFileUrlUtf8BytesLimit =
      dartAppKitFolderServiceMaximumTotalFileUrlUtf8Bytes;

  final int maximumFileUrlCount;
  final int maximumFileUrlUtf8Bytes;
  final int maximumTotalFileUrlUtf8Bytes;

  NativeFolderServicesProviderConfiguration get _native {
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
    return NativeFolderServicesProviderConfiguration(
      maximumFileUrlCount: maximumFileUrlCount,
      maximumFileUrlUtf8Bytes: maximumFileUrlUtf8Bytes,
      maximumTotalFileUrlUtf8Bytes: maximumTotalFileUrlUtf8Bytes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FolderServicesProviderConfiguration &&
      other.maximumFileUrlCount == maximumFileUrlCount &&
      other.maximumFileUrlUtf8Bytes == maximumFileUrlUtf8Bytes &&
      other.maximumTotalFileUrlUtf8Bytes == maximumTotalFileUrlUtf8Bytes;

  @override
  int get hashCode => Object.hash(
    maximumFileUrlCount,
    maximumFileUrlUtf8Bytes,
    maximumTotalFileUrlUtf8Bytes,
  );
}

final class AppKitApplication {
  AppKitApplication._(
    this._bindings,
    this._eventSource,
    this.eventProtocolVersion,
    this.externalUrlPolicy,
  ) : _events = StreamController<AppKitEvent>.broadcast(sync: true);

  static AppKitApplication? _current;

  final NativeBindings _bindings;
  final _EventSource _eventSource;
  final StreamController<AppKitEvent> _events;
  final int eventProtocolVersion;
  final ExternalUrlPolicy externalUrlPolicy;
  final Map<int, WeakReference<Window>> _windows =
      <int, WeakReference<Window>>{};
  final Map<int, WeakReference<MenuItem>> _menuItems =
      <int, WeakReference<MenuItem>>{};
  final Map<int, WeakReference<GlobalHotKey>> _globalHotKeys =
      <int, WeakReference<GlobalHotKey>>{};
  final Map<int, WeakReference<View>> _views = <int, WeakReference<View>>{};

  late final StreamSubscription<Object?> _eventSubscription;
  bool _terminated = false;
  bool _active = false;
  AppKitAppearance? _effectiveAppearance;
  bool _defersTerminationRequests = false;
  Pasteboard? _generalPasteboard;
  Menu? _mainMenu;
  String? _dockBadgeLabel;
  FolderServicesProviderConfiguration? _folderServicesProvider;

  static Future<AppKitApplication> attach({
    ExternalUrlPolicy? externalUrlPolicy,
  }) async {
    final AppKitApplication? existing = _current;
    if (existing != null && !existing._terminated) {
      if (externalUrlPolicy != null &&
          !identical(existing.externalUrlPolicy, externalUrlPolicy)) {
        throw StateError(
          'the attached application already has another external URL policy',
        );
      }
      return existing;
    }

    final _ReceivePortEventSource source = _ReceivePortEventSource();
    try {
      final NativeBindings bindings = FfiNativeBindings.process();
      return _attach(
        bindings,
        source,
        externalUrlPolicy ?? ExternalUrlPolicy.defaultPolicy,
      );
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
    ExternalUrlPolicy externalUrlPolicy,
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
      externalUrlPolicy,
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
  Stream<ApplicationActiveChangedEvent> get onActiveChanged => events
      .where((AppKitEvent event) => event is ApplicationActiveChangedEvent)
      .map((AppKitEvent event) => event as ApplicationActiveChangedEvent);
  Stream<ApplicationReopenRequestedEvent> get onReopenRequested => events
      .where((AppKitEvent event) => event is ApplicationReopenRequestedEvent)
      .map((AppKitEvent event) => event as ApplicationReopenRequestedEvent);
  Stream<ApplicationTerminateRequestedEvent> get onTerminateRequested => events
      .where((AppKitEvent event) => event is ApplicationTerminateRequestedEvent)
      .map((AppKitEvent event) => event as ApplicationTerminateRequestedEvent);
  Stream<ApplicationAppearanceChangedEvent> get onAppearanceChanged => events
      .where((AppKitEvent event) => event is ApplicationAppearanceChangedEvent)
      .map((AppKitEvent event) => event as ApplicationAppearanceChangedEvent);
  Stream<ApplicationFolderServiceRequestedEvent> get onFolderServiceRequested =>
      events
          .where(
            (AppKitEvent event) =>
                event is ApplicationFolderServiceRequestedEvent,
          )
          .map(
            (AppKitEvent event) =>
                event as ApplicationFolderServiceRequestedEvent,
          );
  bool get isTerminated => _terminated;
  bool get isActive => _active;
  AppKitAppearance? get effectiveAppearance => _effectiveAppearance;

  FolderServicesProviderConfiguration? get folderServicesProvider {
    _ensureRunning();
    return _folderServicesProvider;
  }

  set folderServicesProvider(FolderServicesProviderConfiguration? value) {
    _ensureRunning();
    if (value == _folderServicesProvider) {
      return;
    }
    if (value != null && eventProtocolVersion < 12) {
      throw UnsupportedError(
        'folder Services providers require native event protocol 12',
      );
    }
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeFolderServicesProviderBindings) {
      throw const AppKitNativeException(
        operation: 'AppKitApplication.folderServicesProvider',
        status: 8,
        nativeMessage:
            'native bridge does not support folder Services providers',
      );
    }
    _checkCall(
      (bindings as NativeFolderServicesProviderBindings)
          .applicationSetFolderServicesProvider(value?._native),
      'AppKitApplication.folderServicesProvider',
    );
    _folderServicesProvider = value;
  }

  Pasteboard get generalPasteboard {
    _ensureRunning();
    return _generalPasteboard ??= Pasteboard._(this);
  }

  Menu? get mainMenu {
    _ensureRunning();
    return _mainMenu;
  }

  set mainMenu(Menu? value) {
    _ensureRunning();
    value?.ensureAlive();
    if (value != null && !identical(value._application, this)) {
      throw StateError('main menu belongs to a different AppKit application');
    }
    if (identical(value, _mainMenu)) {
      return;
    }
    _checkCall(
      _bindings.applicationSetMainMenu(value?._handle ?? 0),
      'AppKitApplication.mainMenu',
    );
    _mainMenu = value;
  }

  bool get defersTerminationRequests => _defersTerminationRequests;

  set defersTerminationRequests(bool value) {
    _ensureRunning();
    if (value && eventProtocolVersion < 4) {
      throw UnsupportedError(
        'termination request deferral requires native event protocol 4',
      );
    }
    if (value == _defersTerminationRequests) {
      return;
    }
    _checkCall(
      _bindings.applicationSetTerminationRequestDeferral(value),
      'AppKitApplication.defersTerminationRequests',
    );
    _defersTerminationRequests = value;
  }

  void replyToTerminationRequest(
    ApplicationTerminateRequestedEvent request, {
    required bool allow,
  }) {
    _ensureRunning();
    _checkCall(
      _bindings.applicationReplyToTerminationRequest(
        operationId: request.operationId,
        allow: allow,
      ),
      'AppKitApplication.replyToTerminationRequest',
    );
  }

  /// Opens one prevalidated external URL with its registered macOS handler.
  ///
  /// Returns whether Launch Services accepted the request. The URL is checked
  /// again against this application's immutable [externalUrlPolicy], and the
  /// native bridge repeats structural and selected-scheme validation.
  bool openExternalUrl(AllowedExternalUrl url) {
    _ensureRunning();
    final AllowedExternalUrl? validated = AllowedExternalUrl.tryParse(
      url.value,
      policy: externalUrlPolicy,
    );
    if (validated == null) {
      throw ArgumentError.value(
        url,
        'url',
        'is not allowed by this application external URL policy',
      );
    }
    final ExternalUrlSchemePolicy schemePolicy = externalUrlPolicy
        .policyForScheme(validated.scheme)!;
    final int opened = _checkValue<int>(
      _bindings.applicationOpenExternalUrl(
        validated.value,
        scheme: schemePolicy.scheme,
        policyFlags: schemePolicy._nativeFlags,
      ),
      'AppKitApplication.openExternalUrl',
    );
    if (opened != 0 && opened != 1) {
      throw const AppKitNativeException(
        operation: 'AppKitApplication.openExternalUrl',
        status: 7,
        nativeMessage: 'native bridge returned an invalid external URL result',
      );
    }
    return opened == 1;
  }

  /// Submits one bounded alert-only notification for asynchronous delivery.
  void postUserNotification(AppKitUserNotification notification) {
    _ensureRunning();
    _checkCall(
      _bindings.applicationPostUserNotification(
        identifier: notification.identifier,
        title: notification.title,
        body: notification.body,
      ),
      'AppKitApplication.postUserNotification',
    );
  }

  /// Removes pending and delivered native state for one application identity.
  void removeUserNotification(String identifier) {
    _ensureRunning();
    if (!AppKitUserNotification.isValidIdentifier(identifier)) {
      throw ArgumentError.value(identifier, 'identifier');
    }
    _checkCall(
      _bindings.applicationRemoveUserNotification(identifier),
      'AppKitApplication.removeUserNotification',
    );
  }

  String? get dockBadgeLabel => _dockBadgeLabel;

  /// Sets a short application Dock badge, or clears it with null/empty text.
  set dockBadgeLabel(String? value) {
    _ensureRunning();
    final String? normalized = value == null || value.isEmpty ? null : value;
    if (normalized != null &&
        !_isSafeDisplayText(
          normalized,
          dartAppKitDockBadgeLabelMaximumUtf8Bytes,
        )) {
      throw ArgumentError.value(value, 'dockBadgeLabel');
    }
    if (normalized == _dockBadgeLabel) return;
    _checkCall(
      _bindings.applicationSetDockBadgeLabel(normalized),
      'AppKitApplication.dockBadgeLabel',
    );
    _dockBadgeLabel = normalized;
  }

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

  void _registerView(View view) {
    _ensureRunning();
    if (_views.containsKey(view._handle)) {
      throw StateError('native view handle ${view._handle} is duplicated');
    }
    _views[view._handle] = WeakReference<View>(view);
  }

  void _unregisterView(View view) {
    final WeakReference<View>? reference = _views[view._handle];
    if (identical(reference?.target, view) || reference?.target == null) {
      _views.remove(view._handle);
    }
  }

  void _unregisterWindow(Window window) {
    final WeakReference<Window>? reference = _windows[window._handle];
    if (identical(reference?.target, window) || reference?.target == null) {
      _windows.remove(window._handle);
    }
  }

  void _registerMenuItem(MenuItem item) {
    _ensureRunning();
    if (_menuItems.containsKey(item._handle)) {
      throw StateError('native menu item handle ${item._handle} is duplicated');
    }
    _menuItems[item._handle] = WeakReference<MenuItem>(item);
  }

  void _unregisterMenuItem(MenuItem item) {
    final WeakReference<MenuItem>? reference = _menuItems[item._handle];
    if (identical(reference?.target, item) || reference?.target == null) {
      _menuItems.remove(item._handle);
    }
  }

  void _registerGlobalHotKey(GlobalHotKey hotKey) {
    _ensureRunning();
    if (_globalHotKeys.containsKey(hotKey._handle)) {
      throw StateError(
        'native global hot key handle ${hotKey._handle} is duplicated',
      );
    }
    _globalHotKeys[hotKey._handle] = WeakReference<GlobalHotKey>(hotKey);
  }

  void _unregisterGlobalHotKey(GlobalHotKey hotKey) {
    final WeakReference<GlobalHotKey>? reference =
        _globalHotKeys[hotKey._handle];
    if (identical(reference?.target, hotKey) || reference?.target == null) {
      _globalHotKeys.remove(hotKey._handle);
    }
  }

  void _menuDisposed(Menu menu) {
    if (identical(_mainMenu, menu)) {
      _mainMenu = null;
    }
  }

  void _handleRawEvent(Object? message) {
    if (_terminated) {
      return;
    }
    try {
      final AppKitEvent event = _EventCodec.decode(message);
      if (event case ApplicationActiveChangedEvent(:final isActive)) {
        _active = isActive;
      }
      if (event case ApplicationAppearanceChangedEvent(:final appearance)) {
        _effectiveAppearance = appearance;
      }
      Window? window;
      if (event is WindowEvent) {
        final WeakReference<Window>? reference = _windows[event.windowHandle];
        window = reference?.target;
        if (window == null) {
          _windows.remove(event.windowHandle);
        } else {
          window._updateState(event);
        }
      }
      MenuItem? menuItem;
      if (event is MenuItemInvokedEvent) {
        final WeakReference<MenuItem>? reference =
            _menuItems[event.menuItemHandle];
        menuItem = reference?.target;
        if (menuItem == null) {
          _menuItems.remove(event.menuItemHandle);
        }
      }
      GlobalHotKey? globalHotKey;
      if (event is GlobalHotKeyPressedEvent) {
        final WeakReference<GlobalHotKey>? reference =
            _globalHotKeys[event.globalHotKeyHandle];
        globalHotKey = reference?.target;
        if (globalHotKey == null) {
          _globalHotKeys.remove(event.globalHotKeyHandle);
        }
      }
      View? view;
      if (event is ViewQuickLookRequestedEvent ||
          event is ViewServicesTextReceivedEvent ||
          event is ViewDropPerformedEvent) {
        final WeakReference<View>? reference = _views[event.sourceHandle];
        view = reference?.target;
        if (view == null) {
          _views.remove(event.sourceHandle);
        }
      }
      _events.add(event);
      if (window != null) {
        window._dispatch(event);
      }
      if (menuItem != null && event is MenuItemInvokedEvent) {
        menuItem._dispatch(event);
      }
      if (globalHotKey != null && event is GlobalHotKeyPressedEvent) {
        globalHotKey._dispatch(event);
      }
      if (view != null && event is ViewQuickLookRequestedEvent) {
        view._dispatchQuickLook(event);
      }
      if (view != null && event is ViewServicesTextReceivedEvent) {
        view._dispatchServicesText(event);
      }
      if (view != null && event is ViewDropPerformedEvent) {
        view._dispatchDrop(event);
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
    _menuItems.clear();
    _globalHotKeys.clear();
    _views.clear();
    _active = false;
    _effectiveAppearance = null;
    _defersTerminationRequests = false;
    _generalPasteboard = null;
    _mainMenu = null;
    _dockBadgeLabel = null;
    _folderServicesProvider = null;
  }
}

Future<AppKitApplication> attachApplicationForTesting({
  required NativeBindings bindings,
  required Stream<Object?> events,
  int eventPort = 4242,
  void Function()? onClose,
  ExternalUrlPolicy? externalUrlPolicy,
}) async {
  final _ProvidedEventSource source = _ProvidedEventSource(
    events,
    eventPort,
    onClose,
  );
  return AppKitApplication._attach(
    bindings,
    source,
    externalUrlPolicy ?? ExternalUrlPolicy.defaultPolicy,
  );
}

/// Delivers one value through the same decoder and routing path as the native
/// event port.
///
/// This hook is exported only from `package:dart_appkit/testing.dart`.
void injectRawAppKitEventForTesting(
  AppKitApplication application,
  Object? message,
) {
  if (!identical(AppKitApplication._current, application) ||
      application._terminated) {
    throw StateError('the supplied AppKit application is not attached');
  }
  application._handleRawEvent(message);
}

/// Returns the generation-checked native handle used to build routing
/// fixtures, including a late event after the Dart owner is disposed.
///
/// This hook is exported only from `package:dart_appkit/testing.dart`.
int nativeWindowHandleForTesting(Window window) => window._handle;

/// Returns the generation-checked global-hot-key handle for routing fixtures.
/// Exported only from `package:dart_appkit/testing.dart`.
int nativeGlobalHotKeyHandleForTesting(GlobalHotKey hotKey) => hotKey._handle;

/// Returns the generation-checked View handle for request-routing fixtures.
/// Exported only from `package:dart_appkit/testing.dart`.
int nativeViewHandleForTesting(View view) => view._handle;

/// Enters the real native deferred-termination state machine without asking
/// the host process to exit. Exported only from `package:dart_appkit/testing.dart`.
void requestApplicationTerminationForTesting(AppKitApplication application) {
  if (!identical(AppKitApplication._current, application) ||
      application._terminated) {
    throw StateError('the supplied AppKit application is not attached');
  }
  _checkCall(
    application._bindings.debugRequestApplicationTermination(),
    'requestApplicationTerminationForTesting',
  );
}
