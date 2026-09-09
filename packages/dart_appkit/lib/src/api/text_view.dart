part of '../api.dart';

enum TextViewFontKind { system, monospacedSystem, named }

enum TextViewFontWeight {
  ultraLight,
  thin,
  light,
  regular,
  medium,
  semibold,
  bold,
  heavy,
  black,
}

/// Immutable font selection for the built-in display-only [TextView].
final class TextViewFont {
  const TextViewFont.system({
    this.size = 18,
    this.weight = TextViewFontWeight.regular,
  }) : kind = TextViewFontKind.system,
       family = null;

  const TextViewFont.monospacedSystem({
    this.size = 18,
    this.weight = TextViewFontWeight.regular,
  }) : kind = TextViewFontKind.monospacedSystem,
       family = null;

  /// Selects an exact AppKit font name; encode styles in that name.
  factory TextViewFont.named(String family, {double size = 18}) {
    final int length = utf8.encode(family).length;
    if (family.isEmpty || length > maximumFamilyUtf8Bytes) {
      throw ArgumentError.value(
        family,
        'family',
        'must be non-empty and within the UTF-8 byte limit',
      );
    }
    return TextViewFont._(
      kind: TextViewFontKind.named,
      family: family,
      size: size,
      weight: TextViewFontWeight.regular,
    );
  }

  const TextViewFont._({
    required this.kind,
    required this.family,
    required this.size,
    required this.weight,
  });

  static const double maximumSize = dartAppKitTextViewFontMaximumSize;
  static const int maximumFamilyUtf8Bytes =
      dartAppKitTextViewFontFamilyMaximumUtf8Bytes;

  final TextViewFontKind kind;
  final String? family;
  final double size;
  final TextViewFontWeight weight;

  void _validate() {
    if (!size.isFinite || size <= 0 || size > maximumSize) {
      throw ArgumentError.value(
        size,
        'font.size',
        'must be finite, positive, and within the font-size bound',
      );
    }
    final String? selectedFamily = family;
    if (kind == TextViewFontKind.named) {
      if (selectedFamily == null ||
          selectedFamily.isEmpty ||
          utf8.encode(selectedFamily).length > maximumFamilyUtf8Bytes) {
        throw ArgumentError.value(
          selectedFamily,
          'font.family',
          'named fonts require a family within the UTF-8 byte limit',
        );
      }
    } else if (selectedFamily != null) {
      throw ArgumentError.value(
        selectedFamily,
        'font.family',
        'system fonts do not accept a named family',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TextViewFont &&
      other.kind == kind &&
      other.family == family &&
      other.size == size &&
      other.weight == weight;

  @override
  int get hashCode => Object.hash(kind, family, size, weight);
}

/// Immutable logical padding around display text.
final class TextViewPadding {
  const TextViewPadding({
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
    this.left = 0,
  });

  const TextViewPadding.all(double value)
    : top = value,
      right = value,
      bottom = value,
      left = value;

  static const double maximumExtent = dartAppKitTextViewPaddingMaximumExtent;

  final double top;
  final double right;
  final double bottom;
  final double left;

  void _validate() {
    for (final MapEntry<String, double> extent in <String, double>{
      'padding.top': top,
      'padding.right': right,
      'padding.bottom': bottom,
      'padding.left': left,
    }.entries) {
      if (!extent.value.isFinite ||
          extent.value < 0 ||
          extent.value > maximumExtent) {
        throw ArgumentError.value(
          extent.value,
          extent.key,
          'must be finite, non-negative, and within the padding bound',
        );
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TextViewPadding &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

enum TextViewColorKind { label, windowBackground, sRgb }

/// Dynamic system role or fixed sRGB color used by [TextView].
final class TextViewColor {
  const TextViewColor.label()
    : kind = TextViewColorKind.label,
      red = 0,
      green = 0,
      blue = 0,
      alpha = 1;

  const TextViewColor.windowBackground()
    : kind = TextViewColorKind.windowBackground,
      red = 0,
      green = 0,
      blue = 0,
      alpha = 1;

  factory TextViewColor.sRgb({
    required double red,
    required double green,
    required double blue,
    double alpha = 1,
  }) {
    for (final MapEntry<String, double> component in <String, double>{
      'red': red,
      'green': green,
      'blue': blue,
      'alpha': alpha,
    }.entries) {
      if (!component.value.isFinite ||
          component.value < 0 ||
          component.value > 1) {
        throw RangeError.range(component.value, 0, 1, component.key);
      }
    }
    return TextViewColor._(
      kind: TextViewColorKind.sRgb,
      red: red,
      green: green,
      blue: blue,
      alpha: alpha,
    );
  }

  const TextViewColor._({
    required this.kind,
    required this.red,
    required this.green,
    required this.blue,
    required this.alpha,
  });

  final TextViewColorKind kind;
  final double red;
  final double green;
  final double blue;
  final double alpha;

  @override
  bool operator ==(Object other) =>
      other is TextViewColor &&
      other.kind == kind &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(kind, red, green, blue, alpha);
}

/// Immutable behavior and presentation selected when a [TextView] is created.
final class TextViewConfiguration {
  const TextViewConfiguration({
    this.view = const ViewConfiguration(),
    this.font = const TextViewFont.monospacedSystem(),
    this.padding = const TextViewPadding.all(20),
    this.foregroundColor = const TextViewColor.label(),
    this.backgroundColor = const TextViewColor.windowBackground(),
  });

  final ViewConfiguration view;
  final TextViewFont font;
  final TextViewPadding padding;
  final TextViewColor foregroundColor;
  final TextViewColor backgroundColor;

  void _validate() {
    font._validate();
    padding._validate();
  }

  NativeTextViewConfiguration get _native => NativeTextViewConfiguration(
    view: view._native,
    fontKind: font.kind.index,
    fontWeight: font.weight.index,
    fontSize: font.size,
    fontFamily: font.family,
    paddingTop: padding.top,
    paddingRight: padding.right,
    paddingBottom: padding.bottom,
    paddingLeft: padding.left,
    foregroundColorKind: foregroundColor.kind.index,
    foregroundRed: foregroundColor.red,
    foregroundGreen: foregroundColor.green,
    foregroundBlue: foregroundColor.blue,
    foregroundAlpha: foregroundColor.alpha,
    backgroundColorKind: backgroundColor.kind.index,
    backgroundRed: backgroundColor.red,
    backgroundGreen: backgroundColor.green,
    backgroundBlue: backgroundColor.blue,
    backgroundAlpha: backgroundColor.alpha,
  );

  @override
  bool operator ==(Object other) =>
      other is TextViewConfiguration &&
      other.view == view &&
      other.font == font &&
      other.padding == padding &&
      other.foregroundColor == foregroundColor &&
      other.backgroundColor == backgroundColor;

  @override
  int get hashCode =>
      Object.hash(view, font, padding, foregroundColor, backgroundColor);
}

final class TextView extends View {
  factory TextView({
    TextViewConfiguration configuration = const TextViewConfiguration(),
  }) {
    configuration._validate();
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int handle = _checkValue<int>(
      application._bindings.textViewCreate(configuration._native),
      'TextView.create',
    );
    return TextView._(application._bindings, handle, configuration);
  }

  TextView._(NativeBindings bindings, int handle, this.configuration)
    : super._(bindings, handle, configuration.view);

  final TextViewConfiguration configuration;

  String _text = '';

  String get text {
    ensureAlive();
    return _text;
  }

  set text(String value) {
    ensureAlive();
    _checkCall(_bindings.textViewSetText(_handle, value), 'TextView.text');
    _text = value;
  }
}
