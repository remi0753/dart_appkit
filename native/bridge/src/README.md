# Bridge implementation

This directory implements the generation-safe object registry, AppKit
window/text-view types, UTF-8 and thread-local error handling, main-thread
guards, finalizer dispatch, stable input events, and the Runner-injected
asynchronous event sink. It has no Dart Engine link dependency and is tested as
both a standalone dylib and part of the native test executable.
