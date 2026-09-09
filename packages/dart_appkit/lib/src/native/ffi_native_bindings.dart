import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'native_bindings.dart';

final class _DaRectNative extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;

  @Double()
  external double width;

  @Double()
  external double height;
}

final class _DaWindowConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Uint64()
  external int styleMask;
}

final class _DaErrorNative extends Struct {
  @Int32()
  external int code;

  external Pointer<Uint8> message;

  @Size()
  external int messageLength;
}

final class _DaPasteboardTextNative extends Struct {
  external Pointer<Uint8> text;

  @Size()
  external int textLength;

  @Int32()
  external int hasText;

  @Int64()
  external int changeCount;
}

typedef _AbiVersionNative = Uint32 Function();
typedef _AbiVersionDart = int Function();
typedef _SetEventPortNative = Int32 Function(Int64);
typedef _SetEventPortDart = int Function(int);
typedef _SetEventPortVersionedNative = Int32 Function(
  Int64,
  Uint32,
  Uint32,
  Pointer<Uint32>,
);
typedef _SetEventPortVersionedDart = int Function(
  int,
  int,
  int,
  Pointer<Uint32>,
);
typedef _NoArgsStatusNative = Int32 Function();
typedef _NoArgsStatusDart = int Function();
typedef _BoolStatusNative = Int32 Function(Int32);
typedef _BoolStatusDart = int Function(int);
typedef _OperationReplyNative = Int32 Function(Int64, Int32);
typedef _OperationReplyDart = int Function(int, int);
typedef _ExternalUrlOpenNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Int32>,
);
typedef _ExternalUrlOpenDart = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Int32>,
);
typedef _PasteboardReadNative = Int32 Function(
  Pointer<_DaPasteboardTextNative>,
);
typedef _PasteboardReadDart = int Function(Pointer<_DaPasteboardTextNative>);
typedef _PasteboardWriteNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Int64>,
);
typedef _PasteboardWriteDart = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Int64>,
);
typedef _Int64OutputNative = Int32 Function(Pointer<Int64>);
typedef _Int64OutputDart = int Function(Pointer<Int64>);
typedef _StringCreateNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint64>,
);
typedef _StringCreateDart = int Function(Pointer<Uint8>, int, Pointer<Uint64>);
typedef _MenuItemCreateNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
  Uint64,
  Pointer<Uint64>,
);
typedef _MenuItemCreateDart = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  int,
  Pointer<Uint64>,
);
typedef _WindowCreateNative = Int32 Function(
  _DaRectNative,
  Pointer<Uint8>,
  Size,
  Pointer<Uint64>,
);
typedef _WindowCreateDart = int Function(
  _DaRectNative,
  Pointer<Uint8>,
  int,
  Pointer<Uint64>,
);
typedef _WindowCreateConfiguredNative = Int32 Function(
  _DaRectNative,
  Pointer<Uint8>,
  Size,
  Pointer<_DaWindowConfigurationNative>,
  Pointer<Uint64>,
);
typedef _WindowCreateConfiguredDart = int Function(
  _DaRectNative,
  Pointer<Uint8>,
  int,
  Pointer<_DaWindowConfigurationNative>,
  Pointer<Uint64>,
);
typedef _HandleRectNative = Int32 Function(Uint64, _DaRectNative);
typedef _HandleRectDart = int Function(int, _DaRectNative);
typedef _HandleStatusNative = Int32 Function(Uint64);
typedef _HandleStatusDart = int Function(int);
typedef _HandleBoolStatusNative = Int32 Function(Uint64, Int32);
typedef _HandleBoolStatusDart = int Function(int, int);
typedef _HandleOperationReplyNative = Int32 Function(Uint64, Int64, Int32);
typedef _HandleOperationReplyDart = int Function(int, int, int);
typedef _HandleStringNative = Int32 Function(Uint64, Pointer<Uint8>, Size);
typedef _HandleStringDart = int Function(int, Pointer<Uint8>, int);
typedef _HandleBoolFourDoublesNative = Int32 Function(
  Uint64,
  Int32,
  Double,
  Double,
  Double,
  Double,
);
typedef _HandleBoolFourDoublesDart = int Function(
  int,
  int,
  double,
  double,
  double,
  double,
);
typedef _TwoHandlesNative = Int32 Function(Uint64, Uint64);
typedef _TwoHandlesDart = int Function(int, int);
typedef _ThreeHandlesNative = Int32 Function(Uint64, Uint64, Uint64);
typedef _ThreeHandlesDart = int Function(int, int, int);
typedef _HandleThreeDoublesNative = Int32 Function(
  Uint64,
  Double,
  Double,
  Double,
);
typedef _HandleThreeDoublesDart = int Function(int, double, double, double);
typedef _CreateHandleNative = Int32 Function(Pointer<Uint64>);
typedef _CreateHandleDart = int Function(Pointer<Uint64>);
typedef _IntCreateHandleNative = Int32 Function(Int32, Pointer<Uint64>);
typedef _IntCreateHandleDart = int Function(int, Pointer<Uint64>);
typedef _GetLastErrorNative = Void Function(Pointer<_DaErrorNative>);
typedef _GetLastErrorDart = void Function(Pointer<_DaErrorNative>);
typedef _DebugInt32Native = Int32 Function(Pointer<Int32>);
typedef _DebugInt32Dart = int Function(Pointer<Int32>);
typedef _DebugUint64Native = Int32 Function(Pointer<Uint64>);
typedef _DebugUint64Dart = int Function(Pointer<Uint64>);
typedef _MallocNative = Pointer<Void> Function(Size);
typedef _MallocDart = Pointer<Void> Function(int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

_SetEventPortVersionedDart? _lookupSetEventPortVersioned(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _SetEventPortVersionedNative,
      _SetEventPortVersionedDart
    >('da_application_set_event_port_versioned');
  } on ArgumentError {
    return null;
  }
}

_CreateHandleDart? _lookupViewCreate(DynamicLibrary library) {
  try {
    return library.lookupFunction<_CreateHandleNative, _CreateHandleDart>(
      'da_view_create',
    );
  } on ArgumentError {
    return null;
  }
}

_StringCreateDart? _lookupCustomViewCreate(DynamicLibrary library) {
  try {
    return library.lookupFunction<_StringCreateNative, _StringCreateDart>(
      'da_view_create_custom',
    );
  } on ArgumentError {
    return null;
  }
}

_HandleStringDart? _lookupCustomViewPerformOperation(DynamicLibrary library) {
  try {
    return library.lookupFunction<_HandleStringNative, _HandleStringDart>(
      'da_view_perform_custom_operation',
    );
  } on ArgumentError {
    return null;
  }
}

_BoolStatusDart? _lookupApplicationTerminationDeferral(DynamicLibrary library) {
  try {
    return library.lookupFunction<_BoolStatusNative, _BoolStatusDart>(
      'da_application_set_termination_request_deferral',
    );
  } on ArgumentError {
    return null;
  }
}

_OperationReplyDart? _lookupApplicationTerminationReply(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<_OperationReplyNative, _OperationReplyDart>(
      'da_application_reply_to_termination_request',
    );
  } on ArgumentError {
    return null;
  }
}

_NoArgsStatusDart? _lookupNoArgsStatus(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_NoArgsStatusNative, _NoArgsStatusDart>(
      symbol,
    );
  } on ArgumentError {
    return null;
  }
}

_ExternalUrlOpenDart? _lookupApplicationOpenExternalUrl(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<_ExternalUrlOpenNative, _ExternalUrlOpenDart>(
      'da_application_open_external_url',
    );
  } on ArgumentError {
    return null;
  }
}

_HandleStatusDart? _lookupWindowRequestClose(DynamicLibrary library) {
  try {
    return library.lookupFunction<_HandleStatusNative, _HandleStatusDart>(
      'da_window_request_close',
    );
  } on ArgumentError {
    return null;
  }
}

_WindowCreateConfiguredDart? _lookupWindowCreateConfigured(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _WindowCreateConfiguredNative,
      _WindowCreateConfiguredDart
    >('da_window_create_configured');
  } on ArgumentError {
    return null;
  }
}

_HandleRectDart? _lookupHandleRect(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_HandleRectNative, _HandleRectDart>(symbol);
  } on ArgumentError {
    return null;
  }
}

_HandleBoolStatusDart? _lookupWindowCloseDeferral(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_HandleBoolStatusNative, _HandleBoolStatusDart>(
          'da_window_set_close_request_deferral',
        );
  } on ArgumentError {
    return null;
  }
}

_HandleBoolStatusDart? _lookupWindowKeyEventRouting(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_HandleBoolStatusNative, _HandleBoolStatusDart>(
          'da_window_set_key_event_routing',
        );
  } on ArgumentError {
    return null;
  }
}

_HandleOperationReplyDart? _lookupWindowCloseReply(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_HandleOperationReplyNative, _HandleOperationReplyDart>(
          'da_window_reply_to_close_request',
        );
  } on ArgumentError {
    return null;
  }
}

_PasteboardReadDart? _lookupPasteboardRead(DynamicLibrary library) {
  try {
    return library.lookupFunction<_PasteboardReadNative, _PasteboardReadDart>(
      'da_pasteboard_read_text',
    );
  } on ArgumentError {
    return null;
  }
}

_PasteboardWriteDart? _lookupPasteboardWrite(DynamicLibrary library) {
  try {
    return library.lookupFunction<_PasteboardWriteNative, _PasteboardWriteDart>(
      'da_pasteboard_write_text',
    );
  } on ArgumentError {
    return null;
  }
}

_Int64OutputDart? _lookupPasteboardClear(DynamicLibrary library) {
  try {
    return library.lookupFunction<_Int64OutputNative, _Int64OutputDart>(
      'da_pasteboard_clear',
    );
  } on ArgumentError {
    return null;
  }
}

_Int64OutputDart? _lookupPasteboardChangeCount(DynamicLibrary library) {
  try {
    return library.lookupFunction<_Int64OutputNative, _Int64OutputDart>(
      'da_pasteboard_get_change_count',
    );
  } on ArgumentError {
    return null;
  }
}

_StringCreateDart? _lookupMenuCreate(DynamicLibrary library) {
  try {
    return library.lookupFunction<_StringCreateNative, _StringCreateDart>(
      'da_menu_create',
    );
  } on ArgumentError {
    return null;
  }
}

_MenuItemCreateDart? _lookupMenuItemCreate(DynamicLibrary library) {
  try {
    return library.lookupFunction<_MenuItemCreateNative, _MenuItemCreateDart>(
      'da_menu_item_create',
    );
  } on ArgumentError {
    return null;
  }
}

_CreateHandleDart? _lookupMenuItemCreateSeparator(DynamicLibrary library) {
  try {
    return library.lookupFunction<_CreateHandleNative, _CreateHandleDart>(
      'da_menu_item_create_separator',
    );
  } on ArgumentError {
    return null;
  }
}

_TwoHandlesDart? _lookupMenuAddItem(DynamicLibrary library) {
  try {
    return library.lookupFunction<_TwoHandlesNative, _TwoHandlesDart>(
      'da_menu_add_item',
    );
  } on ArgumentError {
    return null;
  }
}

_TwoHandlesDart? _lookupMenuItemSetSubmenu(DynamicLibrary library) {
  try {
    return library.lookupFunction<_TwoHandlesNative, _TwoHandlesDart>(
      'da_menu_item_set_submenu',
    );
  } on ArgumentError {
    return null;
  }
}

_HandleBoolStatusDart? _lookupMenuItemSetEnabled(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_HandleBoolStatusNative, _HandleBoolStatusDart>(
          'da_menu_item_set_enabled',
        );
  } on ArgumentError {
    return null;
  }
}

_HandleStatusDart? _lookupApplicationSetMainMenu(DynamicLibrary library) {
  try {
    return library.lookupFunction<_HandleStatusNative, _HandleStatusDart>(
      'da_application_set_main_menu',
    );
  } on ArgumentError {
    return null;
  }
}

_HandleStatusDart? _lookupMenuItemPerformAction(DynamicLibrary library) {
  try {
    return library.lookupFunction<_HandleStatusNative, _HandleStatusDart>(
      'da_menu_item_perform_action',
    );
  } on ArgumentError {
    return null;
  }
}

_TwoHandlesDart? _lookupWindowAddTabbedWindow(DynamicLibrary library) {
  try {
    return library.lookupFunction<_TwoHandlesNative, _TwoHandlesDart>(
      'da_window_add_tabbed_window',
    );
  } on ArgumentError {
    return null;
  }
}

_HandleBoolFourDoublesDart? _lookupHandleBoolFourDoubles(
  DynamicLibrary library,
  String symbol,
) {
  try {
    return library.lookupFunction<
      _HandleBoolFourDoublesNative,
      _HandleBoolFourDoublesDart
    >(symbol);
  } on ArgumentError {
    return null;
  }
}

_HandleStatusDart? _lookupHandleStatus(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_HandleStatusNative, _HandleStatusDart>(
      symbol,
    );
  } on ArgumentError {
    return null;
  }
}

_HandleStringDart? _lookupHandleString(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_HandleStringNative, _HandleStringDart>(
      symbol,
    );
  } on ArgumentError {
    return null;
  }
}

_TwoHandlesDart? _lookupTwoHandles(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_TwoHandlesNative, _TwoHandlesDart>(symbol);
  } on ArgumentError {
    return null;
  }
}

_ThreeHandlesDart? _lookupThreeHandles(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_ThreeHandlesNative, _ThreeHandlesDart>(
      symbol,
    );
  } on ArgumentError {
    return null;
  }
}

_HandleBoolStatusDart? _lookupHandleInt(DynamicLibrary library, String symbol) {
  try {
    return library
        .lookupFunction<_HandleBoolStatusNative, _HandleBoolStatusDart>(symbol);
  } on ArgumentError {
    return null;
  }
}

_HandleThreeDoublesDart? _lookupHandleThreeDoubles(
  DynamicLibrary library,
  String symbol,
) {
  try {
    return library
        .lookupFunction<_HandleThreeDoublesNative, _HandleThreeDoublesDart>(
          symbol,
        );
  } on ArgumentError {
    return null;
  }
}

_IntCreateHandleDart? _lookupIntCreateHandle(
  DynamicLibrary library,
  String symbol,
) {
  try {
    return library.lookupFunction<_IntCreateHandleNative, _IntCreateHandleDart>(
      symbol,
    );
  } on ArgumentError {
    return null;
  }
}

final class FfiNativeBindings implements NativeBindings {
  FfiNativeBindings._(DynamicLibrary library, DynamicLibrary allocatorLibrary)
    : _abiVersion = library.lookupFunction<_AbiVersionNative, _AbiVersionDart>(
        'da_abi_version',
      ),
      _setEventPort = library
          .lookupFunction<_SetEventPortNative, _SetEventPortDart>(
            'da_application_set_event_port',
          ),
      _setEventPortVersioned = _lookupSetEventPortVersioned(library),
      _terminate = library
          .lookupFunction<_NoArgsStatusNative, _NoArgsStatusDart>(
            'da_application_terminate',
          ),
      _applicationTerminationDeferral = _lookupApplicationTerminationDeferral(
        library,
      ),
      _applicationTerminationReply = _lookupApplicationTerminationReply(
        library,
      ),
      _debugRequestApplicationTermination = _lookupNoArgsStatus(
        library,
        'da_debug_request_application_termination',
      ),
      _applicationOpenExternalUrl = _lookupApplicationOpenExternalUrl(library),
      _pasteboardRead = _lookupPasteboardRead(library),
      _pasteboardWrite = _lookupPasteboardWrite(library),
      _pasteboardClear = _lookupPasteboardClear(library),
      _pasteboardChangeCount = _lookupPasteboardChangeCount(library),
      _menuCreate = _lookupMenuCreate(library),
      _menuItemCreate = _lookupMenuItemCreate(library),
      _menuItemCreateSeparator = _lookupMenuItemCreateSeparator(library),
      _menuAddItem = _lookupMenuAddItem(library),
      _menuItemSetSubmenu = _lookupMenuItemSetSubmenu(library),
      _menuItemSetEnabled = _lookupMenuItemSetEnabled(library),
      _applicationSetMainMenu = _lookupApplicationSetMainMenu(library),
      _menuItemPerformAction = _lookupMenuItemPerformAction(library),
      _windowCreate = library
          .lookupFunction<_WindowCreateNative, _WindowCreateDart>(
            'da_window_create',
          ),
      _windowCreateConfigured = _lookupWindowCreateConfigured(library),
      _windowShow = library
          .lookupFunction<_HandleStatusNative, _HandleStatusDart>(
            'da_window_show',
          ),
      _windowClose = library
          .lookupFunction<_HandleStatusNative, _HandleStatusDart>(
            'da_window_close',
          ),
      _windowSetFrame = _lookupHandleRect(library, 'da_window_set_frame'),
      _windowSetFullscreen = _lookupHandleInt(
        library,
        'da_window_set_fullscreen',
      ),
      _windowRequestClose = _lookupWindowRequestClose(library),
      _windowCloseDeferral = _lookupWindowCloseDeferral(library),
      _windowKeyEventRouting = _lookupWindowKeyEventRouting(library),
      _windowCloseReply = _lookupWindowCloseReply(library),
      _windowSetTitle = library
          .lookupFunction<_HandleStringNative, _HandleStringDart>(
            'da_window_set_title',
          ),
      _windowSetRepresentedFilePath = _lookupHandleString(
        library,
        'da_window_set_represented_file_path',
      ),
      _windowSetTabColor = _lookupHandleBoolFourDoubles(
        library,
        'da_window_set_tab_color',
      ),
      _windowAddTabbedWindow = _lookupWindowAddTabbedWindow(library),
      _windowRemoveFromTabGroup = _lookupHandleStatus(
        library,
        'da_window_remove_from_tab_group',
      ),
      _windowSelectTab = _lookupHandleStatus(library, 'da_window_select_tab'),
      _windowMakeFirstResponder = _lookupTwoHandles(
        library,
        'da_window_make_first_responder',
      ),
      _viewCreate = _lookupViewCreate(library),
      _splitViewCreate = _lookupIntCreateHandle(
        library,
        'da_split_view_create',
      ),
      _splitViewSetChildren = _lookupThreeHandles(
        library,
        'da_split_view_set_children',
      ),
      _splitViewSetPosition = _lookupHandleThreeDoubles(
        library,
        'da_split_view_set_position',
      ),
      _splitViewEqualize = _lookupHandleStatus(
        library,
        'da_split_view_equalize',
      ),
      _splitViewSetZoomedChild = _lookupHandleInt(
        library,
        'da_split_view_set_zoomed_child',
      ),
      _customViewCreate = _lookupCustomViewCreate(library),
      _customViewPerformOperation = _lookupCustomViewPerformOperation(library),
      _textViewCreate = library
          .lookupFunction<_CreateHandleNative, _CreateHandleDart>(
            'da_text_view_create',
          ),
      _textViewSetText = library
          .lookupFunction<_HandleStringNative, _HandleStringDart>(
            'da_text_view_set_text',
          ),
      _windowSetContentView = library
          .lookupFunction<_TwoHandlesNative, _TwoHandlesDart>(
            'da_window_set_content_view',
          ),
      _release = library.lookupFunction<_HandleStatusNative, _HandleStatusDart>(
        'da_release',
      ),
      _getLastError = library
          .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>(
            'da_get_last_error',
          ),
      _debugIsMainThread = library
          .lookupFunction<_DebugInt32Native, _DebugInt32Dart>(
            'da_debug_is_main_thread',
          ),
      _debugLiveObjectCount = library
          .lookupFunction<_DebugUint64Native, _DebugUint64Dart>(
            'da_debug_live_object_count',
          ),
      _nativeFinalizer = NativeFinalizer(
        library.lookup<NativeFinalizerFunction>('da_release_finalizer'),
      ),
      _malloc = allocatorLibrary.lookupFunction<_MallocNative, _MallocDart>(
        'malloc',
      ),
      _free = allocatorLibrary.lookupFunction<_FreeNative, _FreeDart>('free');

  factory FfiNativeBindings.process() {
    final DynamicLibrary process = DynamicLibrary.process();
    return FfiNativeBindings._(process, process);
  }

  factory FfiNativeBindings.open(String path) {
    return FfiNativeBindings._(
      DynamicLibrary.open(path),
      DynamicLibrary.process(),
    );
  }

  final _AbiVersionDart _abiVersion;
  final _SetEventPortDart _setEventPort;
  final _SetEventPortVersionedDart? _setEventPortVersioned;
  final _NoArgsStatusDart _terminate;
  final _BoolStatusDart? _applicationTerminationDeferral;
  final _OperationReplyDart? _applicationTerminationReply;
  final _NoArgsStatusDart? _debugRequestApplicationTermination;
  final _ExternalUrlOpenDart? _applicationOpenExternalUrl;
  final _PasteboardReadDart? _pasteboardRead;
  final _PasteboardWriteDart? _pasteboardWrite;
  final _Int64OutputDart? _pasteboardClear;
  final _Int64OutputDart? _pasteboardChangeCount;
  final _StringCreateDart? _menuCreate;
  final _MenuItemCreateDart? _menuItemCreate;
  final _CreateHandleDart? _menuItemCreateSeparator;
  final _TwoHandlesDart? _menuAddItem;
  final _TwoHandlesDart? _menuItemSetSubmenu;
  final _HandleBoolStatusDart? _menuItemSetEnabled;
  final _HandleStatusDart? _applicationSetMainMenu;
  final _HandleStatusDart? _menuItemPerformAction;
  final _WindowCreateDart _windowCreate;
  final _WindowCreateConfiguredDart? _windowCreateConfigured;
  final _HandleStatusDart _windowShow;
  final _HandleStatusDart _windowClose;
  final _HandleRectDart? _windowSetFrame;
  final _HandleBoolStatusDart? _windowSetFullscreen;
  final _HandleStatusDart? _windowRequestClose;
  final _HandleBoolStatusDart? _windowCloseDeferral;
  final _HandleBoolStatusDart? _windowKeyEventRouting;
  final _HandleOperationReplyDart? _windowCloseReply;
  final _HandleStringDart _windowSetTitle;
  final _HandleStringDart? _windowSetRepresentedFilePath;
  final _HandleBoolFourDoublesDart? _windowSetTabColor;
  final _TwoHandlesDart? _windowAddTabbedWindow;
  final _HandleStatusDart? _windowRemoveFromTabGroup;
  final _HandleStatusDart? _windowSelectTab;
  final _TwoHandlesDart? _windowMakeFirstResponder;
  final _CreateHandleDart? _viewCreate;
  final _IntCreateHandleDart? _splitViewCreate;
  final _ThreeHandlesDart? _splitViewSetChildren;
  final _HandleThreeDoublesDart? _splitViewSetPosition;
  final _HandleStatusDart? _splitViewEqualize;
  final _HandleBoolStatusDart? _splitViewSetZoomedChild;
  final _StringCreateDart? _customViewCreate;
  final _HandleStringDart? _customViewPerformOperation;
  final _CreateHandleDart _textViewCreate;
  final _HandleStringDart _textViewSetText;
  final _TwoHandlesDart _windowSetContentView;
  final _HandleStatusDart _release;
  final _GetLastErrorDart _getLastError;
  final _DebugInt32Dart _debugIsMainThread;
  final _DebugUint64Dart _debugLiveObjectCount;
  final NativeFinalizer _nativeFinalizer;
  final _MallocDart _malloc;
  final _FreeDart _free;

  Pointer<Void> _allocate(int byteCount) {
    final Pointer<Void> pointer = _malloc(byteCount);
    if (pointer.address == 0) {
      throw StateError('native allocation of $byteCount bytes failed');
    }
    return pointer;
  }

  String _lastErrorMessage() {
    final Pointer<_DaErrorNative> errorPointer = _allocate(
      sizeOf<_DaErrorNative>(),
    ).cast<_DaErrorNative>();
    try {
      _getLastError(errorPointer);
      final _DaErrorNative error = errorPointer.ref;
      if (error.messageLength == 0) {
        return '';
      }
      final List<int> bytes = error.message
          .asTypedList(error.messageLength)
          .toList(growable: false);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      _free(errorPointer.cast<Void>());
    }
  }

  NativeCallResult _callResult(int status) {
    if (status == 0) {
      return const NativeCallResult.success();
    }
    return NativeCallResult.failure(status, _lastErrorMessage());
  }

  NativeValueResult<T> _valueResult<T>(int status, T value) {
    if (status == 0) {
      return NativeValueResult<T>.success(value);
    }
    return NativeValueResult<T>.failure(status, _lastErrorMessage());
  }

  T _withUtf8<T>(
    String value,
    T Function(Pointer<Uint8> pointer, int length) body,
  ) {
    final List<int> bytes = utf8.encode(value);
    if (bytes.isEmpty) {
      return body(nullptr, 0);
    }
    final Pointer<Uint8> pointer = _allocate(bytes.length).cast<Uint8>();
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return body(pointer, bytes.length);
    } finally {
      _free(pointer.cast<Void>());
    }
  }

  T _withBytes<T>(
    Uint8List bytes,
    T Function(Pointer<Uint8> pointer, int length) body,
  ) {
    if (bytes.isEmpty) {
      return body(nullptr, 0);
    }
    final Pointer<Uint8> pointer = _allocate(bytes.length).cast<Uint8>();
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      return body(pointer, bytes.length);
    } finally {
      _free(pointer.cast<Void>());
    }
  }

  @override
  int abiVersion() => _abiVersion();

  @override
  NativeCallResult applicationSetEventPort(int port) =>
      _callResult(_setEventPort(port));

  @override
  NativeValueResult<int> applicationSetEventPortVersioned({
    required int port,
    required int minimumVersion,
    required int maximumVersion,
  }) {
    if (minimumVersion <= 0 ||
        maximumVersion <= 0 ||
        minimumVersion > maximumVersion ||
        maximumVersion > 0xffffffff) {
      return const NativeValueResult<int>.failure(
        1,
        'event protocol range must be positive, ordered, and unsigned 32-bit',
      );
    }
    final _SetEventPortVersionedDart? versioned = _setEventPortVersioned;
    if (versioned == null) {
      if (minimumVersion > 1 || maximumVersion < 1) {
        return const NativeValueResult<int>.failure(
          8,
          'legacy native bridge only supports event protocol version 1',
        );
      }
      final NativeCallResult result = applicationSetEventPort(port);
      return result.isSuccess
          ? const NativeValueResult<int>.success(1)
          : NativeValueResult<int>.failure(result.status, result.message);
    }
    final Pointer<Uint32> selected = _allocate(sizeOf<Uint32>()).cast<Uint32>();
    try {
      selected.value = 0;
      final int status = versioned(
        port,
        minimumVersion,
        maximumVersion,
        selected,
      );
      return _valueResult<int>(status, selected.value);
    } finally {
      _free(selected.cast<Void>());
    }
  }

  @override
  NativeCallResult applicationTerminate() => _callResult(_terminate());

  @override
  NativeCallResult applicationSetTerminationRequestDeferral(bool enabled) {
    final _BoolStatusDart? function = _applicationTerminationDeferral;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support termination request deferral',
      );
    }
    return _callResult(function(enabled ? 1 : 0));
  }

  @override
  NativeCallResult applicationReplyToTerminationRequest({
    required int operationId,
    required bool allow,
  }) {
    final _OperationReplyDart? function = _applicationTerminationReply;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support termination request replies',
      );
    }
    return _callResult(function(operationId, allow ? 1 : 0));
  }

  @override
  NativeCallResult debugRequestApplicationTermination() {
    final _NoArgsStatusDart? function = _debugRequestApplicationTermination;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support debug termination requests',
      );
    }
    return _callResult(function());
  }

  @override
  NativeValueResult<int> applicationOpenExternalUrl(String url) {
    final _ExternalUrlOpenDart? function = _applicationOpenExternalUrl;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support external URL opening',
      );
    }
    return _withUtf8(url, (Pointer<Uint8> pointer, int length) {
      final Pointer<Int32> output = _allocate(sizeOf<Int32>()).cast<Int32>();
      try {
        output.value = 0;
        final NativeValueResult<int> result = _valueResult<int>(
          function(pointer, length, output),
          output.value,
        );
        if (result.isSuccess && result.value != 0 && result.value != 1) {
          return const NativeValueResult<int>.failure(
            7,
            'native bridge returned an invalid external URL result',
          );
        }
        return result;
      } finally {
        _free(output.cast<Void>());
      }
    });
  }

  @override
  NativeValueResult<NativePasteboardTextSnapshot> pasteboardReadText() {
    final _PasteboardReadDart? function = _pasteboardRead;
    if (function == null) {
      return const NativeValueResult<NativePasteboardTextSnapshot>.failure(
        8,
        'legacy native bridge does not support pasteboard reads',
      );
    }
    final Pointer<_DaPasteboardTextNative> output = _allocate(
      sizeOf<_DaPasteboardTextNative>(),
    ).cast<_DaPasteboardTextNative>();
    try {
      output.ref
        ..text = nullptr
        ..textLength = 0
        ..hasText = 0
        ..changeCount = 0;
      final int status = function(output);
      if (status != 0) {
        return NativeValueResult<NativePasteboardTextSnapshot>.failure(
          status,
          _lastErrorMessage(),
        );
      }
      final _DaPasteboardTextNative snapshot = output.ref;
      if ((snapshot.hasText != 0 && snapshot.hasText != 1) ||
          snapshot.changeCount < 0 ||
          (snapshot.hasText == 0 &&
              (snapshot.text.address != 0 || snapshot.textLength != 0)) ||
          (snapshot.textLength > 0 && snapshot.text.address == 0)) {
        return const NativeValueResult<NativePasteboardTextSnapshot>.failure(
          7,
          'native bridge returned an invalid pasteboard snapshot',
        );
      }
      String? text;
      if (snapshot.hasText == 1) {
        if (snapshot.textLength == 0) {
          text = '';
        } else {
          try {
            text = utf8.decode(
              snapshot.text
                  .asTypedList(snapshot.textLength)
                  .toList(growable: false),
            );
          } on FormatException {
            return const NativeValueResult<
              NativePasteboardTextSnapshot
            >.failure(
              7,
              'native bridge returned invalid UTF-8 pasteboard text',
            );
          }
        }
      }
      return NativeValueResult<NativePasteboardTextSnapshot>.success(
        NativePasteboardTextSnapshot(
          text: text,
          changeCount: snapshot.changeCount,
        ),
      );
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeValueResult<int> pasteboardWriteText(String text) {
    final _PasteboardWriteDart? function = _pasteboardWrite;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support pasteboard writes',
      );
    }
    return _withUtf8(text, (Pointer<Uint8> pointer, int length) {
      return _pasteboardCountResult(
        (Pointer<Int64> output) => function(pointer, length, output),
      );
    });
  }

  @override
  NativeValueResult<int> pasteboardClear() {
    final _Int64OutputDart? function = _pasteboardClear;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support pasteboard clear',
      );
    }
    return _pasteboardCountResult(function);
  }

  @override
  NativeValueResult<int> pasteboardGetChangeCount() {
    final _Int64OutputDart? function = _pasteboardChangeCount;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support pasteboard change counts',
      );
    }
    return _pasteboardCountResult(function);
  }

  NativeValueResult<int> _pasteboardCountResult(
    int Function(Pointer<Int64>) body,
  ) {
    final Pointer<Int64> output = _allocate(sizeOf<Int64>()).cast<Int64>();
    try {
      output.value = 0;
      final int status = body(output);
      final NativeValueResult<int> result = _valueResult<int>(
        status,
        output.value,
      );
      if (result.isSuccess && result.value! < 0) {
        return const NativeValueResult<int>.failure(
          7,
          'native bridge returned a negative pasteboard change count',
        );
      }
      return result;
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeValueResult<int> menuCreate(String title) {
    final _StringCreateDart? function = _menuCreate;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support menus',
      );
    }
    final Pointer<Uint64> output = _allocate(sizeOf<Uint64>()).cast<Uint64>();
    try {
      output.value = 0;
      return _withUtf8(title, (Pointer<Uint8> pointer, int length) {
        return _valueResult<int>(
          function(pointer, length, output),
          output.value,
        );
      });
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeValueResult<int> menuItemCreate({
    required String title,
    required String keyEquivalent,
    required int modifiers,
  }) {
    final _MenuItemCreateDart? function = _menuItemCreate;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support menu items',
      );
    }
    if (modifiers < 0 || (modifiers & ~0x7f) != 0) {
      return const NativeValueResult<int>.failure(
        1,
        'menu shortcut contains unsupported modifier bits',
      );
    }
    final Pointer<Uint64> output = _allocate(sizeOf<Uint64>()).cast<Uint64>();
    try {
      output.value = 0;
      return _withUtf8(title, (Pointer<Uint8> titlePointer, int titleLength) {
        return _withUtf8(keyEquivalent, (
          Pointer<Uint8> keyPointer,
          int keyLength,
        ) {
          final int status = function(
            titlePointer,
            titleLength,
            keyPointer,
            keyLength,
            modifiers,
            output,
          );
          return _valueResult<int>(status, output.value);
        });
      });
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeValueResult<int> menuItemCreateSeparator() {
    final _CreateHandleDart? function = _menuItemCreateSeparator;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support menu separators',
      );
    }
    final Pointer<Uint64> output = _allocate(sizeOf<Uint64>()).cast<Uint64>();
    try {
      output.value = 0;
      return _valueResult<int>(function(output), output.value);
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeCallResult menuAddItem(int menuHandle, int itemHandle) {
    final _TwoHandlesDart? function = _menuAddItem;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support menu item attachment',
      );
    }
    return _callResult(function(menuHandle, itemHandle));
  }

  @override
  NativeCallResult menuItemSetSubmenu(int itemHandle, int submenuHandle) {
    final _TwoHandlesDart? function = _menuItemSetSubmenu;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support submenus',
      );
    }
    return _callResult(function(itemHandle, submenuHandle));
  }

  @override
  NativeCallResult menuItemSetEnabled(int itemHandle, bool enabled) {
    final _HandleBoolStatusDart? function = _menuItemSetEnabled;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support menu item state',
      );
    }
    return _callResult(function(itemHandle, enabled ? 1 : 0));
  }

  @override
  NativeCallResult applicationSetMainMenu(int menuHandle) {
    final _HandleStatusDart? function = _applicationSetMainMenu;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support application menus',
      );
    }
    return _callResult(function(menuHandle));
  }

  @override
  NativeCallResult menuItemPerformAction(int itemHandle) {
    final _HandleStatusDart? function = _menuItemPerformAction;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support menu actions',
      );
    }
    return _callResult(function(itemHandle));
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
    final _WindowCreateConfiguredDart? configured = _windowCreateConfigured;
    if (configured == null && styleMask != dartAppKitDefaultWindowStyleMask) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge supports only the default window style',
      );
    }
    final Pointer<_DaRectNative> rectPointer = _allocate(
      sizeOf<_DaRectNative>(),
    ).cast<_DaRectNative>();
    final Pointer<_DaWindowConfigurationNative> configurationPointer =
        _allocate(sizeOf<_DaWindowConfigurationNative>())
            .cast<_DaWindowConfigurationNative>();
    final Pointer<Uint64> handlePointer = _allocate(sizeOf<Uint64>())
        .cast<Uint64>();
    try {
      rectPointer.ref
        ..x = x
        ..y = y
        ..width = width
        ..height = height;
      configurationPointer.ref
        ..structSize = sizeOf<_DaWindowConfigurationNative>()
        ..styleMask = styleMask;
      handlePointer.value = 0;
      return _withUtf8(title, (Pointer<Uint8> pointer, int length) {
        final int status = configured == null
            ? _windowCreate(rectPointer.ref, pointer, length, handlePointer)
            : configured(
                rectPointer.ref,
                pointer,
                length,
                configurationPointer,
                handlePointer,
              );
        return _valueResult<int>(status, handlePointer.value);
      });
    } finally {
      _free(handlePointer.cast<Void>());
      _free(configurationPointer.cast<Void>());
      _free(rectPointer.cast<Void>());
    }
  }

  @override
  NativeCallResult windowShow(int handle) => _callResult(_windowShow(handle));

  @override
  NativeCallResult windowClose(int handle) => _callResult(_windowClose(handle));

  @override
  NativeCallResult windowSetFrame({
    required int handle,
    required double x,
    required double y,
    required double width,
    required double height,
  }) {
    final _HandleRectDart? function = _windowSetFrame;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support window frame mutation',
      );
    }
    final Pointer<_DaRectNative> rectPointer = _malloc(sizeOf<_DaRectNative>())
        .cast<_DaRectNative>();
    try {
      rectPointer.ref
        ..x = x
        ..y = y
        ..width = width
        ..height = height;
      return _callResult(function(handle, rectPointer.ref));
    } finally {
      _free(rectPointer.cast<Void>());
    }
  }

  @override
  NativeCallResult windowSetFullscreen(int handle, bool enabled) {
    final _HandleBoolStatusDart? function = _windowSetFullscreen;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support native fullscreen',
      );
    }
    return _callResult(function(handle, enabled ? 1 : 0));
  }

  @override
  NativeCallResult windowRequestClose(int handle) {
    final _HandleStatusDart? function = _windowRequestClose;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support user close requests',
      );
    }
    return _callResult(function(handle));
  }

  @override
  NativeCallResult windowSetCloseRequestDeferral(int handle, bool enabled) {
    final _HandleBoolStatusDart? function = _windowCloseDeferral;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support close request deferral',
      );
    }
    return _callResult(function(handle, enabled ? 1 : 0));
  }

  @override
  NativeCallResult windowSetKeyEventRouting(int handle, int routing) {
    final _HandleBoolStatusDart? function = _windowKeyEventRouting;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support key event routing',
      );
    }
    return _callResult(function(handle, routing));
  }

  @override
  NativeCallResult windowReplyToCloseRequest({
    required int handle,
    required int operationId,
    required bool allow,
  }) {
    final _HandleOperationReplyDart? function = _windowCloseReply;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support close request replies',
      );
    }
    return _callResult(function(handle, operationId, allow ? 1 : 0));
  }

  @override
  NativeCallResult windowSetTitle(int handle, String title) =>
      _withUtf8(title, (Pointer<Uint8> pointer, int length) {
        return _callResult(_windowSetTitle(handle, pointer, length));
      });

  @override
  NativeCallResult windowSetRepresentedFilePath(int handle, String? path) {
    final _HandleStringDart? function = _windowSetRepresentedFilePath;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support represented file paths',
      );
    }
    return _withUtf8(path ?? '', (Pointer<Uint8> pointer, int length) {
      return _callResult(function(handle, pointer, length));
    });
  }

  @override
  NativeCallResult windowSetTabColor({
    required int handle,
    required bool hasColor,
    required double red,
    required double green,
    required double blue,
    required double alpha,
  }) {
    final _HandleBoolFourDoublesDart? function = _windowSetTabColor;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support native tab colors',
      );
    }
    return _callResult(
      function(handle, hasColor ? 1 : 0, red, green, blue, alpha),
    );
  }

  @override
  NativeCallResult windowAddTabbedWindow(int handle, int tabbedWindowHandle) {
    final _TwoHandlesDart? function = _windowAddTabbedWindow;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support native window tabs',
      );
    }
    return _callResult(function(handle, tabbedWindowHandle));
  }

  @override
  NativeCallResult windowRemoveFromTabGroup(int handle) {
    final _HandleStatusDart? function = _windowRemoveFromTabGroup;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support native window tabs',
      );
    }
    return _callResult(function(handle));
  }

  @override
  NativeCallResult windowSelectTab(int handle) {
    final _HandleStatusDart? function = _windowSelectTab;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support native window tabs',
      );
    }
    return _callResult(function(handle));
  }

  @override
  NativeCallResult windowMakeFirstResponder(int handle, int viewHandle) {
    final _TwoHandlesDart? function = _windowMakeFirstResponder;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support explicit first responders',
      );
    }
    return _callResult(function(handle, viewHandle));
  }

  @override
  NativeValueResult<int> viewCreate() {
    final _CreateHandleDart? viewCreate = _viewCreate;
    if (viewCreate == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support generic views',
      );
    }
    final Pointer<Uint64> handlePointer = _allocate(sizeOf<Uint64>())
        .cast<Uint64>();
    try {
      handlePointer.value = 0;
      final int status = viewCreate(handlePointer);
      return _valueResult<int>(status, handlePointer.value);
    } finally {
      _free(handlePointer.cast<Void>());
    }
  }

  @override
  NativeValueResult<int> splitViewCreate(int axis) {
    final _IntCreateHandleDart? function = _splitViewCreate;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support split views',
      );
    }
    final Pointer<Uint64> handlePointer = _allocate(sizeOf<Uint64>())
        .cast<Uint64>();
    try {
      handlePointer.value = 0;
      final int status = function(axis, handlePointer);
      return _valueResult<int>(status, handlePointer.value);
    } finally {
      _free(handlePointer.cast<Void>());
    }
  }

  @override
  NativeCallResult splitViewSetChildren(
    int splitViewHandle,
    int firstViewHandle,
    int secondViewHandle,
  ) {
    final _ThreeHandlesDart? function = _splitViewSetChildren;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support split views',
      );
    }
    return _callResult(
      function(splitViewHandle, firstViewHandle, secondViewHandle),
    );
  }

  @override
  NativeCallResult splitViewSetPosition({
    required int handle,
    required double fraction,
    required double firstMinimumExtent,
    required double secondMinimumExtent,
  }) {
    final _HandleThreeDoublesDart? function = _splitViewSetPosition;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support split views',
      );
    }
    return _callResult(
      function(handle, fraction, firstMinimumExtent, secondMinimumExtent),
    );
  }

  @override
  NativeCallResult splitViewEqualize(int handle) {
    final _HandleStatusDart? function = _splitViewEqualize;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support split views',
      );
    }
    return _callResult(function(handle));
  }

  @override
  NativeCallResult splitViewSetZoomedChild(int handle, int child) {
    final _HandleBoolStatusDart? function = _splitViewSetZoomedChild;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support split views',
      );
    }
    return _callResult(function(handle, child));
  }

  @override
  NativeValueResult<int> customViewCreate(String providerIdentifier) {
    final _StringCreateDart? customViewCreate = _customViewCreate;
    if (customViewCreate == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support registered custom views',
      );
    }
    return _withUtf8(providerIdentifier, (Pointer<Uint8> pointer, int length) {
      final Pointer<Uint64> handlePointer = _allocate(sizeOf<Uint64>())
          .cast<Uint64>();
      try {
        handlePointer.value = 0;
        final int status = customViewCreate(pointer, length, handlePointer);
        return _valueResult<int>(status, handlePointer.value);
      } finally {
        _free(handlePointer.cast<Void>());
      }
    });
  }

  @override
  NativeCallResult customViewPerformOperation(int handle, Uint8List payload) {
    final _HandleStringDart? operation = _customViewPerformOperation;
    if (operation == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support custom view operations',
      );
    }
    return _withBytes(
      payload,
      (Pointer<Uint8> pointer, int length) =>
          _callResult(operation(handle, pointer, length)),
    );
  }

  @override
  NativeValueResult<int> textViewCreate() {
    final Pointer<Uint64> handlePointer = _allocate(sizeOf<Uint64>())
        .cast<Uint64>();
    try {
      handlePointer.value = 0;
      final int status = _textViewCreate(handlePointer);
      return _valueResult<int>(status, handlePointer.value);
    } finally {
      _free(handlePointer.cast<Void>());
    }
  }

  @override
  NativeCallResult textViewSetText(int handle, String text) =>
      _withUtf8(text, (Pointer<Uint8> pointer, int length) {
        return _callResult(_textViewSetText(handle, pointer, length));
      });

  @override
  NativeCallResult windowSetContentView(int windowHandle, int viewHandle) =>
      _callResult(_windowSetContentView(windowHandle, viewHandle));

  @override
  NativeCallResult release(int handle) => _callResult(_release(handle));

  @override
  NativeValueResult<int> debugIsMainThread() {
    final Pointer<Int32> output = _allocate(sizeOf<Int32>()).cast<Int32>();
    try {
      output.value = 0;
      final int status = _debugIsMainThread(output);
      return _valueResult<int>(status, output.value);
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeValueResult<int> debugLiveObjectCount() {
    final Pointer<Uint64> output = _allocate(sizeOf<Uint64>()).cast<Uint64>();
    try {
      output.value = 0;
      final int status = _debugLiveObjectCount(output);
      return _valueResult<int>(status, output.value);
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  void attachFinalizer(Finalizable value, int handle, Object detachKey) {
    _nativeFinalizer.attach(
      value,
      Pointer<Void>.fromAddress(handle),
      detach: detachKey,
    );
  }

  @override
  void detachFinalizer(Object detachKey) {
    _nativeFinalizer.detach(detachKey);
  }
}
