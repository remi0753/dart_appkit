part of '../api.dart';

final class PasteboardTextSnapshot {
  const PasteboardTextSnapshot({required this.text, required this.changeCount});

  final String? text;
  final int changeCount;
}

final class Pasteboard {
  Pasteboard._(this._application);

  final AppKitApplication _application;

  /// Maximum UTF-8 bytes copied from AppKit by one [readText] call.
  static const int maximumTextUtf8Bytes =
      dartAppKitPasteboardMaximumTextUtf8Bytes;

  PasteboardTextSnapshot readText() {
    _application._ensureRunning();
    final NativePasteboardTextSnapshot native =
        _checkValue<NativePasteboardTextSnapshot>(
          _application._bindings.pasteboardReadText(),
          'Pasteboard.readText',
        );
    return PasteboardTextSnapshot(
      text: native.text,
      changeCount: native.changeCount,
    );
  }

  int writeText(String text) {
    _application._ensureRunning();
    return _checkValue<int>(
      _application._bindings.pasteboardWriteText(text),
      'Pasteboard.writeText',
    );
  }

  int clear() {
    _application._ensureRunning();
    return _checkValue<int>(
      _application._bindings.pasteboardClear(),
      'Pasteboard.clear',
    );
  }

  int get changeCount {
    _application._ensureRunning();
    return _checkValue<int>(
      _application._bindings.pasteboardGetChangeCount(),
      'Pasteboard.changeCount',
    );
  }
}
