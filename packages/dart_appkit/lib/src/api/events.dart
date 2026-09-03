part of '../api.dart';

sealed class AppKitEvent {
  const AppKitEvent({
    required this.windowHandle,
    required this.monotonicMicros,
    this.protocolVersion = 1,
    this.sourceGeneration = 0,
    int? monotonicNanoseconds,
    this.operationId = 0,
  }) : monotonicNanoseconds = monotonicNanoseconds ?? monotonicMicros * 1000;

  final int windowHandle;
  final int monotonicMicros;
  final int protocolVersion;
  final int sourceGeneration;
  final int monotonicNanoseconds;
  final int operationId;

  int get sourceHandle => windowHandle;
}

sealed class ApplicationEvent extends AppKitEvent {
  const ApplicationEvent({
    required int monotonicMicros,
    int protocolVersion = 4,
    int? monotonicNanoseconds,
    int operationId = 0,
  }) : super(
         windowHandle: 0,
         monotonicMicros: monotonicMicros,
         protocolVersion: protocolVersion,
         sourceGeneration: 0,
         monotonicNanoseconds: monotonicNanoseconds,
         operationId: operationId,
       );
}

final class ApplicationActiveChangedEvent extends ApplicationEvent {
  const ApplicationActiveChangedEvent({
    required super.monotonicMicros,
    super.protocolVersion,
    super.monotonicNanoseconds,
    super.operationId,
    required this.isActive,
  });

  final bool isActive;
}

final class ApplicationReopenRequestedEvent extends ApplicationEvent {
  const ApplicationReopenRequestedEvent({
    required super.monotonicMicros,
    super.protocolVersion,
    super.monotonicNanoseconds,
    super.operationId,
    required this.hasVisibleWindows,
  });

  final bool hasVisibleWindows;
}

final class ApplicationTerminateRequestedEvent extends ApplicationEvent {
  const ApplicationTerminateRequestedEvent({
    required super.monotonicMicros,
    super.protocolVersion,
    super.monotonicNanoseconds,
    required super.operationId,
  });
}

sealed class WindowEvent extends AppKitEvent {
  const WindowEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
  });
}

final class WindowClosedEvent extends WindowEvent {
  const WindowClosedEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
  });
}

final class WindowCloseRequestedEvent extends WindowEvent {
  const WindowCloseRequestedEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    required super.operationId,
  });
}

final class WindowResizedEvent extends WindowEvent {
  const WindowResizedEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
    required this.width,
    required this.height,
  });

  final double width;
  final double height;
}

final class AppKitScreen {
  const AppKitScreen({
    required this.displayId,
    required this.frame,
    required this.visibleFrame,
  });

  final int displayId;
  final Rect frame;
  final Rect visibleFrame;

  @override
  bool operator ==(Object other) =>
      other is AppKitScreen &&
      other.displayId == displayId &&
      other.frame == frame &&
      other.visibleFrame == visibleFrame;

  @override
  int get hashCode => Object.hash(displayId, frame, visibleFrame);
}

final class WindowFocusChangedEvent extends WindowEvent {
  const WindowFocusChangedEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
    required this.isFocused,
  });

  final bool isFocused;
}

final class WindowVisibilityChangedEvent extends WindowEvent {
  const WindowVisibilityChangedEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
    required this.isVisible,
  });

  final bool isVisible;
}

final class WindowOcclusionChangedEvent extends WindowEvent {
  const WindowOcclusionChangedEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
    required this.isOccluded,
  });

  final bool isOccluded;
}

final class WindowBackingScaleChangedEvent extends WindowEvent {
  const WindowBackingScaleChangedEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
    required this.backingScaleFactor,
  });

  final double backingScaleFactor;
}

final class WindowScreenChangedEvent extends WindowEvent {
  const WindowScreenChangedEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
    required this.screen,
  });

  final AppKitScreen? screen;
}

enum AppKitMouseEventKind { down, up, moved, dragged }

final class AppKitMouseEvent extends WindowEvent {
  const AppKitMouseEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
    required this.kind,
    required this.x,
    required this.y,
    required this.button,
    required this.modifiers,
    required this.clickCount,
  });

  final AppKitMouseEventKind kind;
  final double x;
  final double y;
  final int button;
  final ModifierKeys modifiers;
  final int clickCount;
}

enum AppKitKeyEventKind { down, up }

final class AppKitKeyEvent extends WindowEvent {
  const AppKitKeyEvent({
    required super.windowHandle,
    required super.monotonicMicros,
    super.protocolVersion,
    super.sourceGeneration,
    super.monotonicNanoseconds,
    super.operationId,
    required this.kind,
    required this.keyCode,
    required this.modifiers,
    required this.isRepeat,
    required this.characters,
    required this.charactersIgnoringModifiers,
  });

  final AppKitKeyEventKind kind;
  final int keyCode;
  final ModifierKeys modifiers;
  final bool isRepeat;
  final String characters;
  final String charactersIgnoringModifiers;
}

final class MenuItemInvokedEvent extends AppKitEvent {
  const MenuItemInvokedEvent({
    required int menuItemHandle,
    required int monotonicMicros,
    int protocolVersion = 4,
    int sourceGeneration = 0,
    int? monotonicNanoseconds,
    int operationId = 0,
  }) : super(
         windowHandle: menuItemHandle,
         monotonicMicros: monotonicMicros,
         protocolVersion: protocolVersion,
         sourceGeneration: sourceGeneration,
         monotonicNanoseconds: monotonicNanoseconds,
         operationId: operationId,
       );

  int get menuItemHandle => sourceHandle;
}

final class ModifierKeys {
  const ModifierKeys(this.bits);

  static const int capsLockBit = 1 << 0;
  static const int shiftBit = 1 << 1;
  static const int controlBit = 1 << 2;
  static const int optionBit = 1 << 3;
  static const int commandBit = 1 << 4;
  static const int numericPadBit = 1 << 5;
  static const int functionBit = 1 << 6;
  static const int supportedBits = (1 << 7) - 1;

  final int bits;

  bool get capsLock => (bits & capsLockBit) != 0;
  bool get shift => (bits & shiftBit) != 0;
  bool get control => (bits & controlBit) != 0;
  bool get option => (bits & optionBit) != 0;
  bool get command => (bits & commandBit) != 0;
  bool get numericPad => (bits & numericPadBit) != 0;
  bool get function => (bits & functionBit) != 0;

  @override
  bool operator ==(Object other) => other is ModifierKeys && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;
}

final class _EventCodec {
  static const int _windowClosed = 1;
  static const int _windowResized = 2;
  static const int _windowFocusChanged = 3;
  static const int _windowVisibilityChanged = 4;
  static const int _windowOcclusionChanged = 5;
  static const int _windowBackingScaleChanged = 6;
  static const int _windowScreenChanged = 7;
  static const int _windowCloseRequested = 8;
  static const int _mouseDown = 10;
  static const int _mouseUp = 11;
  static const int _mouseMoved = 12;
  static const int _mouseDragged = 13;
  static const int _keyDown = 20;
  static const int _keyUp = 21;
  static const int _applicationActiveChanged = 30;
  static const int _applicationReopenRequested = 31;
  static const int _applicationTerminateRequested = 32;
  static const int _menuItemInvoked = 40;

  static AppKitEvent decode(Object? message) {
    if (message is! List<Object?>) {
      throw const FormatException('native event must be a list');
    }
    if (message.isEmpty) {
      throw const FormatException('native event envelope is empty');
    }
    final int version = _integer(message, 0, 'protocolVersion');
    if (version < dartAppKitMinimumEventProtocolVersion ||
        version > dartAppKitCurrentEventProtocolVersion) {
      throw FormatException(
        'unsupported native event protocol version $version',
      );
    }
    final int payloadOffset = version == 1 ? 4 : 6;
    if (message.length < payloadOffset) {
      throw FormatException(
        'native event version $version envelope is too short',
      );
    }
    final int type = _integer(message, 1, 'eventType');
    final int handle = _integer(message, 2, 'sourceHandle');
    final bool applicationScoped = _isApplicationScoped(type);
    final int encodedHandleGeneration = handle >> 32;
    final int sourceGeneration = version == 1
        ? encodedHandleGeneration
        : _integer(message, 3, 'sourceGeneration');
    final int monotonicNanoseconds;
    final int monotonicMicros;
    final int operationId;
    if (version == 1) {
      monotonicMicros = _integer(message, 3, 'monotonicMicros');
      monotonicNanoseconds = monotonicMicros * 1000;
      operationId = 0;
    } else {
      monotonicNanoseconds = _integer(message, 4, 'monotonicNanoseconds');
      monotonicMicros = monotonicNanoseconds ~/ 1000;
      operationId = _integer(message, 5, 'operationId');
    }
    if (applicationScoped) {
      if (version < 4 || handle != 0 || sourceGeneration != 0) {
        throw const FormatException(
          'application event must use the zero source identity in protocol 4',
        );
      }
    } else if (handle <= 0 ||
        (version > 1 &&
            (sourceGeneration <= 0 ||
                sourceGeneration != encodedHandleGeneration))) {
      throw const FormatException(
        'native event has an invalid generation-checked source handle',
      );
    }
    if (monotonicNanoseconds < 0) {
      throw const FormatException('native event has a negative timestamp');
    }
    if (operationId < 0) {
      throw const FormatException('native event has a negative operation ID');
    }
    if (_requiresReply(type)) {
      if (operationId <= 0) {
        throw const FormatException(
          'request event must have a positive operation ID',
        );
      }
    } else if (operationId != 0) {
      throw const FormatException(
        'notification event must have operation ID zero',
      );
    }

    switch (type) {
      case _windowClosed:
        _expectLength(message, payloadOffset, 'window closed');
        return WindowClosedEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
        );
      case _windowResized:
        _expectLength(message, payloadOffset + 2, 'window resized');
        return WindowResizedEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          width: _number(message, payloadOffset, 'width'),
          height: _number(message, payloadOffset + 1, 'height'),
        );
      case _windowCloseRequested:
        _requireVersionFour(version, 'window close requested');
        _expectLength(message, payloadOffset, 'window close requested');
        return WindowCloseRequestedEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
        );
      case _windowFocusChanged:
        _requireVersionThree(version, 'window focus changed');
        _expectLength(message, payloadOffset + 1, 'window focus changed');
        return WindowFocusChangedEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          isFocused: _boolean(message, payloadOffset, 'isFocused'),
        );
      case _windowVisibilityChanged:
        _requireVersionThree(version, 'window visibility changed');
        _expectLength(message, payloadOffset + 1, 'window visibility changed');
        return WindowVisibilityChangedEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          isVisible: _boolean(message, payloadOffset, 'isVisible'),
        );
      case _windowOcclusionChanged:
        _requireVersionThree(version, 'window occlusion changed');
        _expectLength(message, payloadOffset + 1, 'window occlusion changed');
        return WindowOcclusionChangedEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          isOccluded: _boolean(message, payloadOffset, 'isOccluded'),
        );
      case _windowBackingScaleChanged:
        _requireVersionThree(version, 'window backing scale changed');
        _expectLength(
          message,
          payloadOffset + 1,
          'window backing scale changed',
        );
        final double backingScaleFactor = _finiteNumber(
          message,
          payloadOffset,
          'backingScaleFactor',
        );
        if (backingScaleFactor <= 0.0) {
          throw const FormatException('backingScaleFactor must be positive');
        }
        return WindowBackingScaleChangedEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          backingScaleFactor: backingScaleFactor,
        );
      case _windowScreenChanged:
        _requireVersionThree(version, 'window screen changed');
        _expectLength(message, payloadOffset + 10, 'window screen changed');
        return WindowScreenChangedEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          screen: _screen(message, payloadOffset),
        );
      case _mouseDown:
      case _mouseUp:
      case _mouseMoved:
      case _mouseDragged:
        _expectLength(message, payloadOffset + 5, 'mouse');
        return AppKitMouseEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          kind: switch (type) {
            _mouseDown => AppKitMouseEventKind.down,
            _mouseUp => AppKitMouseEventKind.up,
            _mouseMoved => AppKitMouseEventKind.moved,
            _ => AppKitMouseEventKind.dragged,
          },
          x: _number(message, payloadOffset, 'x'),
          y: _number(message, payloadOffset + 1, 'y'),
          button: _integer(message, payloadOffset + 2, 'button'),
          modifiers: ModifierKeys(
            _integer(message, payloadOffset + 3, 'modifiers'),
          ),
          clickCount: _integer(message, payloadOffset + 4, 'clickCount'),
        );
      case _keyDown:
      case _keyUp:
        _expectLength(message, payloadOffset + 5, 'key');
        return AppKitKeyEvent(
          windowHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          kind: type == _keyDown
              ? AppKitKeyEventKind.down
              : AppKitKeyEventKind.up,
          keyCode: _integer(message, payloadOffset, 'keyCode'),
          modifiers: ModifierKeys(
            _integer(message, payloadOffset + 1, 'modifiers'),
          ),
          isRepeat: _boolean(message, payloadOffset + 2, 'isRepeat'),
          characters: _string(message, payloadOffset + 3, 'characters'),
          charactersIgnoringModifiers: _string(
            message,
            payloadOffset + 4,
            'charactersIgnoringModifiers',
          ),
        );
      case _applicationActiveChanged:
        _requireVersionFour(version, 'application active changed');
        _expectLength(message, payloadOffset + 1, 'application active changed');
        return ApplicationActiveChangedEvent(
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          isActive: _boolean(message, payloadOffset, 'isActive'),
        );
      case _applicationReopenRequested:
        _requireVersionFour(version, 'application reopen requested');
        _expectLength(
          message,
          payloadOffset + 1,
          'application reopen requested',
        );
        return ApplicationReopenRequestedEvent(
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
          hasVisibleWindows: _boolean(
            message,
            payloadOffset,
            'hasVisibleWindows',
          ),
        );
      case _applicationTerminateRequested:
        _requireVersionFour(version, 'application terminate requested');
        _expectLength(
          message,
          payloadOffset,
          'application terminate requested',
        );
        return ApplicationTerminateRequestedEvent(
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
        );
      case _menuItemInvoked:
        _requireVersionFour(version, 'menu item invoked');
        _expectLength(message, payloadOffset, 'menu item invoked');
        return MenuItemInvokedEvent(
          menuItemHandle: handle,
          monotonicMicros: monotonicMicros,
          protocolVersion: version,
          sourceGeneration: sourceGeneration,
          monotonicNanoseconds: monotonicNanoseconds,
          operationId: operationId,
        );
      default:
        throw FormatException('unknown native event type $type');
    }
  }

  static void _expectLength(
    List<Object?> values,
    int expected,
    String eventName,
  ) {
    if (values.length != expected) {
      throw FormatException(
        '$eventName event has ${values.length} fields; expected $expected',
      );
    }
  }

  static void _requireVersionThree(int version, String eventName) {
    if (version < 3) {
      throw FormatException('$eventName requires native event protocol 3');
    }
  }

  static void _requireVersionFour(int version, String eventName) {
    if (version < 4) {
      throw FormatException('$eventName requires native event protocol 4');
    }
  }

  static bool _isApplicationScoped(int type) =>
      type == _applicationActiveChanged ||
      type == _applicationReopenRequested ||
      type == _applicationTerminateRequested;

  static bool _requiresReply(int type) =>
      type == _windowCloseRequested || type == _applicationTerminateRequested;

  static AppKitScreen? _screen(List<Object?> values, int offset) {
    final bool hasScreen = _boolean(values, offset, 'hasScreen');
    final int displayId = _integer(values, offset + 1, 'displayId');
    final Rect frame = Rect.fromLTWH(
      _finiteNumber(values, offset + 2, 'screenLeft'),
      _finiteNumber(values, offset + 3, 'screenTop'),
      _finiteNumber(values, offset + 4, 'screenWidth'),
      _finiteNumber(values, offset + 5, 'screenHeight'),
    );
    final Rect visibleFrame = Rect.fromLTWH(
      _finiteNumber(values, offset + 6, 'visibleScreenLeft'),
      _finiteNumber(values, offset + 7, 'visibleScreenTop'),
      _finiteNumber(values, offset + 8, 'visibleScreenWidth'),
      _finiteNumber(values, offset + 9, 'visibleScreenHeight'),
    );
    if (!hasScreen) {
      if (displayId != 0 ||
          frame != const Rect.fromLTWH(0, 0, 0, 0) ||
          visibleFrame != const Rect.fromLTWH(0, 0, 0, 0)) {
        throw const FormatException(
          'absent screen must have zero identifier and rectangles',
        );
      }
      return null;
    }
    if (displayId <= 0 ||
        frame.width <= 0.0 ||
        frame.height <= 0.0 ||
        visibleFrame.width <= 0.0 ||
        visibleFrame.height <= 0.0) {
      throw const FormatException(
        'present screen must have a positive identifier and dimensions',
      );
    }
    return AppKitScreen(
      displayId: displayId,
      frame: frame,
      visibleFrame: visibleFrame,
    );
  }

  static int _integer(List<Object?> values, int index, String name) {
    final Object? value = values[index];
    if (value is! int) {
      throw FormatException('$name must be an int');
    }
    return value;
  }

  static double _number(List<Object?> values, int index, String name) {
    final Object? value = values[index];
    if (value is! num) {
      throw FormatException('$name must be a number');
    }
    return value.toDouble();
  }

  static double _finiteNumber(List<Object?> values, int index, String name) {
    final double value = _number(values, index, name);
    if (!value.isFinite) {
      throw FormatException('$name must be finite');
    }
    return value;
  }

  static bool _boolean(List<Object?> values, int index, String name) {
    final Object? value = values[index];
    if (value is! bool) {
      throw FormatException('$name must be a bool');
    }
    return value;
  }

  static String _string(List<Object?> values, int index, String name) {
    final Object? value = values[index];
    if (value is! String) {
      throw FormatException('$name must be a string');
    }
    return value;
  }
}
