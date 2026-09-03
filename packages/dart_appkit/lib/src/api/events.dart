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

final class ModifierKeys {
  const ModifierKeys(this.bits);

  static const int capsLockBit = 1 << 0;
  static const int shiftBit = 1 << 1;
  static const int controlBit = 1 << 2;
  static const int optionBit = 1 << 3;
  static const int commandBit = 1 << 4;
  static const int numericPadBit = 1 << 5;
  static const int functionBit = 1 << 6;

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
  static const int _mouseDown = 10;
  static const int _mouseUp = 11;
  static const int _mouseMoved = 12;
  static const int _mouseDragged = 13;
  static const int _keyDown = 20;
  static const int _keyUp = 21;

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
    final int handle = _integer(message, 2, 'windowHandle');
    if (handle <= 0) {
      throw const FormatException('native event has an invalid window handle');
    }
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
      if (sourceGeneration <= 0 ||
          sourceGeneration != encodedHandleGeneration) {
        throw const FormatException(
          'native event source generation does not match its handle',
        );
      }
    }
    if (monotonicNanoseconds < 0) {
      throw const FormatException('native event has a negative timestamp');
    }
    if (operationId < 0) {
      throw const FormatException('native event has a negative operation ID');
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
