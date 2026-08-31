# Native Runner

This directory owns `NSApplication`, the process main thread, the AppKit run
loop, the Dart Engine/root isolate, Kernel invocation, and the bounded
main-run-loop message pump. It links the AppKit bridge into the executable so
Dart resolves the public C ABI through `DynamicLibrary.process()`.

`RunnerArguments` validates the private launcher/Runner protocol. `DartHost`
checks Dart 3.13.2 plus the exact compiled source revision, owns Engine startup
and teardown, invokes `main(List<String>)`, and serializes native events.
`DartMessagePump` accepts scheduler callbacks on arbitrary threads but handles
them only through a main-run-loop source, with limits of 64 messages or 4 ms per
turn.

`test_support/include/dart_engine.h` is a declaration-only copy used solely to
warning-compile and unit-test source when the released SDK lacks the Engine
binary. Production `make runner` always includes the official header and links
the explicit, revision-validated dylib.
