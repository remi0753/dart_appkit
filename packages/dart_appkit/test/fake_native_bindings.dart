import 'dart:ffi';

import 'package:dart_appkit/src/native/native_bindings.dart';

enum FakeObjectKind { window, view, textView, menu, menuItem }

final class FakeMenuItemState {
  const FakeMenuItemState({
    required this.title,
    required this.keyEquivalent,
    required this.modifiers,
    required this.isSeparator,
  });

  final String title;
  final String keyEquivalent;
  final int modifiers;
  final bool isSeparator;
}

final class FakeNativeBindings implements NativeBindings {
  int reportedAbiVersion = dartAppKitAbiVersion;
  int mainThreadValue = 1;
  int nextHandle = 100;
  int? eventPort;
  int selectedEventProtocolVersion = dartAppKitCurrentEventProtocolVersion;
  int? requestedMinimumEventProtocolVersion;
  int? requestedMaximumEventProtocolVersion;
  bool terminateCalled = false;
  bool applicationTerminationDeferral = false;
  int? applicationTerminationReplyOperationId;
  bool? applicationTerminationReplyAllow;
  String? pasteboardText;
  int pasteboardChangeCount = 0;
  int? mainMenu;

  final Map<int, FakeObjectKind> objects = <int, FakeObjectKind>{};
  final Map<int, String> windowTitles = <int, String>{};
  final Map<int, String> texts = <int, String>{};
  final Map<int, String> customViewProviders = <int, String>{};
  final Map<int, int> contentViews = <int, int>{};
  final Map<int, bool> windowCloseDeferrals = <int, bool>{};
  final Map<int, int> windowKeyEventRoutings = <int, int>{};
  final Map<int, String> menuTitles = <int, String>{};
  final Map<int, FakeMenuItemState> menuItems = <int, FakeMenuItemState>{};
  final Map<int, List<int>> menuContents = <int, List<int>>{};
  final Map<int, int> submenus = <int, int>{};
  final Map<int, bool> menuItemEnabled = <int, bool>{};
  final List<int> performedMenuItems = <int>[];
  final List<int> windowCloseRequests = <int>[];
  int? windowCloseReplyHandle;
  int? windowCloseReplyOperationId;
  bool? windowCloseReplyAllow;
  final Set<Object> attachedFinalizers = <Object>{};
  final List<String> operations = <String>[];

  String? failNextOperation;
  int failureStatus = 7;
  String failureMessage = 'injected native failure';

  NativeCallResult _status(String operation) {
    operations.add(operation);
    if (failNextOperation == operation) {
      failNextOperation = null;
      return NativeCallResult.failure(failureStatus, failureMessage);
    }
    return const NativeCallResult.success();
  }

  NativeValueResult<T> _value<T>(String operation, T value) {
    operations.add(operation);
    if (failNextOperation == operation) {
      failNextOperation = null;
      return NativeValueResult<T>.failure(failureStatus, failureMessage);
    }
    return NativeValueResult<T>.success(value);
  }

  @override
  int abiVersion() => reportedAbiVersion;

  @override
  NativeCallResult applicationSetEventPort(int port) {
    final NativeCallResult result = _status('applicationSetEventPort');
    if (result.isSuccess) {
      eventPort = port;
    }
    return result;
  }

  @override
  NativeValueResult<int> applicationSetEventPortVersioned({
    required int port,
    required int minimumVersion,
    required int maximumVersion,
  }) {
    requestedMinimumEventProtocolVersion = minimumVersion;
    requestedMaximumEventProtocolVersion = maximumVersion;
    final NativeValueResult<int> result = _value<int>(
      'applicationSetEventPortVersioned',
      selectedEventProtocolVersion,
    );
    if (result.isSuccess) {
      eventPort = port;
    }
    return result;
  }

  @override
  NativeCallResult applicationTerminate() {
    final NativeCallResult result = _status('applicationTerminate');
    if (result.isSuccess) {
      terminateCalled = true;
    }
    return result;
  }

  @override
  NativeCallResult applicationSetTerminationRequestDeferral(bool enabled) {
    final NativeCallResult result = _status(
      'applicationSetTerminationRequestDeferral',
    );
    if (result.isSuccess) {
      applicationTerminationDeferral = enabled;
    }
    return result;
  }

  @override
  NativeCallResult applicationReplyToTerminationRequest({
    required int operationId,
    required bool allow,
  }) {
    final NativeCallResult result = _status(
      'applicationReplyToTerminationRequest',
    );
    if (result.isSuccess) {
      applicationTerminationReplyOperationId = operationId;
      applicationTerminationReplyAllow = allow;
    }
    return result;
  }

  @override
  NativeValueResult<NativePasteboardTextSnapshot> pasteboardReadText() =>
      _value<NativePasteboardTextSnapshot>(
        'pasteboardReadText',
        NativePasteboardTextSnapshot(
          text: pasteboardText,
          changeCount: pasteboardChangeCount,
        ),
      );

  @override
  NativeValueResult<int> pasteboardWriteText(String text) {
    final NativeValueResult<int> result = _value<int>(
      'pasteboardWriteText',
      pasteboardChangeCount + 1,
    );
    if (result.isSuccess) {
      pasteboardText = text;
      pasteboardChangeCount = result.value!;
    }
    return result;
  }

  @override
  NativeValueResult<int> pasteboardClear() {
    final NativeValueResult<int> result = _value<int>(
      'pasteboardClear',
      pasteboardChangeCount + 1,
    );
    if (result.isSuccess) {
      pasteboardText = null;
      pasteboardChangeCount = result.value!;
    }
    return result;
  }

  @override
  NativeValueResult<int> pasteboardGetChangeCount() =>
      _value<int>('pasteboardGetChangeCount', pasteboardChangeCount);

  @override
  NativeValueResult<int> menuCreate(String title) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('menuCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.menu;
      menuTitles[handle] = title;
      menuContents[handle] = <int>[];
    }
    return result;
  }

  @override
  NativeValueResult<int> menuItemCreate({
    required String title,
    required String keyEquivalent,
    required int modifiers,
  }) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('menuItemCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.menuItem;
      menuItems[handle] = FakeMenuItemState(
        title: title,
        keyEquivalent: keyEquivalent,
        modifiers: modifiers,
        isSeparator: false,
      );
      menuItemEnabled[handle] = true;
    }
    return result;
  }

  @override
  NativeValueResult<int> menuItemCreateSeparator() {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>(
      'menuItemCreateSeparator',
      handle,
    );
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.menuItem;
      menuItems[handle] = const FakeMenuItemState(
        title: '',
        keyEquivalent: '',
        modifiers: 0,
        isSeparator: true,
      );
    }
    return result;
  }

  @override
  NativeCallResult menuAddItem(int menuHandle, int itemHandle) {
    final NativeCallResult result = _status('menuAddItem');
    if (result.isSuccess) {
      menuContents[menuHandle]!.add(itemHandle);
    }
    return result;
  }

  @override
  NativeCallResult menuItemSetSubmenu(int itemHandle, int submenuHandle) {
    final NativeCallResult result = _status('menuItemSetSubmenu');
    if (result.isSuccess) {
      if (submenuHandle == 0) {
        submenus.remove(itemHandle);
      } else {
        submenus[itemHandle] = submenuHandle;
      }
    }
    return result;
  }

  @override
  NativeCallResult menuItemSetEnabled(int itemHandle, bool enabled) {
    final NativeCallResult result = _status('menuItemSetEnabled');
    if (result.isSuccess) {
      menuItemEnabled[itemHandle] = enabled;
    }
    return result;
  }

  @override
  NativeCallResult applicationSetMainMenu(int menuHandle) {
    final NativeCallResult result = _status('applicationSetMainMenu');
    if (result.isSuccess) {
      mainMenu = menuHandle == 0 ? null : menuHandle;
    }
    return result;
  }

  @override
  NativeCallResult menuItemPerformAction(int itemHandle) {
    final NativeCallResult result = _status('menuItemPerformAction');
    if (result.isSuccess) {
      performedMenuItems.add(itemHandle);
    }
    return result;
  }

  @override
  NativeValueResult<int> windowCreate({
    required double x,
    required double y,
    required double width,
    required double height,
    required String title,
  }) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('windowCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.window;
      windowTitles[handle] = title;
      windowKeyEventRoutings[handle] = 0;
    }
    return result;
  }

  @override
  NativeCallResult windowShow(int handle) => _status('windowShow');

  @override
  NativeCallResult windowClose(int handle) => _status('windowClose');

  @override
  NativeCallResult windowRequestClose(int handle) {
    final NativeCallResult result = _status('windowRequestClose');
    if (result.isSuccess) {
      windowCloseRequests.add(handle);
    }
    return result;
  }

  @override
  NativeCallResult windowSetCloseRequestDeferral(int handle, bool enabled) {
    final NativeCallResult result = _status('windowSetCloseRequestDeferral');
    if (result.isSuccess) {
      windowCloseDeferrals[handle] = enabled;
    }
    return result;
  }

  @override
  NativeCallResult windowSetKeyEventRouting(int handle, int routing) {
    final NativeCallResult result = _status('windowSetKeyEventRouting');
    if (result.isSuccess) {
      windowKeyEventRoutings[handle] = routing;
    }
    return result;
  }

  @override
  NativeCallResult windowReplyToCloseRequest({
    required int handle,
    required int operationId,
    required bool allow,
  }) {
    final NativeCallResult result = _status('windowReplyToCloseRequest');
    if (result.isSuccess) {
      windowCloseReplyHandle = handle;
      windowCloseReplyOperationId = operationId;
      windowCloseReplyAllow = allow;
    }
    return result;
  }

  @override
  NativeCallResult windowSetTitle(int handle, String title) {
    final NativeCallResult result = _status('windowSetTitle');
    if (result.isSuccess) {
      windowTitles[handle] = title;
    }
    return result;
  }

  @override
  NativeValueResult<int> viewCreate() {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('viewCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.view;
    }
    return result;
  }

  @override
  NativeValueResult<int> customViewCreate(String providerIdentifier) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>(
      'customViewCreate',
      handle,
    );
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.view;
      customViewProviders[handle] = providerIdentifier;
    }
    return result;
  }

  @override
  NativeValueResult<int> textViewCreate() {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('textViewCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.textView;
      texts[handle] = '';
    }
    return result;
  }

  @override
  NativeCallResult textViewSetText(int handle, String text) {
    final NativeCallResult result = _status('textViewSetText');
    if (result.isSuccess) {
      texts[handle] = text;
    }
    return result;
  }

  @override
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle) {
    final NativeCallResult result = _status('windowSetContentView');
    if (result.isSuccess) {
      contentViews[windowHandle] = viewHandle;
    }
    return result;
  }

  @override
  NativeCallResult release(int handle) {
    final NativeCallResult result = _status('release');
    if (result.isSuccess) {
      objects.remove(handle);
      windowTitles.remove(handle);
      texts.remove(handle);
      customViewProviders.remove(handle);
      contentViews.remove(handle);
      windowCloseDeferrals.remove(handle);
      windowKeyEventRoutings.remove(handle);
      menuTitles.remove(handle);
      menuItems.remove(handle);
      menuContents.remove(handle);
      submenus.remove(handle);
      menuItemEnabled.remove(handle);
      if (mainMenu == handle) {
        mainMenu = null;
      }
    }
    return result;
  }

  @override
  NativeValueResult<int> debugIsMainThread() =>
      _value<int>('debugIsMainThread', mainThreadValue);

  @override
  NativeValueResult<int> debugLiveObjectCount() =>
      _value<int>('debugLiveObjectCount', objects.length);

  @override
  void attachFinalizer(Finalizable value, int handle, Object detachKey) {
    attachedFinalizers.add(detachKey);
  }

  @override
  void detachFinalizer(Object detachKey) {
    attachedFinalizers.remove(detachKey);
  }
}
