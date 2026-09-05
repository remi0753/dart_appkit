# Bridge implementation

This directory implements the generation-safe object registry, AppKit
window/text-view types, UTF-8 and thread-local error handling, main-thread
guards, finalizer dispatch, stable input events, and the Runner-injected
asynchronous event sink. Per-window key routing keeps dual Dart/AppKit dispatch
as the default and lets raw-input views retain native menu shortcuts while
suppressing ordinary responder fallthrough. The bridge has no Dart Engine link
dependency and is tested as both a standalone dylib and part of the native test
executable.
