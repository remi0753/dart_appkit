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

final class _DaScreenSnapshotNative extends Struct {
  @Uint64()
  external int structSize;

  @Uint64()
  external int displayId;

  external _DaRectNative frame;

  external _DaRectNative visibleFrame;

  @Double()
  external double backingScaleFactor;
}

final class _DaSecureEventInputSnapshotNative extends Struct {
  @Uint64()
  external int structSize;

  @Int32()
  external int desired;

  @Int32()
  external int ownedEnabled;

  @Int32()
  external int systemEnabled;

  @Int32()
  external int lastOsStatus;
}

final class _DaWindowPresentationConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Int32()
  external int level;

  @Int32()
  external int reserved;

  @Uint64()
  external int collectionBehaviorMask;
}

final class _DaWindowTabAccessoryConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Int32()
  external int shape;

  @Int32()
  external int reserved;

  @Double()
  external double width;

  @Double()
  external double height;

  @Double()
  external double red;

  @Double()
  external double green;

  @Double()
  external double blue;

  @Double()
  external double alpha;
}

final class _DaViewConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Uint64()
  external int autoresizingMask;

  @Int32()
  external int acceptsFirstResponder;

  @Int32()
  external int reserved;
}

final class _DaDefinitionPresentationConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Int32()
  external int fontKind;

  @Int32()
  external int fontWeight;

  @Int32()
  external int reserved0;

  @Int32()
  external int reserved1;

  @Double()
  external double fontSize;

  @Double()
  external double baselineX;

  @Double()
  external double baselineY;
}

final class _DaServicesTextRequestorConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Uint64()
  external int maximumReturnedTextUtf8Bytes;

  @Int32()
  external int hasSelection;

  @Int32()
  external int acceptsReturnedText;

  @Int32()
  external int reserved0;

  @Int32()
  external int reserved1;
}

final class _DaDropDestinationConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Uint64()
  external int maximumTextUtf8Bytes;

  @Uint64()
  external int maximumFileUrlCount;

  @Uint64()
  external int maximumFileUrlUtf8Bytes;

  @Uint64()
  external int maximumTotalFileUrlUtf8Bytes;

  @Int32()
  external int acceptsPlainText;

  @Int32()
  external int acceptsFileUrls;

  @Int32()
  external int reserved0;

  @Int32()
  external int reserved1;
}

final class _DaFolderServicesProviderConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Uint64()
  external int maximumFileUrlCount;

  @Uint64()
  external int maximumFileUrlUtf8Bytes;

  @Uint64()
  external int maximumTotalFileUrlUtf8Bytes;

  @Int32()
  external int reserved0;

  @Int32()
  external int reserved1;
}

final class _DaTextViewColorConfigurationNative extends Struct {
  @Int32()
  external int kind;

  @Int32()
  external int reserved;

  @Double()
  external double red;

  @Double()
  external double green;

  @Double()
  external double blue;

  @Double()
  external double alpha;
}

final class _DaTextViewConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  external _DaViewConfigurationNative view;

  @Int32()
  external int fontKind;

  @Int32()
  external int fontWeight;

  @Double()
  external double fontSize;

  @Double()
  external double paddingTop;

  @Double()
  external double paddingRight;

  @Double()
  external double paddingBottom;

  @Double()
  external double paddingLeft;

  external _DaTextViewColorConfigurationNative foregroundColor;

  external _DaTextViewColorConfigurationNative backgroundColor;
}

final class _DaTextEditorConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  external _DaTextViewConfigurationNative presentation;

  @Int32()
  external int initiallyEditable;

  @Int32()
  external int reserved;
}

final class _DaTextEditorStyleRunNative extends Struct {
  @Uint64()
  external int location;

  @Uint64()
  external int length;

  external _DaTextViewColorConfigurationNative foregroundColor;

  @Int32()
  external int underlineStyle;

  @Int32()
  external int reserved;

  external _DaTextViewColorConfigurationNative underlineColor;
}

final class _DaTextEditorSnapshotNative extends Struct {
  external Pointer<Uint8> text;

  @Size()
  external int textLength;

  @Uint64()
  external int selectionLocation;

  @Uint64()
  external int selectionLength;

  @Int32()
  external int isEditable;

  @Int32()
  external int hasMarkedText;
}

final class _DaMenuConfigurationNative extends Struct {
  @Uint64()
  external int structSize;

  @Int32()
  external int autoEnablesItems;

  @Int32()
  external int reserved;
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
typedef _ExternalUrlOpenWithPolicyNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
  Uint64,
  Pointer<Int32>,
);
typedef _ExternalUrlOpenWithPolicyDart = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  int,
  Pointer<Int32>,
);
typedef _StringStatusNative = Int32 Function(Pointer<Uint8>, Size);
typedef _StringStatusDart = int Function(Pointer<Uint8>, int);
typedef _ThreeStringsStatusNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
);
typedef _ThreeStringsStatusDart = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
);
typedef _TrackedUserNotificationNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
  Pointer<Uint8>,
  Size,
  Int64,
  Pointer<Int64>,
);
typedef _TrackedUserNotificationDart = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  int,
  Pointer<Int64>,
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
typedef _MenuCreateConfiguredNative = Int32 Function(
  Pointer<Uint8>,
  Size,
  Pointer<_DaMenuConfigurationNative>,
  Pointer<Uint64>,
);
typedef _MenuCreateConfiguredDart = int Function(
  Pointer<Uint8>,
  int,
  Pointer<_DaMenuConfigurationNative>,
  Pointer<Uint64>,
);
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
typedef _ScreenResolveNative = Int32 Function(
  Int32,
  Pointer<_DaScreenSnapshotNative>,
);
typedef _ScreenResolveDart = int Function(
  int,
  Pointer<_DaScreenSnapshotNative>,
);
typedef _WindowSetPresentationConfigurationNative = Int32 Function(
  Uint64,
  Pointer<_DaWindowPresentationConfigurationNative>,
);
typedef _WindowSetPresentationConfigurationDart = int Function(
  int,
  Pointer<_DaWindowPresentationConfigurationNative>,
);
typedef _WindowPresentNative = Int32 Function(
  Uint64,
  _DaRectNative,
  _DaRectNative,
  Double,
  Int32,
);
typedef _WindowPresentDart = int Function(
  int,
  _DaRectNative,
  _DaRectNative,
  double,
  int,
);
typedef _WindowHideNative = Int32 Function(Uint64, _DaRectNative, Double);
typedef _WindowHideDart = int Function(int, _DaRectNative, double);
typedef _HandleRectNative = Int32 Function(Uint64, _DaRectNative);
typedef _HandleRectDart = int Function(int, _DaRectNative);
typedef _HandleRectOutputNative = Int32 Function(
  Uint64,
  Pointer<_DaRectNative>,
);
typedef _HandleRectOutputDart = int Function(int, Pointer<_DaRectNative>);
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
typedef _WindowTabAccessoryNative = Int32 Function(
  Uint64,
  Int32,
  Pointer<_DaWindowTabAccessoryConfigurationNative>,
);
typedef _WindowTabAccessoryDart = int Function(
  int,
  int,
  Pointer<_DaWindowTabAccessoryConfigurationNative>,
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
typedef _HandleDoubleOutputNative = Int32 Function(Uint64, Pointer<Double>);
typedef _HandleDoubleOutputDart = int Function(int, Pointer<Double>);
typedef _CreateHandleNative = Int32 Function(Pointer<Uint64>);
typedef _CreateHandleDart = int Function(Pointer<Uint64>);
typedef _GlobalHotKeyRegisterNative = Int32 Function(
  Uint16,
  Uint64,
  Pointer<Uint64>,
);
typedef _GlobalHotKeyRegisterDart = int Function(int, int, Pointer<Uint64>);
typedef _SecureEventInputSnapshotNative = Int32 Function(
  Uint64,
  Pointer<_DaSecureEventInputSnapshotNative>,
);
typedef _SecureEventInputSnapshotDart = int Function(
  int,
  Pointer<_DaSecureEventInputSnapshotNative>,
);
typedef _ViewCreateConfiguredNative = Int32 Function(
  Pointer<_DaViewConfigurationNative>,
  Pointer<Uint64>,
);
typedef _ViewCreateConfiguredDart = int Function(
  Pointer<_DaViewConfigurationNative>,
  Pointer<Uint64>,
);
typedef _ViewShowDefinitionNative = Int32 Function(
  Uint64,
  Pointer<Uint8>,
  Size,
  Pointer<_DaDefinitionPresentationConfigurationNative>,
  Pointer<Uint8>,
  Size,
);
typedef _ViewShowDefinitionDart = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<_DaDefinitionPresentationConfigurationNative>,
  Pointer<Uint8>,
  int,
);
typedef _ViewSetServicesTextRequestorNative = Int32 Function(
  Uint64,
  Pointer<Uint8>,
  Size,
  Pointer<_DaServicesTextRequestorConfigurationNative>,
);
typedef _ViewSetServicesTextRequestorDart = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<_DaServicesTextRequestorConfigurationNative>,
);
typedef _ViewSetDropDestinationNative = Int32 Function(
  Uint64,
  Pointer<_DaDropDestinationConfigurationNative>,
);
typedef _ViewSetDropDestinationDart = int Function(
  int,
  Pointer<_DaDropDestinationConfigurationNative>,
);
typedef _ApplicationSetFolderServicesProviderNative = Int32 Function(
  Pointer<_DaFolderServicesProviderConfigurationNative>,
);
typedef _ApplicationSetFolderServicesProviderDart = int Function(
  Pointer<_DaFolderServicesProviderConfigurationNative>,
);
typedef _TextViewCreateConfiguredNative = Int32 Function(
  Pointer<_DaTextViewConfigurationNative>,
  Pointer<Uint8>,
  Size,
  Pointer<Uint64>,
);
typedef _TextViewCreateConfiguredDart = int Function(
  Pointer<_DaTextViewConfigurationNative>,
  Pointer<Uint8>,
  int,
  Pointer<Uint64>,
);
typedef _TextEditorCreateConfiguredNative = Int32 Function(
  Pointer<_DaTextEditorConfigurationNative>,
  Pointer<Uint8>,
  Size,
  Pointer<Uint64>,
);
typedef _TextEditorCreateConfiguredDart = int Function(
  Pointer<_DaTextEditorConfigurationNative>,
  Pointer<Uint8>,
  int,
  Pointer<Uint64>,
);
typedef _TextEditorSetDocumentNative = Int32 Function(
  Uint64,
  Pointer<Uint8>,
  Size,
  Pointer<_DaTextEditorStyleRunNative>,
  Size,
  Uint64,
  Uint64,
);
typedef _TextEditorSetDocumentDart = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<_DaTextEditorStyleRunNative>,
  int,
  int,
  int,
);
typedef _TextEditorSetStyleRunsNative = Int32 Function(
  Uint64,
  Pointer<_DaTextEditorStyleRunNative>,
  Size,
);
typedef _TextEditorSetStyleRunsDart = int Function(
  int,
  Pointer<_DaTextEditorStyleRunNative>,
  int,
);
typedef _TextEditorSetLineHighlightNative = Int32 Function(
  Uint64,
  Uint64,
  Pointer<_DaTextViewColorConfigurationNative>,
);
typedef _TextEditorSetLineHighlightDart = int Function(
  int,
  int,
  Pointer<_DaTextViewColorConfigurationNative>,
);
typedef _TextEditorSetSelectionNative = Int32 Function(Uint64, Uint64, Uint64);
typedef _TextEditorSetSelectionDart = int Function(int, int, int);
typedef _TextEditorGetSnapshotNative = Int32 Function(
  Uint64,
  Pointer<_DaTextEditorSnapshotNative>,
);
typedef _TextEditorGetSnapshotDart = int Function(
  int,
  Pointer<_DaTextEditorSnapshotNative>,
);
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

_CreateHandleDart? _lookupCreateHandle(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_CreateHandleNative, _CreateHandleDart>(
      symbol,
    );
  } on ArgumentError {
    return null;
  }
}

_CreateHandleDart? _lookupViewCreate(DynamicLibrary library) =>
    _lookupCreateHandle(library, 'da_view_create');

_ViewCreateConfiguredDart? _lookupViewCreateConfigured(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_ViewCreateConfiguredNative, _ViewCreateConfiguredDart>(
          'da_view_create_configured',
        );
  } on ArgumentError {
    return null;
  }
}

_ViewShowDefinitionDart? _lookupViewShowDefinition(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_ViewShowDefinitionNative, _ViewShowDefinitionDart>(
          'da_view_show_definition',
        );
  } on ArgumentError {
    return null;
  }
}

_ViewSetServicesTextRequestorDart? _lookupViewSetServicesTextRequestor(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _ViewSetServicesTextRequestorNative,
      _ViewSetServicesTextRequestorDart
    >('da_view_set_services_text_requestor');
  } on ArgumentError {
    return null;
  }
}

_ViewSetDropDestinationDart? _lookupViewSetDropDestination(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _ViewSetDropDestinationNative,
      _ViewSetDropDestinationDart
    >('da_view_set_drop_destination');
  } on ArgumentError {
    return null;
  }
}

_ApplicationSetFolderServicesProviderDart?
_lookupApplicationSetFolderServicesProvider(DynamicLibrary library) {
  try {
    return library.lookupFunction<
      _ApplicationSetFolderServicesProviderNative,
      _ApplicationSetFolderServicesProviderDart
    >('da_application_set_folder_services_provider');
  } on ArgumentError {
    return null;
  }
}

_TextViewCreateConfiguredDart? _lookupTextViewCreateConfigured(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _TextViewCreateConfiguredNative,
      _TextViewCreateConfiguredDart
    >('da_text_view_create_configured');
  } on ArgumentError {
    return null;
  }
}

_TextEditorCreateConfiguredDart? _lookupTextEditorCreateConfigured(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _TextEditorCreateConfiguredNative,
      _TextEditorCreateConfiguredDart
    >('da_text_editor_create_configured');
  } on ArgumentError {
    return null;
  }
}

_TextEditorSetDocumentDart? _lookupTextEditorSetDocument(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _TextEditorSetDocumentNative,
      _TextEditorSetDocumentDart
    >('da_text_editor_set_document');
  } on ArgumentError {
    return null;
  }
}

_TextEditorSetStyleRunsDart? _lookupTextEditorSetStyleRuns(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _TextEditorSetStyleRunsNative,
      _TextEditorSetStyleRunsDart
    >('da_text_editor_set_style_runs');
  } on ArgumentError {
    return null;
  }
}

_TextEditorSetLineHighlightDart? _lookupTextEditorSetLineHighlight(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _TextEditorSetLineHighlightNative,
      _TextEditorSetLineHighlightDart
    >('da_text_editor_set_line_highlight');
  } on ArgumentError {
    return null;
  }
}

_TextEditorSetSelectionDart? _lookupTextEditorSetSelection(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _TextEditorSetSelectionNative,
      _TextEditorSetSelectionDart
    >('da_text_editor_set_selection');
  } on ArgumentError {
    return null;
  }
}

_TextEditorGetSnapshotDart? _lookupTextEditorGetSnapshot(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _TextEditorGetSnapshotNative,
      _TextEditorGetSnapshotDart
    >('da_text_editor_get_snapshot');
  } on ArgumentError {
    return null;
  }
}

void _writeViewConfiguration(
  _DaViewConfigurationNative output,
  NativeViewConfiguration configuration,
) {
  output
    ..structSize = sizeOf<_DaViewConfigurationNative>()
    ..autoresizingMask = configuration.autoresizingMask
    ..acceptsFirstResponder = configuration.acceptsFirstResponder ? 1 : 0
    ..reserved = 0;
}

void _writeDefinitionPresentation(
  _DaDefinitionPresentationConfigurationNative output,
  NativeDefinitionPresentation presentation,
) {
  output
    ..structSize = sizeOf<_DaDefinitionPresentationConfigurationNative>()
    ..fontKind = presentation.fontKind
    ..fontWeight = presentation.fontWeight
    ..reserved0 = 0
    ..reserved1 = 0
    ..fontSize = presentation.fontSize
    ..baselineX = presentation.baselineX
    ..baselineY = presentation.baselineY;
}

void _writeServicesTextRequestorConfiguration(
  _DaServicesTextRequestorConfigurationNative output,
  NativeServicesTextRequestorConfiguration configuration,
) {
  output
    ..structSize = sizeOf<_DaServicesTextRequestorConfigurationNative>()
    ..maximumReturnedTextUtf8Bytes = configuration.maximumReturnedTextUtf8Bytes
    ..hasSelection = configuration.selectionText == null ? 0 : 1
    ..acceptsReturnedText = configuration.acceptsReturnedText ? 1 : 0
    ..reserved0 = 0
    ..reserved1 = 0;
}

void _writeDropDestinationConfiguration(
  _DaDropDestinationConfigurationNative output,
  NativeDropDestinationConfiguration configuration,
) {
  output
    ..structSize = sizeOf<_DaDropDestinationConfigurationNative>()
    ..maximumTextUtf8Bytes = configuration.maximumTextUtf8Bytes
    ..maximumFileUrlCount = configuration.maximumFileUrlCount
    ..maximumFileUrlUtf8Bytes = configuration.maximumFileUrlUtf8Bytes
    ..maximumTotalFileUrlUtf8Bytes = configuration.maximumTotalFileUrlUtf8Bytes
    ..acceptsPlainText = configuration.acceptsPlainText ? 1 : 0
    ..acceptsFileUrls = configuration.acceptsFileUrls ? 1 : 0
    ..reserved0 = 0
    ..reserved1 = 0;
}

void _writeFolderServicesProviderConfiguration(
  _DaFolderServicesProviderConfigurationNative output,
  NativeFolderServicesProviderConfiguration configuration,
) {
  output
    ..structSize = sizeOf<_DaFolderServicesProviderConfigurationNative>()
    ..maximumFileUrlCount = configuration.maximumFileUrlCount
    ..maximumFileUrlUtf8Bytes = configuration.maximumFileUrlUtf8Bytes
    ..maximumTotalFileUrlUtf8Bytes = configuration.maximumTotalFileUrlUtf8Bytes
    ..reserved0 = 0
    ..reserved1 = 0;
}

void _writeTextViewColor(
  _DaTextViewColorConfigurationNative output, {
  required int kind,
  required double red,
  required double green,
  required double blue,
  required double alpha,
}) {
  output
    ..kind = kind
    ..reserved = 0
    ..red = red
    ..green = green
    ..blue = blue
    ..alpha = alpha;
}

void _writeTextViewConfiguration(
  _DaTextViewConfigurationNative output,
  NativeTextViewConfiguration configuration,
) {
  output
    ..structSize = sizeOf<_DaTextViewConfigurationNative>()
    ..fontKind = configuration.fontKind
    ..fontWeight = configuration.fontWeight
    ..fontSize = configuration.fontSize
    ..paddingTop = configuration.paddingTop
    ..paddingRight = configuration.paddingRight
    ..paddingBottom = configuration.paddingBottom
    ..paddingLeft = configuration.paddingLeft;
  _writeViewConfiguration(output.view, configuration.view);
  _writeTextViewColor(
    output.foregroundColor,
    kind: configuration.foregroundColorKind,
    red: configuration.foregroundRed,
    green: configuration.foregroundGreen,
    blue: configuration.foregroundBlue,
    alpha: configuration.foregroundAlpha,
  );
  _writeTextViewColor(
    output.backgroundColor,
    kind: configuration.backgroundColorKind,
    red: configuration.backgroundRed,
    green: configuration.backgroundGreen,
    blue: configuration.backgroundBlue,
    alpha: configuration.backgroundAlpha,
  );
}

void _writeTextEditorStyleRun(
  _DaTextEditorStyleRunNative output,
  NativeTextEditorStyleRun run,
) {
  output
    ..location = run.start
    ..length = run.length
    ..underlineStyle = run.underlineStyle
    ..reserved = 0;
  _writeTextViewColor(
    output.foregroundColor,
    kind: run.foregroundColorKind,
    red: run.foregroundRed,
    green: run.foregroundGreen,
    blue: run.foregroundBlue,
    alpha: run.foregroundAlpha,
  );
  _writeTextViewColor(
    output.underlineColor,
    kind: run.underlineColorKind,
    red: run.underlineRed,
    green: run.underlineGreen,
    blue: run.underlineBlue,
    alpha: run.underlineAlpha,
  );
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

_ExternalUrlOpenWithPolicyDart? _lookupApplicationOpenExternalUrlWithPolicy(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _ExternalUrlOpenWithPolicyNative,
      _ExternalUrlOpenWithPolicyDart
    >('da_application_open_external_url_with_policy');
  } on ArgumentError {
    return null;
  }
}

_StringStatusDart? _lookupStringStatus(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_StringStatusNative, _StringStatusDart>(
      symbol,
    );
  } on ArgumentError {
    return null;
  }
}

_ThreeStringsStatusDart? _lookupThreeStringsStatus(
  DynamicLibrary library,
  String symbol,
) {
  try {
    return library
        .lookupFunction<_ThreeStringsStatusNative, _ThreeStringsStatusDart>(
          symbol,
        );
  } on ArgumentError {
    return null;
  }
}

_Int64OutputDart? _lookupInt64Output(DynamicLibrary library, String symbol) {
  try {
    return library.lookupFunction<_Int64OutputNative, _Int64OutputDart>(symbol);
  } on ArgumentError {
    return null;
  }
}

_TrackedUserNotificationDart? _lookupTrackedUserNotification(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _TrackedUserNotificationNative,
      _TrackedUserNotificationDart
    >('da_application_post_tracked_user_notification');
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

_HandleRectOutputDart? _lookupHandleRectOutput(
  DynamicLibrary library,
  String symbol,
) {
  try {
    return library
        .lookupFunction<_HandleRectOutputNative, _HandleRectOutputDart>(symbol);
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

_MenuCreateConfiguredDart? _lookupMenuCreateConfigured(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_MenuCreateConfiguredNative, _MenuCreateConfiguredDart>(
          'da_menu_create_configured',
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

_WindowTabAccessoryDart? _lookupWindowTabAccessory(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_WindowTabAccessoryNative, _WindowTabAccessoryDart>(
          'da_window_set_tab_accessory',
        );
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

_HandleDoubleOutputDart? _lookupHandleDoubleOutput(
  DynamicLibrary library,
  String symbol,
) {
  try {
    return library
        .lookupFunction<_HandleDoubleOutputNative, _HandleDoubleOutputDart>(
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

_GlobalHotKeyRegisterDart? _lookupGlobalHotKeyRegister(DynamicLibrary library) {
  try {
    return library
        .lookupFunction<_GlobalHotKeyRegisterNative, _GlobalHotKeyRegisterDart>(
          'da_global_hot_key_register',
        );
  } on ArgumentError {
    return null;
  }
}

_SecureEventInputSnapshotDart? _lookupSecureEventInputSnapshot(
  DynamicLibrary library,
) {
  try {
    return library.lookupFunction<
      _SecureEventInputSnapshotNative,
      _SecureEventInputSnapshotDart
    >('da_secure_event_input_get_snapshot');
  } on ArgumentError {
    return null;
  }
}

_ScreenResolveDart? _lookupScreenResolve(DynamicLibrary library) {
  try {
    return library.lookupFunction<_ScreenResolveNative, _ScreenResolveDart>(
      'da_application_resolve_screen',
    );
  } on ArgumentError {
    return null;
  }
}

_WindowSetPresentationConfigurationDart?
_lookupWindowSetPresentationConfiguration(DynamicLibrary library) {
  try {
    return library.lookupFunction<
      _WindowSetPresentationConfigurationNative,
      _WindowSetPresentationConfigurationDart
    >('da_window_set_presentation_configuration');
  } on ArgumentError {
    return null;
  }
}

_WindowPresentDart? _lookupWindowPresent(DynamicLibrary library) {
  try {
    return library.lookupFunction<_WindowPresentNative, _WindowPresentDart>(
      'da_window_present',
    );
  } on ArgumentError {
    return null;
  }
}

_WindowHideDart? _lookupWindowHide(DynamicLibrary library) {
  try {
    return library.lookupFunction<_WindowHideNative, _WindowHideDart>(
      'da_window_hide',
    );
  } on ArgumentError {
    return null;
  }
}

final class FfiNativeBindings
    implements
        NativeBindings,
        NativeTextEditorBindings,
        NativeSplitViewPositionBindings,
        NativeGlobalHotKeyBindings,
        NativeMenuItemStateBindings,
        NativeViewContextMenuBindings,
        NativeQuickLookBindings,
        NativeServicesTextRequestorBindings,
        NativeDropDestinationBindings,
        NativeFolderServicesProviderBindings,
        NativeUserNotificationLifecycleBindings,
        NativeSecureEventInputBindings,
        NativeWindowPresentationBindings {
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
      _applicationOpenExternalUrlWithPolicy =
          _lookupApplicationOpenExternalUrlWithPolicy(library),
      _applicationPostUserNotification = _lookupThreeStringsStatus(
        library,
        'da_application_post_user_notification',
      ),
      _applicationGetUserNotificationSettings = _lookupInt64Output(
        library,
        'da_application_get_user_notification_settings',
      ),
      _applicationRequestUserNotificationAuthorization = _lookupInt64Output(
        library,
        'da_application_request_user_notification_authorization',
      ),
      _applicationPostTrackedUserNotification = _lookupTrackedUserNotification(
        library,
      ),
      _applicationRemoveUserNotification = _lookupStringStatus(
        library,
        'da_application_remove_user_notification',
      ),
      _applicationSetDockBadgeLabel = _lookupStringStatus(
        library,
        'da_application_set_dock_badge_label',
      ),
      _globalHotKeyRegister = _lookupGlobalHotKeyRegister(library),
      _secureEventInputCreate = _lookupCreateHandle(
        library,
        'da_secure_event_input_create',
      ),
      _secureEventInputSetDesired = _lookupHandleInt(
        library,
        'da_secure_event_input_set_desired',
      ),
      _secureEventInputGetSnapshot = _lookupSecureEventInputSnapshot(library),
      _applicationResolveScreen = _lookupScreenResolve(library),
      _pasteboardRead = _lookupPasteboardRead(library),
      _pasteboardWrite = _lookupPasteboardWrite(library),
      _pasteboardClear = _lookupPasteboardClear(library),
      _pasteboardChangeCount = _lookupPasteboardChangeCount(library),
      _menuCreate = _lookupMenuCreate(library),
      _menuCreateConfigured = _lookupMenuCreateConfigured(library),
      _menuItemCreate = _lookupMenuItemCreate(library),
      _menuItemCreateSeparator = _lookupMenuItemCreateSeparator(library),
      _menuAddItem = _lookupMenuAddItem(library),
      _menuItemSetSubmenu = _lookupMenuItemSetSubmenu(library),
      _menuItemSetEnabled = _lookupMenuItemSetEnabled(library),
      _menuItemSetChecked = _lookupHandleInt(
        library,
        'da_menu_item_set_checked',
      ),
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
      _windowGetContentLayoutRect = _lookupHandleRectOutput(
        library,
        'da_window_get_content_layout_rect',
      ),
      _windowSetFullscreen = _lookupHandleInt(
        library,
        'da_window_set_fullscreen',
      ),
      _windowSetPresentationConfiguration =
          _lookupWindowSetPresentationConfiguration(library),
      _windowPresent = _lookupWindowPresent(library),
      _windowHide = _lookupWindowHide(library),
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
      _windowSetTabAccessory = _lookupWindowTabAccessory(library),
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
      _viewCreateConfigured = _lookupViewCreateConfigured(library),
      _viewSetSecureInputIndicator = _lookupHandleInt(
        library,
        'da_view_set_secure_input_indicator',
      ),
      _viewSetContextMenu = _lookupTwoHandles(
        library,
        'da_view_set_context_menu',
      ),
      _viewSetQuickLookRequestEnabled = _lookupHandleInt(
        library,
        'da_view_set_quick_look_request_enabled',
      ),
      _viewShowDefinition = _lookupViewShowDefinition(library),
      _viewSetServicesTextRequestor = _lookupViewSetServicesTextRequestor(
        library,
      ),
      _viewSetDropDestination = _lookupViewSetDropDestination(library),
      _applicationSetFolderServicesProvider =
          _lookupApplicationSetFolderServicesProvider(library),
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
      _splitViewGetFraction = _lookupHandleDoubleOutput(
        library,
        'da_split_view_get_fraction',
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
      _textViewCreateConfigured = _lookupTextViewCreateConfigured(library),
      _textViewSetText = library
          .lookupFunction<_HandleStringNative, _HandleStringDart>(
            'da_text_view_set_text',
          ),
      _textEditorCreateConfigured = _lookupTextEditorCreateConfigured(library),
      _textEditorSetDocument = _lookupTextEditorSetDocument(library),
      _textEditorSetStyleRuns = _lookupTextEditorSetStyleRuns(library),
      _textEditorSetLineHighlight = _lookupTextEditorSetLineHighlight(library),
      _textEditorSetEditable = _lookupHandleInt(
        library,
        'da_text_editor_set_editable',
      ),
      _textEditorSetSelection = _lookupTextEditorSetSelection(library),
      _textEditorScrollSelectionToVisible = _lookupHandleStatus(
        library,
        'da_text_editor_scroll_selection_to_visible',
      ),
      _textEditorGetSnapshot = _lookupTextEditorGetSnapshot(library),
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
  final _ExternalUrlOpenWithPolicyDart? _applicationOpenExternalUrlWithPolicy;
  final _ThreeStringsStatusDart? _applicationPostUserNotification;
  final _Int64OutputDart? _applicationGetUserNotificationSettings;
  final _Int64OutputDart? _applicationRequestUserNotificationAuthorization;
  final _TrackedUserNotificationDart? _applicationPostTrackedUserNotification;
  final _StringStatusDart? _applicationRemoveUserNotification;
  final _StringStatusDart? _applicationSetDockBadgeLabel;
  final _GlobalHotKeyRegisterDart? _globalHotKeyRegister;
  final _CreateHandleDart? _secureEventInputCreate;
  final _HandleBoolStatusDart? _secureEventInputSetDesired;
  final _SecureEventInputSnapshotDart? _secureEventInputGetSnapshot;
  final _ScreenResolveDart? _applicationResolveScreen;
  final _PasteboardReadDart? _pasteboardRead;
  final _PasteboardWriteDart? _pasteboardWrite;
  final _Int64OutputDart? _pasteboardClear;
  final _Int64OutputDart? _pasteboardChangeCount;
  final _StringCreateDart? _menuCreate;
  final _MenuCreateConfiguredDart? _menuCreateConfigured;
  final _MenuItemCreateDart? _menuItemCreate;
  final _CreateHandleDart? _menuItemCreateSeparator;
  final _TwoHandlesDart? _menuAddItem;
  final _TwoHandlesDart? _menuItemSetSubmenu;
  final _HandleBoolStatusDart? _menuItemSetEnabled;
  final _HandleBoolStatusDart? _menuItemSetChecked;
  final _HandleStatusDart? _applicationSetMainMenu;
  final _HandleStatusDart? _menuItemPerformAction;
  final _WindowCreateDart _windowCreate;
  final _WindowCreateConfiguredDart? _windowCreateConfigured;
  final _HandleStatusDart _windowShow;
  final _HandleStatusDart _windowClose;
  final _HandleRectDart? _windowSetFrame;
  final _HandleRectOutputDart? _windowGetContentLayoutRect;
  final _HandleBoolStatusDart? _windowSetFullscreen;
  final _WindowSetPresentationConfigurationDart?
  _windowSetPresentationConfiguration;
  final _WindowPresentDart? _windowPresent;
  final _WindowHideDart? _windowHide;
  final _HandleStatusDart? _windowRequestClose;
  final _HandleBoolStatusDart? _windowCloseDeferral;
  final _HandleBoolStatusDart? _windowKeyEventRouting;
  final _HandleOperationReplyDart? _windowCloseReply;
  final _HandleStringDart _windowSetTitle;
  final _HandleStringDart? _windowSetRepresentedFilePath;
  final _HandleBoolFourDoublesDart? _windowSetTabColor;
  final _WindowTabAccessoryDart? _windowSetTabAccessory;
  final _TwoHandlesDart? _windowAddTabbedWindow;
  final _HandleStatusDart? _windowRemoveFromTabGroup;
  final _HandleStatusDart? _windowSelectTab;
  final _TwoHandlesDart? _windowMakeFirstResponder;
  final _CreateHandleDart? _viewCreate;
  final _ViewCreateConfiguredDart? _viewCreateConfigured;
  final _HandleBoolStatusDart? _viewSetSecureInputIndicator;
  final _TwoHandlesDart? _viewSetContextMenu;
  final _HandleBoolStatusDart? _viewSetQuickLookRequestEnabled;
  final _ViewShowDefinitionDart? _viewShowDefinition;
  final _ViewSetServicesTextRequestorDart? _viewSetServicesTextRequestor;
  final _ViewSetDropDestinationDart? _viewSetDropDestination;
  final _ApplicationSetFolderServicesProviderDart?
  _applicationSetFolderServicesProvider;
  final _IntCreateHandleDart? _splitViewCreate;
  final _ThreeHandlesDart? _splitViewSetChildren;
  final _HandleThreeDoublesDart? _splitViewSetPosition;
  final _HandleDoubleOutputDart? _splitViewGetFraction;
  final _HandleStatusDart? _splitViewEqualize;
  final _HandleBoolStatusDart? _splitViewSetZoomedChild;
  final _StringCreateDart? _customViewCreate;
  final _HandleStringDart? _customViewPerformOperation;
  final _CreateHandleDart _textViewCreate;
  final _TextViewCreateConfiguredDart? _textViewCreateConfigured;
  final _HandleStringDart _textViewSetText;
  final _TextEditorCreateConfiguredDart? _textEditorCreateConfigured;
  final _TextEditorSetDocumentDart? _textEditorSetDocument;
  final _TextEditorSetStyleRunsDart? _textEditorSetStyleRuns;
  final _TextEditorSetLineHighlightDart? _textEditorSetLineHighlight;
  final _HandleBoolStatusDart? _textEditorSetEditable;
  final _TextEditorSetSelectionDart? _textEditorSetSelection;
  final _HandleStatusDart? _textEditorScrollSelectionToVisible;
  final _TextEditorGetSnapshotDart? _textEditorGetSnapshot;
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

  T _withTextEditorStyleRuns<T>(
    List<NativeTextEditorStyleRun> runs,
    T Function(Pointer<_DaTextEditorStyleRunNative> pointer, int count) body,
  ) {
    if (runs.isEmpty) {
      return body(nullptr, 0);
    }
    final Pointer<_DaTextEditorStyleRunNative> pointer = _allocate(
      sizeOf<_DaTextEditorStyleRunNative>() * runs.length,
    ).cast<_DaTextEditorStyleRunNative>();
    try {
      for (var index = 0; index < runs.length; index++) {
        _writeTextEditorStyleRun((pointer + index).ref, runs[index]);
      }
      return body(pointer, runs.length);
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
  NativeValueResult<int> applicationOpenExternalUrl(
    String url, {
    required String scheme,
    required int policyFlags,
  }) {
    final _ExternalUrlOpenWithPolicyDart? configuredFunction =
        _applicationOpenExternalUrlWithPolicy;
    final _ExternalUrlOpenDart? legacyFunction = _applicationOpenExternalUrl;
    final int webPolicyFlags =
        dartAppKitExternalUrlPolicyRequireAuthority |
        dartAppKitExternalUrlPolicyRequireHost |
        dartAppKitExternalUrlPolicyForbidCredentials;
    final int mailtoPolicyFlags =
        dartAppKitExternalUrlPolicyForbidAuthority |
        dartAppKitExternalUrlPolicyForbidCredentials |
        dartAppKitExternalUrlPolicyRequirePath;
    final bool supportsLegacyPolicy =
        (scheme == 'http' || scheme == 'https') &&
            policyFlags == webPolicyFlags ||
        scheme == 'mailto' && policyFlags == mailtoPolicyFlags;
    if (configuredFunction == null &&
        (legacyFunction == null || !supportsLegacyPolicy)) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge supports only the default external URL policy',
      );
    }
    return _withUtf8(url, (Pointer<Uint8> pointer, int length) {
      final Pointer<Int32> output = _allocate(sizeOf<Int32>()).cast<Int32>();
      try {
        output.value = 0;
        return _withUtf8(scheme, (
          Pointer<Uint8> schemePointer,
          int schemeLength,
        ) {
          final int status = configuredFunction == null
              ? legacyFunction!(pointer, length, output)
              : configuredFunction(
                  pointer,
                  length,
                  schemePointer,
                  schemeLength,
                  policyFlags,
                  output,
                );
          final NativeValueResult<int> result = _valueResult<int>(
            status,
            output.value,
          );
          if (result.isSuccess && result.value != 0 && result.value != 1) {
            return const NativeValueResult<int>.failure(
              7,
              'native bridge returned an invalid external URL result',
            );
          }
          return result;
        });
      } finally {
        _free(output.cast<Void>());
      }
    });
  }

  @override
  NativeCallResult applicationPostUserNotification({
    required String identifier,
    required String title,
    required String body,
  }) {
    final _ThreeStringsStatusDart? function = _applicationPostUserNotification;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support user notifications',
      );
    }
    return _withUtf8(identifier, (
      Pointer<Uint8> identifierPointer,
      int identifierLength,
    ) {
      return _withUtf8(title, (Pointer<Uint8> titlePointer, int titleLength) {
        return _withUtf8(body, (Pointer<Uint8> bodyPointer, int bodyLength) {
          return _callResult(
            function(
              identifierPointer,
              identifierLength,
              titlePointer,
              titleLength,
              bodyPointer,
              bodyLength,
            ),
          );
        });
      });
    });
  }

  NativeValueResult<int> _notificationRequest(
    _Int64OutputDart? function,
    String legacyMessage,
  ) {
    if (function == null) {
      return NativeValueResult<int>.failure(8, legacyMessage);
    }
    final Pointer<Int64> output = _allocate(sizeOf<Int64>()).cast<Int64>();
    try {
      output.value = 0;
      return _valueResult<int>(function(output), output.value);
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeValueResult<int> applicationGetUserNotificationSettings() =>
      _notificationRequest(
        _applicationGetUserNotificationSettings,
        'legacy native bridge does not support notification settings',
      );

  @override
  NativeValueResult<int> applicationRequestUserNotificationAuthorization() =>
      _notificationRequest(
        _applicationRequestUserNotificationAuthorization,
        'legacy native bridge does not support notification authorization',
      );

  @override
  NativeValueResult<int> applicationPostTrackedUserNotification({
    required String identifier,
    required String title,
    required String body,
    required int responseToken,
  }) {
    final _TrackedUserNotificationDart? function =
        _applicationPostTrackedUserNotification;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support tracked notifications',
      );
    }
    return _withUtf8(identifier, (
      Pointer<Uint8> identifierPointer,
      int identifierLength,
    ) {
      return _withUtf8(title, (Pointer<Uint8> titlePointer, int titleLength) {
        return _withUtf8(body, (Pointer<Uint8> bodyPointer, int bodyLength) {
          final Pointer<Int64> output = _allocate(sizeOf<Int64>())
              .cast<Int64>();
          try {
            output.value = 0;
            return _valueResult<int>(
              function(
                identifierPointer,
                identifierLength,
                titlePointer,
                titleLength,
                bodyPointer,
                bodyLength,
                responseToken,
                output,
              ),
              output.value,
            );
          } finally {
            _free(output.cast<Void>());
          }
        });
      });
    });
  }

  @override
  NativeCallResult applicationRemoveUserNotification(String identifier) {
    final _StringStatusDart? function = _applicationRemoveUserNotification;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support user notification removal',
      );
    }
    return _withUtf8(
      identifier,
      (Pointer<Uint8> pointer, int length) =>
          _callResult(function(pointer, length)),
    );
  }

  @override
  NativeCallResult applicationSetDockBadgeLabel(String? label) {
    final _StringStatusDart? function = _applicationSetDockBadgeLabel;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support a Dock badge label',
      );
    }
    return _withUtf8(
      label ?? '',
      (Pointer<Uint8> pointer, int length) =>
          _callResult(function(pointer, length)),
    );
  }

  @override
  NativeValueResult<int> globalHotKeyRegister({
    required int keyCode,
    required int modifiers,
  }) {
    if (keyCode < 0 || keyCode > 0xffff || modifiers < 0) {
      return const NativeValueResult<int>.failure(
        1,
        'global hot key inputs must fit their unsigned native fields',
      );
    }
    final _GlobalHotKeyRegisterDart? function = _globalHotKeyRegister;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support global hot keys',
      );
    }
    final Pointer<Uint64> output = _allocate(sizeOf<Uint64>()).cast<Uint64>();
    try {
      output.value = 0;
      return _valueResult<int>(
        function(keyCode, modifiers, output),
        output.value,
      );
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeValueResult<int> secureEventInputCreate() {
    final _CreateHandleDart? function = _secureEventInputCreate;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support Secure Event Input',
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
  NativeCallResult secureEventInputSetDesired(int handle, bool desired) {
    final _HandleBoolStatusDart? function = _secureEventInputSetDesired;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support Secure Event Input',
      );
    }
    return _callResult(function(handle, desired ? 1 : 0));
  }

  @override
  NativeValueResult<NativeSecureEventInputSnapshot> secureEventInputGetSnapshot(
    int handle,
  ) {
    final _SecureEventInputSnapshotDart? function =
        _secureEventInputGetSnapshot;
    if (function == null) {
      return const NativeValueResult<NativeSecureEventInputSnapshot>.failure(
        8,
        'legacy native bridge does not support Secure Event Input',
      );
    }
    final Pointer<_DaSecureEventInputSnapshotNative> output = _allocate(
      sizeOf<_DaSecureEventInputSnapshotNative>(),
    ).cast<_DaSecureEventInputSnapshotNative>();
    try {
      output.ref.structSize = sizeOf<_DaSecureEventInputSnapshotNative>();
      final int status = function(handle, output);
      return _valueResult<NativeSecureEventInputSnapshot>(
        status,
        NativeSecureEventInputSnapshot(
          desired: output.ref.desired != 0,
          ownedEnabled: output.ref.ownedEnabled != 0,
          systemEnabled: output.ref.systemEnabled != 0,
          lastOsStatus: output.ref.lastOsStatus,
        ),
      );
    } finally {
      _free(output.cast<Void>());
    }
  }

  @override
  NativeValueResult<NativeScreenSnapshot> applicationResolveScreen(
    int selection,
  ) {
    final _ScreenResolveDart? function = _applicationResolveScreen;
    if (function == null) {
      return const NativeValueResult<NativeScreenSnapshot>.failure(
        8,
        'legacy native bridge does not support current screen resolution',
      );
    }
    final Pointer<_DaScreenSnapshotNative> output = _allocate(
      sizeOf<_DaScreenSnapshotNative>(),
    ).cast<_DaScreenSnapshotNative>();
    try {
      output.ref.structSize = sizeOf<_DaScreenSnapshotNative>();
      final int status = function(selection, output);
      final _DaScreenSnapshotNative value = output.ref;
      NativeRect rect(_DaRectNative native) => NativeRect(
        x: native.x,
        y: native.y,
        width: native.width,
        height: native.height,
      );
      return _valueResult<NativeScreenSnapshot>(
        status,
        NativeScreenSnapshot(
          displayId: value.displayId,
          frame: rect(value.frame),
          visibleFrame: rect(value.visibleFrame),
          backingScaleFactor: value.backingScaleFactor,
        ),
      );
    } finally {
      _free(output.cast<Void>());
    }
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
  NativeValueResult<int> menuCreate(
    String title, {
    required bool autoEnablesItems,
  }) {
    final _MenuCreateConfiguredDart? configuredFunction = _menuCreateConfigured;
    final _StringCreateDart? legacyFunction = _menuCreate;
    if (configuredFunction == null &&
        (legacyFunction == null || autoEnablesItems)) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge supports only explicit-state menus',
      );
    }
    final Pointer<Uint64> output = _allocate(sizeOf<Uint64>()).cast<Uint64>();
    Pointer<_DaMenuConfigurationNative>? configurationPointer;
    try {
      output.value = 0;
      return _withUtf8(title, (Pointer<Uint8> pointer, int length) {
        if (configuredFunction == null) {
          return _valueResult<int>(
            legacyFunction!(pointer, length, output),
            output.value,
          );
        }
        final Pointer<_DaMenuConfigurationNative> configPointer = _allocate(
          sizeOf<_DaMenuConfigurationNative>(),
        ).cast<_DaMenuConfigurationNative>();
        configurationPointer = configPointer;
        configPointer.ref
          ..structSize = sizeOf<_DaMenuConfigurationNative>()
          ..autoEnablesItems = autoEnablesItems ? 1 : 0
          ..reserved = 0;
        return _valueResult<int>(
          configuredFunction(pointer, length, configPointer, output),
          output.value,
        );
      });
    } finally {
      final Pointer<_DaMenuConfigurationNative>? pointer = configurationPointer;
      if (pointer != null) {
        _free(pointer.cast<Void>());
      }
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
  NativeCallResult menuItemSetChecked(int handle, bool checked) {
    final _HandleBoolStatusDart? function = _menuItemSetChecked;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support checked menu items',
      );
    }
    return _callResult(function(handle, checked ? 1 : 0));
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
  NativeValueResult<NativeRect> windowGetContentLayoutRect(int handle) {
    final _HandleRectOutputDart? function = _windowGetContentLayoutRect;
    if (function == null) {
      return const NativeValueResult<NativeRect>.failure(
        8,
        'legacy native bridge does not support window content layout queries',
      );
    }
    final Pointer<_DaRectNative> rectPointer = _malloc(sizeOf<_DaRectNative>())
        .cast<_DaRectNative>();
    try {
      final int status = function(handle, rectPointer);
      final _DaRectNative rect = rectPointer.ref;
      return _valueResult<NativeRect>(
        status,
        NativeRect(
          x: rect.x,
          y: rect.y,
          width: rect.width,
          height: rect.height,
        ),
      );
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
  NativeCallResult windowSetPresentationConfiguration({
    required int handle,
    required int level,
    required int collectionBehaviorMask,
  }) {
    final _WindowSetPresentationConfigurationDart? function =
        _windowSetPresentationConfiguration;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support window presentation policy',
      );
    }
    final Pointer<_DaWindowPresentationConfigurationNative> configuration =
        _allocate(sizeOf<_DaWindowPresentationConfigurationNative>())
            .cast<_DaWindowPresentationConfigurationNative>();
    try {
      configuration.ref
        ..structSize = sizeOf<_DaWindowPresentationConfigurationNative>()
        ..level = level
        ..reserved = 0
        ..collectionBehaviorMask = collectionBehaviorMask;
      return _callResult(function(handle, configuration));
    } finally {
      _free(configuration.cast<Void>());
    }
  }

  @override
  NativeCallResult windowPresent({
    required int handle,
    required NativeRect startFrame,
    required NativeRect targetFrame,
    required double durationSeconds,
    required bool makeKey,
  }) {
    final _WindowPresentDart? function = _windowPresent;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support animated window presentation',
      );
    }
    final Pointer<_DaRectNative> start = _allocate(sizeOf<_DaRectNative>())
        .cast<_DaRectNative>();
    final Pointer<_DaRectNative> target = _allocate(sizeOf<_DaRectNative>())
        .cast<_DaRectNative>();
    try {
      start.ref
        ..x = startFrame.x
        ..y = startFrame.y
        ..width = startFrame.width
        ..height = startFrame.height;
      target.ref
        ..x = targetFrame.x
        ..y = targetFrame.y
        ..width = targetFrame.width
        ..height = targetFrame.height;
      return _callResult(
        function(
          handle,
          start.ref,
          target.ref,
          durationSeconds,
          makeKey ? 1 : 0,
        ),
      );
    } finally {
      _free(target.cast<Void>());
      _free(start.cast<Void>());
    }
  }

  @override
  NativeCallResult windowHide({
    required int handle,
    required NativeRect targetFrame,
    required double durationSeconds,
  }) {
    final _WindowHideDart? function = _windowHide;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support animated window presentation',
      );
    }
    final Pointer<_DaRectNative> target = _allocate(sizeOf<_DaRectNative>())
        .cast<_DaRectNative>();
    try {
      target.ref
        ..x = targetFrame.x
        ..y = targetFrame.y
        ..width = targetFrame.width
        ..height = targetFrame.height;
      return _callResult(function(handle, target.ref, durationSeconds));
    } finally {
      _free(target.cast<Void>());
    }
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
    final _WindowTabAccessoryDart? function = _windowSetTabAccessory;
    if (function == null) {
      final _HandleBoolFourDoublesDart? legacy = _windowSetTabColor;
      if (legacy != null &&
          (!hasAccessory ||
              shape == dartAppKitWindowTabAccessoryShapeEllipse &&
                  width == 8 &&
                  height == 8)) {
        return _callResult(
          legacy(handle, hasAccessory ? 1 : 0, red, green, blue, alpha),
        );
      }
      return const NativeCallResult.failure(
        8,
        'legacy native bridge supports only the default tab accessory',
      );
    }
    final Pointer<_DaWindowTabAccessoryConfigurationNative> configuration =
        _allocate(sizeOf<_DaWindowTabAccessoryConfigurationNative>())
            .cast<_DaWindowTabAccessoryConfigurationNative>();
    try {
      configuration.ref
        ..structSize = sizeOf<_DaWindowTabAccessoryConfigurationNative>()
        ..shape = shape
        ..reserved = 0
        ..width = width
        ..height = height
        ..red = red
        ..green = green
        ..blue = blue
        ..alpha = alpha;
      return _callResult(
        function(
          handle,
          hasAccessory ? 1 : 0,
          hasAccessory ? configuration : nullptr,
        ),
      );
    } finally {
      _free(configuration.cast<Void>());
    }
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
  NativeValueResult<int> viewCreate(NativeViewConfiguration configuration) {
    final _ViewCreateConfiguredDart? configuredFunction = _viewCreateConfigured;
    final _CreateHandleDart? legacyFunction = _viewCreate;
    if (configuredFunction == null &&
        (legacyFunction == null || !configuration.isCompatibilityDefault)) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge supports only the default generic view',
      );
    }
    final Pointer<Uint64> handlePointer = _allocate(sizeOf<Uint64>())
        .cast<Uint64>();
    Pointer<_DaViewConfigurationNative>? configurationPointer;
    try {
      handlePointer.value = 0;
      final int status;
      if (configuredFunction == null) {
        status = legacyFunction!(handlePointer);
      } else {
        configurationPointer = _allocate(sizeOf<_DaViewConfigurationNative>())
            .cast<_DaViewConfigurationNative>();
        _writeViewConfiguration(configurationPointer.ref, configuration);
        status = configuredFunction(configurationPointer, handlePointer);
      }
      return _valueResult<int>(status, handlePointer.value);
    } finally {
      if (configurationPointer != null) {
        _free(configurationPointer.cast<Void>());
      }
      _free(handlePointer.cast<Void>());
    }
  }

  @override
  NativeCallResult viewSetSecureInputIndicator(int handle, int state) {
    final _HandleBoolStatusDart? function = _viewSetSecureInputIndicator;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support secure-input indication',
      );
    }
    return _callResult(function(handle, state));
  }

  @override
  NativeCallResult viewSetContextMenu(int viewHandle, int menuHandle) {
    final _TwoHandlesDart? function = _viewSetContextMenu;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support view context menus',
      );
    }
    return _callResult(function(viewHandle, menuHandle));
  }

  @override
  NativeCallResult viewSetQuickLookRequestEnabled(int handle, bool enabled) {
    final _HandleBoolStatusDart? function = _viewSetQuickLookRequestEnabled;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support Quick Look requests',
      );
    }
    return _callResult(function(handle, enabled ? 1 : 0));
  }

  @override
  NativeCallResult viewShowDefinition(
    int handle,
    NativeDefinitionPresentation presentation,
  ) {
    final _ViewShowDefinitionDart? function = _viewShowDefinition;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support definitions',
      );
    }
    final Pointer<_DaDefinitionPresentationConfigurationNative> configuration =
        _allocate(sizeOf<_DaDefinitionPresentationConfigurationNative>())
            .cast<_DaDefinitionPresentationConfigurationNative>();
    try {
      _writeDefinitionPresentation(configuration.ref, presentation);
      return _withUtf8(
        presentation.text,
        (Pointer<Uint8> text, int textLength) => _withUtf8(
          presentation.fontFamily ?? '',
          (Pointer<Uint8> fontFamily, int fontFamilyLength) => _callResult(
            function(
              handle,
              text,
              textLength,
              configuration,
              fontFamily,
              fontFamilyLength,
            ),
          ),
        ),
      );
    } finally {
      _free(configuration.cast<Void>());
    }
  }

  @override
  NativeCallResult viewSetServicesTextRequestor(
    int handle,
    NativeServicesTextRequestorConfiguration? configuration,
  ) {
    final _ViewSetServicesTextRequestorDart? function =
        _viewSetServicesTextRequestor;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support Services requestors',
      );
    }
    if (configuration == null) {
      return _callResult(function(handle, nullptr, 0, nullptr));
    }
    final Pointer<_DaServicesTextRequestorConfigurationNative>
    nativeConfiguration = _allocate(
      sizeOf<_DaServicesTextRequestorConfigurationNative>(),
    ).cast<_DaServicesTextRequestorConfigurationNative>();
    try {
      _writeServicesTextRequestorConfiguration(
        nativeConfiguration.ref,
        configuration,
      );
      if (configuration.selectionText == null) {
        return _callResult(function(handle, nullptr, 0, nativeConfiguration));
      }
      return _withUtf8(
        configuration.selectionText!,
        (Pointer<Uint8> selection, int selectionLength) => _callResult(
          function(handle, selection, selectionLength, nativeConfiguration),
        ),
      );
    } finally {
      _free(nativeConfiguration.cast<Void>());
    }
  }

  @override
  NativeCallResult viewSetDropDestination(
    int handle,
    NativeDropDestinationConfiguration? configuration,
  ) {
    final _ViewSetDropDestinationDart? function = _viewSetDropDestination;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support drop destinations',
      );
    }
    if (configuration == null) {
      return _callResult(function(handle, nullptr));
    }
    final Pointer<_DaDropDestinationConfigurationNative> nativeConfiguration =
        _allocate(sizeOf<_DaDropDestinationConfigurationNative>())
            .cast<_DaDropDestinationConfigurationNative>();
    try {
      _writeDropDestinationConfiguration(
        nativeConfiguration.ref,
        configuration,
      );
      return _callResult(function(handle, nativeConfiguration));
    } finally {
      _free(nativeConfiguration.cast<Void>());
    }
  }

  @override
  NativeCallResult applicationSetFolderServicesProvider(
    NativeFolderServicesProviderConfiguration? configuration,
  ) {
    final _ApplicationSetFolderServicesProviderDart? function =
        _applicationSetFolderServicesProvider;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support folder Services providers',
      );
    }
    if (configuration == null) {
      return _callResult(function(nullptr));
    }
    final Pointer<_DaFolderServicesProviderConfigurationNative>
    nativeConfiguration = _allocate(
      sizeOf<_DaFolderServicesProviderConfigurationNative>(),
    ).cast<_DaFolderServicesProviderConfigurationNative>();
    try {
      _writeFolderServicesProviderConfiguration(
        nativeConfiguration.ref,
        configuration,
      );
      return _callResult(function(nativeConfiguration));
    } finally {
      _free(nativeConfiguration.cast<Void>());
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
  NativeValueResult<double> splitViewGetFraction(int handle) {
    final _HandleDoubleOutputDart? function = _splitViewGetFraction;
    if (function == null) {
      return const NativeValueResult<double>.failure(
        8,
        'legacy native bridge does not support split position observation',
      );
    }
    final Pointer<Double> output = _allocate(sizeOf<Double>()).cast<Double>();
    try {
      output.value = 0;
      final int status = function(handle, output);
      return _valueResult<double>(status, output.value);
    } finally {
      _free(output.cast<Void>());
    }
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
  NativeValueResult<int> textViewCreate(
    NativeTextViewConfiguration configuration,
  ) {
    final _TextViewCreateConfiguredDart? configuredFunction =
        _textViewCreateConfigured;
    if (configuredFunction == null && !configuration.isCompatibilityDefault) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge supports only the default text view',
      );
    }
    final Pointer<Uint64> handlePointer = _allocate(sizeOf<Uint64>())
        .cast<Uint64>();
    Pointer<_DaTextViewConfigurationNative>? configurationPointer;
    try {
      handlePointer.value = 0;
      if (configuredFunction == null) {
        return _valueResult<int>(
          _textViewCreate(handlePointer),
          handlePointer.value,
        );
      }
      configurationPointer = _allocate(sizeOf<_DaTextViewConfigurationNative>())
          .cast<_DaTextViewConfigurationNative>();
      _writeTextViewConfiguration(configurationPointer.ref, configuration);
      return _withUtf8(configuration.fontFamily ?? '', (
        Pointer<Uint8> familyPointer,
        int familyLength,
      ) {
        return _valueResult<int>(
          configuredFunction(
            configurationPointer!,
            familyPointer,
            familyLength,
            handlePointer,
          ),
          handlePointer.value,
        );
      });
    } finally {
      if (configurationPointer != null) {
        _free(configurationPointer.cast<Void>());
      }
      _free(handlePointer.cast<Void>());
    }
  }

  @override
  NativeCallResult textViewSetText(int handle, String text) =>
      _withUtf8(text, (Pointer<Uint8> pointer, int length) {
        return _callResult(_textViewSetText(handle, pointer, length));
      });

  @override
  NativeValueResult<int> textEditorCreate(
    NativeTextEditorConfiguration configuration,
  ) {
    final _TextEditorCreateConfiguredDart? function =
        _textEditorCreateConfigured;
    if (function == null) {
      return const NativeValueResult<int>.failure(
        8,
        'legacy native bridge does not support text editors',
      );
    }
    final Pointer<Uint64> handlePointer = _allocate(sizeOf<Uint64>())
        .cast<Uint64>();
    final Pointer<_DaTextEditorConfigurationNative> configurationPointer =
        _allocate(sizeOf<_DaTextEditorConfigurationNative>())
            .cast<_DaTextEditorConfigurationNative>();
    try {
      handlePointer.value = 0;
      final _DaTextEditorConfigurationNative native = configurationPointer.ref;
      native
        ..structSize = sizeOf<_DaTextEditorConfigurationNative>()
        ..initiallyEditable = configuration.initiallyEditable ? 1 : 0
        ..reserved = 0;
      _writeTextViewConfiguration(
        native.presentation,
        configuration.presentation,
      );
      return _withUtf8(configuration.presentation.fontFamily ?? '', (
        Pointer<Uint8> familyPointer,
        int familyLength,
      ) {
        return _valueResult<int>(
          function(
            configurationPointer,
            familyPointer,
            familyLength,
            handlePointer,
          ),
          handlePointer.value,
        );
      });
    } finally {
      _free(configurationPointer.cast<Void>());
      _free(handlePointer.cast<Void>());
    }
  }

  @override
  NativeCallResult textEditorSetDocument(
    int handle,
    NativeTextEditorDocument document,
  ) {
    final _TextEditorSetDocumentDart? function = _textEditorSetDocument;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support text editors',
      );
    }
    return _withUtf8(document.text, (Pointer<Uint8> text, int textLength) {
      return _withTextEditorStyleRuns(document.styleRuns, (
        Pointer<_DaTextEditorStyleRunNative> runs,
        int runCount,
      ) {
        return _callResult(
          function(
            handle,
            text,
            textLength,
            runs,
            runCount,
            document.selectionStart,
            document.selectionLength,
          ),
        );
      });
    });
  }

  @override
  NativeCallResult textEditorSetStyleRuns(
    int handle,
    List<NativeTextEditorStyleRun> styleRuns,
  ) {
    final _TextEditorSetStyleRunsDart? function = _textEditorSetStyleRuns;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support text editors',
      );
    }
    return _withTextEditorStyleRuns(
      styleRuns,
      (Pointer<_DaTextEditorStyleRunNative> runs, int count) =>
          _callResult(function(handle, runs, count)),
    );
  }

  @override
  NativeCallResult textEditorSetLineHighlight(
    int handle,
    NativeTextEditorLineHighlight? highlight,
  ) {
    final _TextEditorSetLineHighlightDart? function =
        _textEditorSetLineHighlight;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support text editor line highlights',
      );
    }
    if (highlight == null) {
      return _callResult(function(handle, 0, nullptr));
    }
    final Pointer<_DaTextViewColorConfigurationNative> color = _allocate(
      sizeOf<_DaTextViewColorConfigurationNative>(),
    ).cast<_DaTextViewColorConfigurationNative>();
    try {
      _writeTextViewColor(
        color.ref,
        kind: highlight.colorKind,
        red: highlight.red,
        green: highlight.green,
        blue: highlight.blue,
        alpha: highlight.alpha,
      );
      return _callResult(function(handle, highlight.location, color));
    } finally {
      _free(color.cast<Void>());
    }
  }

  @override
  NativeCallResult textEditorSetEditable(int handle, bool editable) {
    final _HandleBoolStatusDart? function = _textEditorSetEditable;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support text editors',
      );
    }
    return _callResult(function(handle, editable ? 1 : 0));
  }

  @override
  NativeCallResult textEditorSetSelection(
    int handle, {
    required int start,
    required int length,
  }) {
    final _TextEditorSetSelectionDart? function = _textEditorSetSelection;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support text editors',
      );
    }
    return _callResult(function(handle, start, length));
  }

  @override
  NativeCallResult textEditorScrollSelectionToVisible(int handle) {
    final _HandleStatusDart? function = _textEditorScrollSelectionToVisible;
    if (function == null) {
      return const NativeCallResult.failure(
        8,
        'legacy native bridge does not support text editor selection reveal',
      );
    }
    return _callResult(function(handle));
  }

  @override
  NativeValueResult<NativeTextEditorSnapshot> textEditorSnapshot(int handle) {
    final _TextEditorGetSnapshotDart? function = _textEditorGetSnapshot;
    if (function == null) {
      return const NativeValueResult<NativeTextEditorSnapshot>.failure(
        8,
        'legacy native bridge does not support text editors',
      );
    }
    final Pointer<_DaTextEditorSnapshotNative> output = _allocate(
      sizeOf<_DaTextEditorSnapshotNative>(),
    ).cast<_DaTextEditorSnapshotNative>();
    try {
      final int status = function(handle, output);
      if (status != 0) {
        return NativeValueResult<NativeTextEditorSnapshot>.failure(
          status,
          _lastErrorMessage(),
        );
      }
      final _DaTextEditorSnapshotNative native = output.ref;
      if ((native.text.address == 0 && native.textLength != 0) ||
          native.textLength > dartAppKitTextEditorMaximumTextUtf8Bytes ||
          (native.isEditable != 0 && native.isEditable != 1) ||
          (native.hasMarkedText != 0 && native.hasMarkedText != 1)) {
        return const NativeValueResult<NativeTextEditorSnapshot>.failure(
          7,
          'native bridge returned an invalid text editor snapshot',
        );
      }
      final String text;
      try {
        text = native.textLength == 0
            ? ''
            : utf8.decode(
                native.text.asTypedList(native.textLength),
                allowMalformed: false,
              );
      } on FormatException {
        return const NativeValueResult<NativeTextEditorSnapshot>.failure(
          7,
          'native bridge returned non-UTF-8 text editor contents',
        );
      }
      if (native.selectionLocation > text.length ||
          native.selectionLength > text.length - native.selectionLocation) {
        return const NativeValueResult<NativeTextEditorSnapshot>.failure(
          7,
          'native bridge returned an out-of-bounds text editor selection',
        );
      }
      return NativeValueResult<NativeTextEditorSnapshot>.success(
        NativeTextEditorSnapshot(
          text: text,
          selectionStart: native.selectionLocation,
          selectionLength: native.selectionLength,
          isEditable: native.isEditable == 1,
          hasMarkedText: native.hasMarkedText == 1,
        ),
      );
    } finally {
      _free(output.cast<Void>());
    }
  }

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
