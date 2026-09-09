part of '../api.dart';

/// Immutable AppKit validation behavior selected when a [Menu] is created.
final class MenuConfiguration {
  const MenuConfiguration({this.autoEnablesItems = false});

  /// Whether AppKit automatically validates enabled state through its target.
  ///
  /// The compatibility default is `false`, leaving [MenuItem.isEnabled]
  /// authoritative.
  final bool autoEnablesItems;

  @override
  bool operator ==(Object other) =>
      other is MenuConfiguration && other.autoEnablesItems == autoEnablesItems;

  @override
  int get hashCode => autoEnablesItems.hashCode;
}

final class Menu extends _NativeResource {
  factory Menu({
    String title = '',
    MenuConfiguration configuration = const MenuConfiguration(),
  }) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    if (application.eventProtocolVersion < 4) {
      throw UnsupportedError('menus require native event protocol 4');
    }
    final int handle = _checkValue<int>(
      application._bindings.menuCreate(
        title,
        autoEnablesItems: configuration.autoEnablesItems,
      ),
      'Menu.create',
    );
    return Menu._(application, handle, title, configuration);
  }

  Menu._(this._application, int handle, this.title, this.configuration)
    : super(_application._bindings, handle);

  final AppKitApplication _application;
  final String title;
  final MenuConfiguration configuration;
  final List<MenuItem> _items = <MenuItem>[];

  List<MenuItem> get items {
    ensureAlive();
    return List<MenuItem>.unmodifiable(_items);
  }

  void addItem(MenuItem item) {
    ensureAlive();
    item.ensureAlive();
    if (!identical(item._application, _application)) {
      throw StateError('menu item belongs to a different AppKit application');
    }
    _checkCall(_bindings.menuAddItem(_handle, item._handle), 'Menu.addItem');
    _items.add(item);
  }

  @override
  void dispose() {
    if (isDisposed) {
      return;
    }
    super.dispose();
    _application._menuDisposed(this);
    _items.clear();
  }
}

final class MenuItem extends _NativeResource {
  factory MenuItem({
    required String title,
    String keyEquivalent = '',
    ModifierKeys modifiers = const ModifierKeys(0),
  }) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    if (application.eventProtocolVersion < 4) {
      throw UnsupportedError('menu items require native event protocol 4');
    }
    if (modifiers.bits < 0 ||
        (modifiers.bits & ~ModifierKeys.supportedBits) != 0) {
      throw ArgumentError.value(
        modifiers.bits,
        'modifiers',
        'contains unsupported modifier bits',
      );
    }
    final int handle = _checkValue<int>(
      application._bindings.menuItemCreate(
        title: title,
        keyEquivalent: keyEquivalent,
        modifiers: modifiers.bits,
      ),
      'MenuItem.create',
    );
    final MenuItem item = MenuItem._(
      application,
      handle,
      title,
      keyEquivalent,
      modifiers,
      false,
    );
    application._registerMenuItem(item);
    return item;
  }

  factory MenuItem.separator() {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    if (application.eventProtocolVersion < 4) {
      throw UnsupportedError('menu items require native event protocol 4');
    }
    final int handle = _checkValue<int>(
      application._bindings.menuItemCreateSeparator(),
      'MenuItem.separator',
    );
    final MenuItem item = MenuItem._(
      application,
      handle,
      '',
      '',
      const ModifierKeys(0),
      true,
    );
    application._registerMenuItem(item);
    return item;
  }

  MenuItem._(
    this._application,
    int handle,
    this.title,
    this.keyEquivalent,
    this.modifiers,
    this.isSeparator,
  ) : _eventController = StreamController<MenuItemInvokedEvent>.broadcast(
        sync: true,
      ),
      super(_application._bindings, handle);

  final AppKitApplication _application;
  final StreamController<MenuItemInvokedEvent> _eventController;
  final String title;
  final String keyEquivalent;
  final ModifierKeys modifiers;
  final bool isSeparator;

  Menu? _submenu;
  bool _enabled = true;

  Stream<MenuItemInvokedEvent> get onInvoked => _eventController.stream;

  Menu? get submenu {
    ensureAlive();
    return _submenu;
  }

  set submenu(Menu? value) {
    ensureAlive();
    if (isSeparator) {
      throw StateError('a separator cannot own a submenu');
    }
    value?.ensureAlive();
    if (value != null && !identical(value._application, _application)) {
      throw StateError('submenu belongs to a different AppKit application');
    }
    _checkCall(
      _bindings.menuItemSetSubmenu(_handle, value?._handle ?? 0),
      'MenuItem.submenu',
    );
    _submenu = value;
  }

  bool get isEnabled {
    ensureAlive();
    return _enabled;
  }

  set isEnabled(bool value) {
    ensureAlive();
    if (isSeparator) {
      throw StateError('a separator has no enabled state');
    }
    if (value == _enabled) {
      return;
    }
    _checkCall(
      _bindings.menuItemSetEnabled(_handle, value),
      'MenuItem.isEnabled',
    );
    _enabled = value;
  }

  void performAction() {
    ensureAlive();
    if (isSeparator) {
      throw StateError('a separator has no action');
    }
    if (!_enabled) {
      throw StateError('a disabled menu item cannot perform its action');
    }
    _checkCall(
      _bindings.menuItemPerformAction(_handle),
      'MenuItem.performAction',
    );
  }

  void _dispatch(MenuItemInvokedEvent event) {
    if (!isDisposed) {
      _eventController.add(event);
    }
  }

  @override
  void dispose() {
    if (isDisposed) {
      return;
    }
    super.dispose();
    _application._unregisterMenuItem(this);
    _submenu = null;
    unawaited(_eventController.close());
  }
}
