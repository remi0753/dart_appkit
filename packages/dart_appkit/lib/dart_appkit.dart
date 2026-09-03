/// A small Dart API for driving AppKit from the embedded root UI isolate.
library;

export 'src/api.dart'
    show
        AppKitApplication,
        AppKitEvent,
        ApplicationActiveChangedEvent,
        ApplicationEvent,
        ApplicationReopenRequestedEvent,
        ApplicationTerminateRequestedEvent,
        AppKitInitializationException,
        AppKitKeyEvent,
        AppKitKeyEventKind,
        AppKitMouseEvent,
        AppKitMouseEventKind,
        AppKitNativeException,
        AppKitScreen,
        ModifierKeys,
        MenuItemInvokedEvent,
        Pasteboard,
        PasteboardTextSnapshot,
        Rect,
        TextView,
        View,
        Window,
        WindowBackingScaleChangedEvent,
        WindowClosedEvent,
        WindowCloseRequestedEvent,
        WindowEvent,
        WindowFocusChangedEvent,
        WindowOcclusionChangedEvent,
        WindowResizedEvent,
        WindowScreenChangedEvent,
        WindowVisibilityChangedEvent;
export 'src/native/native_bindings.dart'
    show
        dartAppKitCurrentEventProtocolVersion,
        dartAppKitMinimumEventProtocolVersion;
