/// A small Dart API for driving AppKit from the embedded root UI isolate.
library;

export 'src/api.dart'
    show
        AppKitApplication,
        AppKitEvent,
        AppKitInitializationException,
        AppKitKeyEvent,
        AppKitKeyEventKind,
        AppKitMouseEvent,
        AppKitMouseEventKind,
        AppKitNativeException,
        ModifierKeys,
        Rect,
        TextView,
        View,
        Window,
        WindowClosedEvent,
        WindowEvent,
        WindowResizedEvent;
export 'src/native/native_bindings.dart'
    show
        dartAppKitCurrentEventProtocolVersion,
        dartAppKitMinimumEventProtocolVersion;
