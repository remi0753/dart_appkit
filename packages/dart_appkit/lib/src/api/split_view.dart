part of '../api.dart';

/// Direction in which two native split-view children are arranged.
enum SplitViewAxis {
  /// The first child is left of the second child.
  horizontal,

  /// The first child is above the second child.
  vertical,
}

/// One ordered child that can occupy the whole split view while zoomed.
enum SplitViewChild { first, second }

/// A native two-pane helper that remains substitutable as a [View].
///
/// This deliberately narrow helper owns exactly two ordered children, one thin
/// non-collapsible divider, and an optional binary zoom selection. It is not a
/// generic representation of every `NSSplitView` configuration.
final class TwoPaneSplitView extends View {
  factory TwoPaneSplitView({required SplitViewAxis axis}) {
    final AppKitApplication application = AppKitApplication._requireCurrent();
    final int nativeAxis = axis == SplitViewAxis.horizontal ? 0 : 1;
    final int handle = _checkValue<int>(
      application._bindings.splitViewCreate(nativeAxis),
      'TwoPaneSplitView.create',
    );
    return TwoPaneSplitView._(application._bindings, handle, axis);
  }

  TwoPaneSplitView._(NativeBindings bindings, int handle, this.axis)
    : super._(bindings, handle, null);

  final SplitViewAxis axis;
  View? _firstView;
  View? _secondView;
  double _fraction = 0.5;
  double _firstMinimumExtent = 0;
  double _secondMinimumExtent = 0;
  SplitViewChild? _zoomedChild;

  View? get firstView {
    ensureAlive();
    return _firstView;
  }

  View? get secondView {
    ensureAlive();
    return _secondView;
  }

  double get fraction {
    ensureAlive();
    return _fraction;
  }

  /// Refreshes the first-child fraction after native divider interaction.
  ///
  /// This is an explicit observation because native drags do not mutate Dart
  /// application state automatically. Older bridges report unsupported rather
  /// than returning the last Dart-requested value as if it were current.
  double refreshFraction() {
    ensureAlive();
    final NativeBindings bindings = _bindings;
    if (bindings is! NativeSplitViewPositionBindings) {
      throw const AppKitNativeException(
        operation: 'TwoPaneSplitView.refreshFraction',
        status: 8,
        nativeMessage:
            'native bridge does not support split position observation',
      );
    }
    final NativeSplitViewPositionBindings positionBindings =
        bindings as NativeSplitViewPositionBindings;
    final double value = _checkValue<double>(
      positionBindings.splitViewGetFraction(_handle),
      'TwoPaneSplitView.refreshFraction',
    );
    if (!value.isFinite || value < 0 || value > 1) {
      throw StateError('native split fraction is outside [0, 1]');
    }
    _fraction = value;
    return value;
  }

  double get firstMinimumExtent {
    ensureAlive();
    return _firstMinimumExtent;
  }

  double get secondMinimumExtent {
    ensureAlive();
    return _secondMinimumExtent;
  }

  SplitViewChild? get zoomedChild {
    ensureAlive();
    return _zoomedChild;
  }

  void setChildren({required View first, required View second}) {
    ensureAlive();
    first.ensureAlive();
    second.ensureAlive();
    if (identical(first, second) ||
        identical(first, this) ||
        identical(second, this)) {
      throw ArgumentError('split and children must be distinct views');
    }
    if (!identical(first._bindings, _bindings) ||
        !identical(second._bindings, _bindings)) {
      throw StateError('split children belong to a different application');
    }
    _checkCall(
      _bindings.splitViewSetChildren(_handle, first._handle, second._handle),
      'TwoPaneSplitView.setChildren',
    );
    _firstView = first;
    _secondView = second;
  }

  void setPosition({
    required double fraction,
    double firstMinimumExtent = 0,
    double secondMinimumExtent = 0,
  }) {
    ensureAlive();
    if (!fraction.isFinite || fraction <= 0 || fraction >= 1) {
      throw ArgumentError.value(
        fraction,
        'fraction',
        'must be finite and strictly between zero and one',
      );
    }
    if (!firstMinimumExtent.isFinite || firstMinimumExtent < 0) {
      throw ArgumentError.value(
        firstMinimumExtent,
        'firstMinimumExtent',
        'must be finite and non-negative',
      );
    }
    if (!secondMinimumExtent.isFinite || secondMinimumExtent < 0) {
      throw ArgumentError.value(
        secondMinimumExtent,
        'secondMinimumExtent',
        'must be finite and non-negative',
      );
    }
    _checkCall(
      _bindings.splitViewSetPosition(
        handle: _handle,
        fraction: fraction,
        firstMinimumExtent: firstMinimumExtent,
        secondMinimumExtent: secondMinimumExtent,
      ),
      'TwoPaneSplitView.setPosition',
    );
    _fraction = fraction;
    _firstMinimumExtent = firstMinimumExtent;
    _secondMinimumExtent = secondMinimumExtent;
  }

  void equalize() {
    ensureAlive();
    _checkCall(
      _bindings.splitViewEqualize(_handle),
      'TwoPaneSplitView.equalize',
    );
    _fraction = 0.5;
  }

  set zoomedChild(SplitViewChild? value) {
    ensureAlive();
    final int nativeValue = switch (value) {
      null => -1,
      SplitViewChild.first => 0,
      SplitViewChild.second => 1,
    };
    _checkCall(
      _bindings.splitViewSetZoomedChild(_handle, nativeValue),
      'TwoPaneSplitView.zoomedChild',
    );
    _zoomedChild = value;
  }
}

/// Source-compatible name for the historical two-pane helper.
@Deprecated('Use TwoPaneSplitView to make the two-pane boundary explicit.')
typedef SplitView = TwoPaneSplitView;
