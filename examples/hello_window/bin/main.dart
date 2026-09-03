import 'dart:async';
import 'dart:io';

import 'package:dart_appkit/dart_appkit.dart';

Future<void> main(List<String> arguments) async {
  final Duration? autoCloseAfter = _parseAutoCloseAfter(arguments);
  final AppKitApplication application = await AppKitApplication.attach();
  stdout.writeln('Dart root isolate is attached to the AppKit main thread.');
  if (arguments.isNotEmpty) {
    stdout.writeln('Application arguments: ${arguments.join(' | ')}');
  }

  final TextView textView = TextView();
  final Window window =
      Window(
          frame: const Rect.fromLTWH(120, 120, 640, 360),
          title: 'Dart AppKit — Hello Window',
        )
        ..contentView = textView
        ..defersCloseRequests = true;
  final Menu mainMenu = Menu();
  final Menu applicationMenu = Menu(title: 'Dart AppKit');
  final MenuItem applicationMenuItem = MenuItem(title: 'Dart AppKit')
    ..submenu = applicationMenu;
  final MenuItem quitItem = MenuItem(
    title: 'Quit Dart AppKit',
    keyEquivalent: 'q',
    modifiers: const ModifierKeys(ModifierKeys.commandBit),
  );
  mainMenu.addItem(applicationMenuItem);
  applicationMenu.addItem(quitItem);
  application.mainMenu = mainMenu;
  final Completer<void> closed = Completer<void>();
  var ticks = 0;

  void updateText() {
    textView.text = <String>[
      'Hello from an embedded Dart root isolate.',
      '',
      'Timer ticks: $ticks',
      'The AppKit window and Dart Timer share the main run loop.',
      '',
      'Resize, click, or type to see events in stdout.',
      'Close this window to terminate cleanly.',
    ].join('\n');
  }

  updateText();
  final StreamSubscription<WindowEvent>
  eventSubscription = window.events.listen(
    (WindowEvent event) {
      switch (event) {
        case WindowClosedEvent():
          stdout.writeln('Window close event reached Dart.');
          if (!closed.isCompleted) {
            closed.complete();
          }
        case WindowCloseRequestedEvent():
          stdout.writeln(
            'Window close request reached Dart '
            '(operation ${event.operationId}).',
          );
          window.replyToCloseRequest(event, allow: true);
        case WindowResizedEvent(:final width, :final height):
          stdout.writeln(
            'resize ${width.toStringAsFixed(0)} x '
            '${height.toStringAsFixed(0)}',
          );
        case WindowFocusChangedEvent(:final isFocused):
          stdout.writeln('focus ${isFocused ? 'gained' : 'lost'}');
        case WindowVisibilityChangedEvent(:final isVisible):
          stdout.writeln('visibility ${isVisible ? 'visible' : 'hidden'}');
        case WindowOcclusionChangedEvent(:final isOccluded):
          stdout.writeln('occlusion ${isOccluded ? 'occluded' : 'unoccluded'}');
        case WindowBackingScaleChangedEvent(:final backingScaleFactor):
          stdout.writeln(
            'backing scale ${backingScaleFactor.toStringAsFixed(2)}',
          );
        case WindowScreenChangedEvent(:final screen):
          stdout.writeln(
            screen == null
                ? 'screen unavailable'
                : 'screen ${screen.displayId} frame=${screen.frame}',
          );
        case AppKitMouseEvent(:final kind, :final x, :final y, :final button):
          stdout.writeln(
            'mouse ${kind.name} button=$button '
            'at ${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}',
          );
        case AppKitKeyEvent(:final kind, :final keyCode, :final characters):
          stdout.writeln(
            'key ${kind.name} code=$keyCode characters="$characters"',
          );
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!closed.isCompleted) {
        closed.completeError(error, stackTrace);
      }
    },
  );
  final StreamSubscription<MenuItemInvokedEvent> menuSubscription = quitItem
      .onInvoked
      .listen((MenuItemInvokedEvent event) {
        stdout.writeln(
          'Quit menu action reached Dart (item ${event.menuItemHandle}).',
        );
        window.requestClose();
      });
  final Timer timer = Timer.periodic(const Duration(seconds: 1), (_) {
    ++ticks;
    updateText();
    if (autoCloseAfter != null) {
      stdout.writeln('Timer tick $ticks reached Dart.');
    }
  });
  Timer? autoCloseTimer;

  window.show();
  if (autoCloseAfter != null) {
    stdout.writeln(
      'Automated close scheduled after ${autoCloseAfter.inSeconds} seconds.',
    );
    autoCloseTimer = Timer(autoCloseAfter, () {
      stdout.writeln('Automated smoke menu action requested.');
      quitItem.performAction();
    });
  }
  try {
    await closed.future;
  } finally {
    autoCloseTimer?.cancel();
    timer.cancel();
    await eventSubscription.cancel();
    await menuSubscription.cancel();
    application.mainMenu = null;
    quitItem.dispose();
    applicationMenuItem.dispose();
    applicationMenu.dispose();
    mainMenu.dispose();
    if (!window.isDisposed) {
      window.dispose();
    }
    if (!textView.isDisposed) {
      textView.dispose();
    }
    await application.terminate();
  }
  stdout.writeln('Clean shutdown requested; native handles released.');
}

Duration? _parseAutoCloseAfter(List<String> arguments) {
  const String prefix = '--auto-close-after=';
  Duration? result;
  for (final String argument in arguments) {
    if (!argument.startsWith(prefix)) {
      continue;
    }
    if (result != null) {
      throw const FormatException('--auto-close-after may only be set once');
    }
    final int? seconds = int.tryParse(argument.substring(prefix.length));
    if (seconds == null || seconds <= 0) {
      throw FormatException(
        '--auto-close-after must be a positive number of seconds: $argument',
      );
    }
    result = Duration(seconds: seconds);
  }
  return result;
}
