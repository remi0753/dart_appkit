import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:dart_appkit/src/native/native_bindings.dart';

enum FakeObjectKind {
  window,
  view,
  splitView,
  textView,
  textEditor,
  menu,
  menuItem,
}

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

final class FakeNativeBindings
    implements
        NativeBindings,
        NativeTextEditorBindings,
        NativeSplitViewPositionBindings {
  int reportedAbiVersion = dartAppKitAbiVersion;
  int mainThreadValue = 1;
  int nextHandle = 100;
  int? eventPort;
  int selectedEventProtocolVersion = dartAppKitCurrentEventProtocolVersion;
  int? requestedMinimumEventProtocolVersion;
  int? requestedMaximumEventProtocolVersion;
  bool terminateCalled = false;
  bool applicationTerminationDeferral = false;
  int debugApplicationTerminationRequestCount = 0;
  int? applicationTerminationReplyOperationId;
  bool? applicationTerminationReplyAllow;
  bool externalUrlOpenResult = true;
  final List<String> openedExternalUrls = <String>[];
  final List<String> openedExternalUrlSchemes = <String>[];
  final List<int> openedExternalUrlPolicyFlags = <int>[];
  final List<({String identifier, String title, String body})>
  postedUserNotifications =
      <({String identifier, String title, String body})>[];
  final List<String> removedUserNotifications = <String>[];
  String? dockBadgeLabel;
  String? pasteboardText;
  int pasteboardChangeCount = 0;
  int? pasteboardTextUtf8LengthOverride;
  int? mainMenu;

  final Map<int, FakeObjectKind> objects = <int, FakeObjectKind>{};
  final Map<int, String> windowTitles = <int, String>{};
  final Map<int, List<double>> windowFrames = <int, List<double>>{};
  final Map<int, List<double>> windowContentLayoutRects = <int, List<double>>{};
  final Map<int, int> windowStyleMasks = <int, int>{};
  final Map<int, bool> windowFullscreenStates = <int, bool>{};
  final Map<int, String> windowRepresentedFilePaths = <int, String>{};
  final Map<int, List<double>> windowTabColors = <int, List<double>>{};
  final Map<int, List<num>> windowTabAccessories = <int, List<num>>{};
  final Map<int, NativeViewConfiguration> viewConfigurations =
      <int, NativeViewConfiguration>{};
  final Map<int, NativeTextViewConfiguration> textViewConfigurations =
      <int, NativeTextViewConfiguration>{};
  final Map<int, NativeTextEditorConfiguration> textEditorConfigurations =
      <int, NativeTextEditorConfiguration>{};
  final Map<int, List<NativeTextEditorStyleRun>> textEditorStyleRuns =
      <int, List<NativeTextEditorStyleRun>>{};
  final Map<int, NativeTextEditorLineHighlight?> textEditorLineHighlights =
      <int, NativeTextEditorLineHighlight?>{};
  final Map<int, int> textEditorSelectionStarts = <int, int>{};
  final Map<int, int> textEditorSelectionLengths = <int, int>{};
  final Map<int, bool> textEditorEditable = <int, bool>{};
  final Map<int, bool> textEditorHasMarkedText = <int, bool>{};
  final Map<int, String> texts = <int, String>{};
  final Map<int, String> customViewProviders = <int, String>{};
  final Map<int, List<Uint8List>> customViewOperations =
      <int, List<Uint8List>>{};
  final Map<int, int> contentViews = <int, int>{};
  final List<List<int>> windowTabGroups = <List<int>>[];
  final Map<int, int> selectedTabWindows = <int, int>{};
  final Map<int, int> firstResponders = <int, int>{};
  final Map<int, int> splitViewAxes = <int, int>{};
  final Map<int, List<int>> splitViewChildren = <int, List<int>>{};
  final Map<int, double> splitViewFractions = <int, double>{};
  final Map<int, double> splitViewFirstMinimumExtents = <int, double>{};
  final Map<int, double> splitViewSecondMinimumExtents = <int, double>{};
  final Map<int, int> splitViewZoomedChildren = <int, int>{};
  final Map<int, bool> windowCloseDeferrals = <int, bool>{};
  final Map<int, int> windowKeyEventRoutings = <int, int>{};
  final Map<int, String> menuTitles = <int, String>{};
  final Map<int, bool> menuAutoEnablesItems = <int, bool>{};
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
  NativeCallResult debugRequestApplicationTermination() {
    final NativeCallResult result = _status(
      'debugRequestApplicationTermination',
    );
    if (result.isSuccess) {
      debugApplicationTerminationRequestCount++;
    }
    return result;
  }

  @override
  NativeValueResult<int> applicationOpenExternalUrl(
    String url, {
    required String scheme,
    required int policyFlags,
  }) {
    final NativeValueResult<int> result = _value<int>(
      'applicationOpenExternalUrl',
      externalUrlOpenResult ? 1 : 0,
    );
    if (result.isSuccess) {
      openedExternalUrls.add(url);
      openedExternalUrlSchemes.add(scheme);
      openedExternalUrlPolicyFlags.add(policyFlags);
    }
    return result;
  }

  @override
  NativeCallResult applicationPostUserNotification({
    required String identifier,
    required String title,
    required String body,
  }) {
    final NativeCallResult result = _status('applicationPostUserNotification');
    if (result.isSuccess) {
      postedUserNotifications.add((
        identifier: identifier,
        title: title,
        body: body,
      ));
    }
    return result;
  }

  @override
  NativeCallResult applicationRemoveUserNotification(String identifier) {
    final NativeCallResult result = _status(
      'applicationRemoveUserNotification',
    );
    if (result.isSuccess) removedUserNotifications.add(identifier);
    return result;
  }

  @override
  NativeCallResult applicationSetDockBadgeLabel(String? label) {
    final NativeCallResult result = _status('applicationSetDockBadgeLabel');
    if (result.isSuccess) dockBadgeLabel = label;
    return result;
  }

  @override
  NativeValueResult<NativePasteboardTextSnapshot> pasteboardReadText() {
    final NativeValueResult<NativePasteboardTextSnapshot> result =
        _value<NativePasteboardTextSnapshot>(
          'pasteboardReadText',
          NativePasteboardTextSnapshot(
            text: pasteboardText,
            changeCount: pasteboardChangeCount,
          ),
        );
    if (!result.isSuccess) return result;
    final String? text = pasteboardText;
    final int length =
        pasteboardTextUtf8LengthOverride ??
        (text == null ? 0 : utf8.encode(text).length);
    if (length > dartAppKitPasteboardMaximumTextUtf8Bytes) {
      return const NativeValueResult<NativePasteboardTextSnapshot>.failure(
        10,
        'pasteboard UTF-8 text exceeds the read limit',
      );
    }
    return result;
  }

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
  NativeValueResult<int> menuCreate(
    String title, {
    required bool autoEnablesItems,
  }) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('menuCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.menu;
      menuTitles[handle] = title;
      menuAutoEnablesItems[handle] = autoEnablesItems;
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
    required int styleMask,
  }) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('windowCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.window;
      windowTitles[handle] = title;
      windowFrames[handle] = <double>[x, y, width, height];
      windowContentLayoutRects[handle] = <double>[0, 0, width, height];
      windowStyleMasks[handle] = styleMask;
      windowFullscreenStates[handle] = false;
      windowKeyEventRoutings[handle] = 0;
    }
    return result;
  }

  @override
  NativeCallResult windowShow(int handle) => _status('windowShow');

  @override
  NativeCallResult windowClose(int handle) => _status('windowClose');

  @override
  NativeCallResult windowSetFrame({
    required int handle,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    final NativeCallResult result = _status('windowSetFrame');
    if (result.isSuccess) {
      windowFrames[handle] = <double>[x, y, width, height];
      windowContentLayoutRects[handle] = <double>[0, 0, width, height];
    }
    return result;
  }

  @override
  NativeValueResult<NativeRect> windowGetContentLayoutRect(int handle) {
    final NativeCallResult status = _status('windowGetContentLayoutRect');
    if (!status.isSuccess) {
      return NativeValueResult<NativeRect>.failure(
        status.status,
        status.message,
      );
    }
    final List<double>? rect = windowContentLayoutRects[handle];
    if (rect == null) {
      return const NativeValueResult<NativeRect>.failure(2, 'unknown window');
    }
    return NativeValueResult<NativeRect>.success(
      NativeRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]),
    );
  }

  @override
  NativeCallResult windowSetFullscreen(int handle, bool enabled) {
    final NativeCallResult result = _status('windowSetFullscreen');
    if (result.isSuccess) windowFullscreenStates[handle] = enabled;
    return result;
  }

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
  NativeCallResult windowSetRepresentedFilePath(int handle, String? path) {
    final NativeCallResult result = _status('windowSetRepresentedFilePath');
    if (result.isSuccess) {
      if (path == null) {
        windowRepresentedFilePaths.remove(handle);
      } else {
        windowRepresentedFilePaths[handle] = path;
      }
    }
    return result;
  }

  @override
  NativeCallResult windowSetTabAccessory({
    required int handle,
    required bool hasAccessory,
    required int shape,
    required double width,
    required double height,
    required double red,
    required double green,
    required double blue,
    required double alpha,
  }) {
    final NativeCallResult result = _status('windowSetTabAccessory');
    if (result.isSuccess) {
      if (hasAccessory) {
        windowTabColors[handle] = <double>[red, green, blue, alpha];
        windowTabAccessories[handle] = <num>[shape, width, height];
      } else {
        windowTabColors.remove(handle);
        windowTabAccessories.remove(handle);
      }
    }
    return result;
  }

  @override
  NativeCallResult windowAddTabbedWindow(int handle, int tabbedWindowHandle) {
    final NativeCallResult result = _status('windowAddTabbedWindow');
    if (!result.isSuccess) return result;
    if (handle == tabbedWindowHandle ||
        objects[handle] != FakeObjectKind.window ||
        objects[tabbedWindowHandle] != FakeObjectKind.window) {
      return const NativeCallResult.failure(1, 'invalid tabbed windows');
    }
    for (final List<int> group in windowTabGroups.toList()) {
      if (group.remove(tabbedWindowHandle) && group.length < 2) {
        windowTabGroups.remove(group);
      }
    }
    List<int>? target;
    for (final List<int> group in windowTabGroups) {
      if (group.contains(handle)) {
        target = group;
        break;
      }
    }
    if (target == null) {
      target = <int>[handle];
      windowTabGroups.add(target);
    }
    target.add(tabbedWindowHandle);
    selectedTabWindows[target.first] = handle;
    return result;
  }

  @override
  NativeCallResult windowRemoveFromTabGroup(int handle) {
    final NativeCallResult result = _status('windowRemoveFromTabGroup');
    if (!result.isSuccess) return result;
    for (final List<int> group in windowTabGroups.toList()) {
      if (!group.remove(handle)) continue;
      selectedTabWindows.remove(group.first);
      if (group.length < 2) {
        windowTabGroups.remove(group);
      }
      break;
    }
    return result;
  }

  @override
  NativeCallResult windowSelectTab(int handle) {
    final NativeCallResult result = _status('windowSelectTab');
    if (!result.isSuccess) return result;
    for (final List<int> group in windowTabGroups) {
      if (group.contains(handle)) {
        selectedTabWindows[group.first] = handle;
        break;
      }
    }
    return result;
  }

  @override
  NativeCallResult windowMakeFirstResponder(int handle, int viewHandle) {
    final NativeCallResult result = _status('windowMakeFirstResponder');
    if (!result.isSuccess) return result;
    final int? contentView = contentViews[handle];
    if (contentView == null || !_containsView(contentView, viewHandle)) {
      return const NativeCallResult.failure(
        1,
        'first responder is not attached to the window',
      );
    }
    firstResponders[handle] = viewHandle;
    return result;
  }

  @override
  NativeValueResult<int> viewCreate(NativeViewConfiguration configuration) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('viewCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.view;
      viewConfigurations[handle] = configuration;
    }
    return result;
  }

  @override
  NativeValueResult<int> splitViewCreate(int axis) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>(
      'splitViewCreate',
      handle,
    );
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.splitView;
      splitViewAxes[handle] = axis;
      splitViewFractions[handle] = 0.5;
      splitViewZoomedChildren[handle] = -1;
    }
    return result;
  }

  @override
  NativeCallResult splitViewSetChildren(
    int splitViewHandle,
    int firstViewHandle,
    int secondViewHandle,
  ) {
    final NativeCallResult result = _status('splitViewSetChildren');
    if (result.isSuccess) {
      splitViewChildren[splitViewHandle] = <int>[
        firstViewHandle,
        secondViewHandle,
      ];
    }
    return result;
  }

  @override
  NativeCallResult splitViewSetPosition({
    required int handle,
    required double fraction,
    required double firstMinimumExtent,
    required double secondMinimumExtent,
  }) {
    final NativeCallResult result = _status('splitViewSetPosition');
    if (result.isSuccess) {
      splitViewFractions[handle] = fraction;
      splitViewFirstMinimumExtents[handle] = firstMinimumExtent;
      splitViewSecondMinimumExtents[handle] = secondMinimumExtent;
    }
    return result;
  }

  @override
  NativeValueResult<double> splitViewGetFraction(int handle) {
    final NativeCallResult result = _status('splitViewGetFraction');
    if (!result.isSuccess) {
      return NativeValueResult<double>.failure(result.status, result.message);
    }
    final double? fraction = splitViewFractions[handle];
    if (fraction == null) {
      return const NativeValueResult<double>.failure(
        3,
        'split view handle is invalid',
      );
    }
    return NativeValueResult<double>.success(fraction);
  }

  @override
  NativeCallResult splitViewEqualize(int handle) {
    final NativeCallResult result = _status('splitViewEqualize');
    if (result.isSuccess) {
      splitViewFractions[handle] = 0.5;
    }
    return result;
  }

  @override
  NativeCallResult splitViewSetZoomedChild(int handle, int child) {
    final NativeCallResult result = _status('splitViewSetZoomedChild');
    if (result.isSuccess) {
      splitViewZoomedChildren[handle] = child;
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
  NativeCallResult customViewPerformOperation(int handle, Uint8List payload) {
    final NativeCallResult result = _status('customViewPerformOperation');
    if (!result.isSuccess) return result;
    if (!customViewProviders.containsKey(handle)) {
      return const NativeCallResult.failure(
        1,
        'view has no registered custom operation',
      );
    }
    customViewOperations
        .putIfAbsent(handle, () => <Uint8List>[])
        .add(Uint8List.fromList(payload));
    return result;
  }

  @override
  NativeValueResult<int> textViewCreate(
    NativeTextViewConfiguration configuration,
  ) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>('textViewCreate', handle);
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.textView;
      viewConfigurations[handle] = configuration.view;
      textViewConfigurations[handle] = configuration;
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
  NativeValueResult<int> textEditorCreate(
    NativeTextEditorConfiguration configuration,
  ) {
    final int handle = nextHandle++;
    final NativeValueResult<int> result = _value<int>(
      'textEditorCreate',
      handle,
    );
    if (result.isSuccess) {
      objects[handle] = FakeObjectKind.textEditor;
      viewConfigurations[handle] = configuration.presentation.view;
      textEditorConfigurations[handle] = configuration;
      texts[handle] = '';
      textEditorStyleRuns[handle] = const <NativeTextEditorStyleRun>[];
      textEditorLineHighlights[handle] = null;
      textEditorSelectionStarts[handle] = 0;
      textEditorSelectionLengths[handle] = 0;
      textEditorEditable[handle] = configuration.initiallyEditable;
      textEditorHasMarkedText[handle] = false;
    }
    return result;
  }

  @override
  NativeCallResult textEditorSetDocument(
    int handle,
    NativeTextEditorDocument document,
  ) {
    final NativeCallResult result = _status('textEditorSetDocument');
    if (result.isSuccess) {
      texts[handle] = document.text;
      textEditorSelectionStarts[handle] = document.selectionStart;
      textEditorSelectionLengths[handle] = document.selectionLength;
      textEditorStyleRuns[handle] = List<NativeTextEditorStyleRun>.unmodifiable(
        document.styleRuns,
      );
      textEditorLineHighlights[handle] = null;
    }
    return result;
  }

  @override
  NativeCallResult textEditorSetStyleRuns(
    int handle,
    List<NativeTextEditorStyleRun> styleRuns,
  ) {
    final NativeCallResult result = _status('textEditorSetStyleRuns');
    if (result.isSuccess) {
      textEditorStyleRuns[handle] = List<NativeTextEditorStyleRun>.unmodifiable(
        styleRuns,
      );
    }
    return result;
  }

  @override
  NativeCallResult textEditorSetLineHighlight(
    int handle,
    NativeTextEditorLineHighlight? highlight,
  ) {
    final NativeCallResult result = _status('textEditorSetLineHighlight');
    if (result.isSuccess) textEditorLineHighlights[handle] = highlight;
    return result;
  }

  @override
  NativeCallResult textEditorSetEditable(int handle, bool editable) {
    final NativeCallResult result = _status('textEditorSetEditable');
    if (result.isSuccess) textEditorEditable[handle] = editable;
    return result;
  }

  @override
  NativeCallResult textEditorSetSelection(
    int handle, {
    required int start,
    required int length,
  }) {
    final NativeCallResult result = _status('textEditorSetSelection');
    if (result.isSuccess) {
      textEditorSelectionStarts[handle] = start;
      textEditorSelectionLengths[handle] = length;
    }
    return result;
  }

  @override
  NativeCallResult textEditorScrollSelectionToVisible(int handle) =>
      _status('textEditorScrollSelectionToVisible');

  @override
  NativeValueResult<NativeTextEditorSnapshot> textEditorSnapshot(int handle) =>
      _value<NativeTextEditorSnapshot>(
        'textEditorSnapshot',
        NativeTextEditorSnapshot(
          text: texts[handle]!,
          selectionStart: textEditorSelectionStarts[handle]!,
          selectionLength: textEditorSelectionLengths[handle]!,
          isEditable: textEditorEditable[handle]!,
          hasMarkedText: textEditorHasMarkedText[handle]!,
        ),
      );

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
      windowFrames.remove(handle);
      windowContentLayoutRects.remove(handle);
      windowFullscreenStates.remove(handle);
      windowRepresentedFilePaths.remove(handle);
      windowTabColors.remove(handle);
      viewConfigurations.remove(handle);
      textViewConfigurations.remove(handle);
      textEditorConfigurations.remove(handle);
      textEditorStyleRuns.remove(handle);
      textEditorLineHighlights.remove(handle);
      textEditorSelectionStarts.remove(handle);
      textEditorSelectionLengths.remove(handle);
      textEditorEditable.remove(handle);
      textEditorHasMarkedText.remove(handle);
      texts.remove(handle);
      customViewProviders.remove(handle);
      customViewOperations.remove(handle);
      contentViews.remove(handle);
      firstResponders.remove(handle);
      splitViewAxes.remove(handle);
      splitViewChildren.remove(handle);
      splitViewFractions.remove(handle);
      splitViewFirstMinimumExtents.remove(handle);
      splitViewSecondMinimumExtents.remove(handle);
      splitViewZoomedChildren.remove(handle);
      for (final List<int> group in windowTabGroups.toList()) {
        if (group.remove(handle) && group.length < 2) {
          windowTabGroups.remove(group);
        }
      }
      windowCloseDeferrals.remove(handle);
      windowKeyEventRoutings.remove(handle);
      menuTitles.remove(handle);
      menuAutoEnablesItems.remove(handle);
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

  bool _containsView(int root, int target) {
    if (root == target) return true;
    final List<int>? children = splitViewChildren[root];
    return children != null &&
        children.any((int child) => _containsView(child, target));
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
