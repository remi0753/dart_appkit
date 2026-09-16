part of '../api.dart';

abstract final class TextEditorLimits {
  static const int maximumFontVariations = 16;
  static const int maximumTextUtf8Bytes =
      dartAppKitTextEditorMaximumTextUtf8Bytes;
  static const int maximumStyleRuns = dartAppKitTextEditorMaximumStyleRuns;
}

enum TextEditorUnderlineStyle { none, single }

/// One bounded OpenType variation coordinate for an editor's base font.
final class TextEditorFontVariation {
  factory TextEditorFontVariation(String tag, double value) {
    if (!RegExp(r'^[\x20-\x7e]{4}$').hasMatch(tag) ||
        !value.isFinite ||
        value < -65536 ||
        value > 65536) {
      throw ArgumentError(
        'font variation requires a four-byte tag and bounded finite coordinate',
      );
    }
    return TextEditorFontVariation._(tag, value);
  }

  const TextEditorFontVariation._(this.tag, this.value);
  final String tag;
  final double value;
  NativeTextEditorFontVariation get _native => NativeTextEditorFontVariation(
    tag: tag.codeUnits.fold<int>(0, (int bits, int byte) => (bits << 8) | byte),
    value: value,
  );
  @override
  bool operator ==(Object other) =>
      other is TextEditorFontVariation &&
      other.tag == tag &&
      other.value == value;
  @override
  int get hashCode => Object.hash(tag, value);
}

final class TextEditorSelection {
  const TextEditorSelection({required this.start, this.length = 0});

  final int start;
  final int length;

  int get end => start + length;

  @override
  bool operator ==(Object other) =>
      other is TextEditorSelection &&
      other.start == start &&
      other.length == length;

  @override
  int get hashCode => Object.hash(start, length);
}

/// One checked, non-overlapping foreground/underline range.
final class TextEditorStyleRun {
  const TextEditorStyleRun({
    required this.start,
    required this.length,
    required this.foregroundColor,
    this.underlineStyle = TextEditorUnderlineStyle.none,
    this.underlineColor = const TextViewColor.label(),
  });

  final int start;
  final int length;
  final TextViewColor foregroundColor;
  final TextEditorUnderlineStyle underlineStyle;
  final TextViewColor underlineColor;

  int get end => start + length;

  NativeTextEditorStyleRun get _native => NativeTextEditorStyleRun(
    start: start,
    length: length,
    foregroundColorKind: foregroundColor.kind.index,
    foregroundRed: foregroundColor.red,
    foregroundGreen: foregroundColor.green,
    foregroundBlue: foregroundColor.blue,
    foregroundAlpha: foregroundColor.alpha,
    underlineStyle: underlineStyle.index,
    underlineColorKind: underlineColor.kind.index,
    underlineRed: underlineColor.red,
    underlineGreen: underlineColor.green,
    underlineBlue: underlineColor.blue,
    underlineAlpha: underlineColor.alpha,
  );

  @override
  bool operator ==(Object other) =>
      other is TextEditorStyleRun &&
      other.start == start &&
      other.length == length &&
      other.foregroundColor == foregroundColor &&
      other.underlineStyle == underlineStyle &&
      other.underlineColor == underlineColor;

  @override
  int get hashCode => Object.hash(
    start,
    length,
    foregroundColor,
    underlineStyle,
    underlineColor,
  );
}

/// One optional full-width logical-line background, addressed in UTF-16.
final class TextEditorLineHighlight {
  const TextEditorLineHighlight({required this.location, required this.color});

  final int location;
  final TextViewColor color;

  NativeTextEditorLineHighlight get _native => NativeTextEditorLineHighlight(
    location: location,
    colorKind: color.kind.index,
    red: color.red,
    green: color.green,
    blue: color.blue,
    alpha: color.alpha,
  );

  @override
  bool operator ==(Object other) =>
      other is TextEditorLineHighlight &&
      other.location == location &&
      other.color == color;

  @override
  int get hashCode => Object.hash(location, color);
}

/// One atomic text, selection, and attributed-style publication.
final class TextEditorDocument {
  TextEditorDocument({
    required this.text,
    this.selection = const TextEditorSelection(start: 0),
    Iterable<TextEditorStyleRun> styleRuns = const <TextEditorStyleRun>[],
  }) : styleRuns = List<TextEditorStyleRun>.unmodifiable(styleRuns);

  final String text;
  final TextEditorSelection selection;
  final List<TextEditorStyleRun> styleRuns;

  NativeTextEditorDocument get _native => NativeTextEditorDocument(
    text: text,
    selectionStart: selection.start,
    selectionLength: selection.length,
    styleRuns: <NativeTextEditorStyleRun>[
      for (final TextEditorStyleRun run in styleRuns) run._native,
    ],
  );
}

/// Current plain text and UTF-16 selection read from the native editor.
final class TextEditorSnapshot {
  const TextEditorSnapshot({
    required this.text,
    required this.selection,
    required this.isEditable,
    required this.hasMarkedText,
  });

  final String text;
  final TextEditorSelection selection;
  final bool isEditable;
  final bool hasMarkedText;
}

/// Immutable behavior and base presentation for a scrollable [TextEditor].
final class TextEditorConfiguration {
  const TextEditorConfiguration({
    this.view = const ViewConfiguration(),
    this.font = const TextViewFont.monospacedSystem(size: 14),
    this.padding = const TextViewPadding.all(12),
    this.foregroundColor = const TextViewColor.label(),
    this.backgroundColor = const TextViewColor.windowBackground(),
    this.initiallyEditable = false,
  });

  final ViewConfiguration view;
  final TextViewFont font;
  final TextViewPadding padding;
  final TextViewColor foregroundColor;
  final TextViewColor backgroundColor;
  final bool initiallyEditable;

  void _validate() {
    font._validate();
    padding._validate();
  }

  NativeTextEditorConfiguration get _native => NativeTextEditorConfiguration(
    presentation: TextViewConfiguration(
      view: view,
      font: font,
      padding: padding,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
    )._native,
    initiallyEditable: initiallyEditable,
  );

  @override
  bool operator ==(Object other) =>
      other is TextEditorConfiguration &&
      other.view == view &&
      other.font == font &&
      other.padding == padding &&
      other.foregroundColor == foregroundColor &&
      other.backgroundColor == backgroundColor &&
      other.initiallyEditable == initiallyEditable;

  @override
  int get hashCode => Object.hash(
    view,
    font,
    padding,
    foregroundColor,
    backgroundColor,
    initiallyEditable,
  );
}

/// Generic multiline NSTextView surface with Dart-owned attributed ranges.
final class TextEditor extends View {
  factory TextEditor({
    TextEditorConfiguration configuration = const TextEditorConfiguration(),
  }) {
    configuration._validate();
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final NativeBindings bindings = application._bindings;
    if (bindings is! NativeTextEditorBindings) {
      throw const AppKitNativeException(
        operation: 'TextEditor.create',
        status: 8,
        nativeMessage: 'native bridge does not support text editors',
      );
    }
    final NativeTextEditorBindings editorBindings =
        bindings as NativeTextEditorBindings;
    final int handle = _checkValue<int>(
      editorBindings.textEditorCreate(configuration._native),
      'TextEditor.create',
    );
    return TextEditor._(application, handle, configuration);
  }

  TextEditor._(
    AppKitApplication application,
    int handle,
    TextEditorConfiguration configuration,
  ) : _configuration = configuration,
      _editorBindings = application._bindings as NativeTextEditorBindings,
      super._(application, handle, configuration.view);

  TextEditorConfiguration _configuration;
  TextEditorConfiguration get configuration => _configuration;
  List<TextEditorFontVariation> _fontVariations =
      const <TextEditorFontVariation>[];
  List<TextEditorFontVariation> get fontVariations => _fontVariations;
  final NativeTextEditorBindings _editorBindings;
  TextEditorLineHighlight? _lineHighlight;
  bool _suppressesUnhandledEscape = false;

  /// Suppresses only the wrapper's unhandled native cancelOperation fallback.
  ///
  /// Enable when the caller handles Escape using Dart window events. Native
  /// text-view/input-context handling runs first; ordinary editing and key
  /// routing are unchanged. Defaults to false. Requires an optional bridge API.
  bool get suppressesUnhandledEscape => _suppressesUnhandledEscape;
  set suppressesUnhandledEscape(bool suppressed) {
    ensureAlive();
    if (suppressed == _suppressesUnhandledEscape) return;
    final NativeBindings bindings = _application._bindings;
    if (bindings is! NativeTextEditorEscapeBindings) {
      throw const AppKitNativeException(
        operation: 'TextEditor.suppressesUnhandledEscape',
        status: 8,
        nativeMessage: 'native bridge does not support Escape fallback policy',
      );
    }
    _checkCall(
      (bindings as NativeTextEditorEscapeBindings)
          .textEditorSetUnhandledEscapeSuppressed(_handle, suppressed),
      'TextEditor.suppressesUnhandledEscape',
    );
    _suppressesUnhandledEscape = suppressed;
  }

  /// Updates base presentation in place without changing document, focus,
  /// selection, scroll, editability, marked text or explicit attributed runs.
  /// Unavailable variation axes are left to AppKit's font descriptor fallback.
  bool updatePresentation({
    required TextViewFont font,
    required TextViewColor foregroundColor,
    required TextViewColor backgroundColor,
    TextViewPadding? padding,
    Iterable<TextEditorFontVariation> fontVariations =
        const <TextEditorFontVariation>[],
  }) {
    ensureAlive();
    final List<TextEditorFontVariation> variations =
        List<TextEditorFontVariation>.unmodifiable(fontVariations);
    if (variations.length > TextEditorLimits.maximumFontVariations) {
      throw RangeError.range(
        variations.length,
        0,
        TextEditorLimits.maximumFontVariations,
        'fontVariations.length',
      );
    }
    final TextEditorConfiguration next = TextEditorConfiguration(
      view: configuration.view,
      font: font,
      padding: padding ?? configuration.padding,
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      initiallyEditable: configuration.initiallyEditable,
    );
    next._validate();
    if (next == configuration &&
        variations.length == _fontVariations.length &&
        List<bool>.generate(
          variations.length,
          (int i) => variations[i] == _fontVariations[i],
        ).every((bool same) => same))
      return false;
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeTextEditorPresentationBindings) {
      throw const AppKitNativeException(
        operation: 'TextEditor.updatePresentation',
        status: 8,
        nativeMessage:
            'native bridge does not support text editor presentation updates',
      );
    }
    _checkCall(
      (bindings as NativeTextEditorPresentationBindings)
          .textEditorUpdatePresentation(
            _handle,
            next._native.presentation,
            <NativeTextEditorFontVariation>[
              for (final TextEditorFontVariation axis in variations)
                axis._native,
            ],
          ),
      'TextEditor.updatePresentation',
    );
    _configuration = next;
    _fontVariations = variations;
    return true;
  }

  /// The last successfully published line highlight, if any.
  TextEditorLineHighlight? get lineHighlight {
    ensureAlive();
    return _lineHighlight;
  }

  TextEditorSnapshot get snapshot {
    ensureAlive();
    final NativeTextEditorSnapshot native = _checkValue(
      _editorBindings.textEditorSnapshot(_handle),
      'TextEditor.snapshot',
    );
    return TextEditorSnapshot(
      text: native.text,
      selection: TextEditorSelection(
        start: native.selectionStart,
        length: native.selectionLength,
      ),
      isEditable: native.isEditable,
      hasMarkedText: native.hasMarkedText,
    );
  }

  void setDocument(TextEditorDocument document) {
    ensureAlive();
    _validateDocument(document);
    _checkCall(
      _editorBindings.textEditorSetDocument(_handle, document._native),
      'TextEditor.setDocument',
    );
    _lineHighlight = null;
  }

  void setStyleRuns(Iterable<TextEditorStyleRun> runs) {
    ensureAlive();
    final List<TextEditorStyleRun> copied =
        List<TextEditorStyleRun>.unmodifiable(runs);
    final TextEditorSnapshot current = snapshot;
    _validateStyleRuns(current.text, copied);
    _checkCall(
      _editorBindings.textEditorSetStyleRuns(
        _handle,
        <NativeTextEditorStyleRun>[
          for (final TextEditorStyleRun run in copied) run._native,
        ],
      ),
      'TextEditor.setStyleRuns',
    );
  }

  /// Sets a full-width background for the logical line at [location].
  ///
  /// Passing `null` clears the highlight. Replacing the document also clears
  /// it so a location from the previous buffer cannot remain active.
  void setLineHighlight(TextEditorLineHighlight? highlight) {
    ensureAlive();
    if (highlight != null) {
      final TextEditorSnapshot current = snapshot;
      _validateSelection(
        current.text,
        TextEditorSelection(start: highlight.location),
      );
    }
    _checkCall(
      _editorBindings.textEditorSetLineHighlight(_handle, highlight?._native),
      'TextEditor.setLineHighlight',
    );
    _lineHighlight = highlight;
  }

  set isEditable(bool value) {
    ensureAlive();
    _checkCall(
      _editorBindings.textEditorSetEditable(_handle, value),
      'TextEditor.isEditable',
    );
  }

  void setSelection(TextEditorSelection selection) {
    ensureAlive();
    final TextEditorSnapshot current = snapshot;
    _validateSelection(current.text, selection);
    _checkCall(
      _editorBindings.textEditorSetSelection(
        _handle,
        start: selection.start,
        length: selection.length,
      ),
      'TextEditor.setSelection',
    );
  }

  /// Scrolls the current selection into the visible editor viewport.
  ///
  /// This does not change the document, selection, attributed styles, or line
  /// highlight. Call it explicitly after a Dart-owned navigation change when
  /// the viewport should follow that selection.
  void scrollSelectionToVisible() {
    ensureAlive();
    _checkCall(
      _editorBindings.textEditorScrollSelectionToVisible(_handle),
      'TextEditor.scrollSelectionToVisible',
    );
  }

  static void _validateDocument(TextEditorDocument document) {
    final int bytes = utf8.encode(document.text).length;
    if (bytes > TextEditorLimits.maximumTextUtf8Bytes) {
      throw RangeError.range(
        bytes,
        0,
        TextEditorLimits.maximumTextUtf8Bytes,
        'document.text',
      );
    }
    _validateSelection(document.text, document.selection);
    _validateStyleRuns(document.text, document.styleRuns);
  }

  static void _validateStyleRuns(String text, List<TextEditorStyleRun> runs) {
    if (runs.length > TextEditorLimits.maximumStyleRuns) {
      throw RangeError.range(
        runs.length,
        0,
        TextEditorLimits.maximumStyleRuns,
        'styleRuns.length',
      );
    }
    var previousEnd = 0;
    for (var index = 0; index < runs.length; index++) {
      final TextEditorStyleRun run = runs[index];
      if (run.start < previousEnd ||
          run.start < 0 ||
          run.length <= 0 ||
          run.end > text.length ||
          !_isScalarBoundary(text, run.start) ||
          !_isScalarBoundary(text, run.end)) {
        throw RangeError(
          'styleRuns[$index] must be ordered, non-overlapping, positive, '
          'in bounds, and aligned to UTF-16 scalar boundaries',
        );
      }
      previousEnd = run.end;
    }
  }

  static void _validateSelection(String text, TextEditorSelection selection) {
    if (selection.start < 0 ||
        selection.length < 0 ||
        selection.end > text.length ||
        !_isScalarBoundary(text, selection.start) ||
        !_isScalarBoundary(text, selection.end)) {
      throw RangeError(
        'selection must be in bounds and aligned to UTF-16 scalar boundaries',
      );
    }
  }

  static bool _isScalarBoundary(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return true;
    final int before = text.codeUnitAt(offset - 1);
    final int after = text.codeUnitAt(offset);
    return !(before >= 0xd800 &&
        before <= 0xdbff &&
        after >= 0xdc00 &&
        after <= 0xdfff);
  }
}
