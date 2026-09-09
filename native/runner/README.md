# Native Runner

This directory owns `NSApplication`, the process main thread, the AppKit run
loop, one process-lifetime stock Dart Engine root isolate, Kernel invocation,
and the bounded main-run-loop message pump. It links the AppKit bridge into the
executable so Dart resolves the public C ABI through
`DynamicLibrary.process()`.

`RunnerArguments` validates the private launcher/Runner protocol. `DartHost`
checks Dart 3.13.2 plus the exact compiled source revision, owns Engine startup
and teardown, invokes `main(List<String>)`, and serializes native events.
`DartMessagePump` accepts scheduler callbacks on arbitrary threads but handles
them only through a main-run-loop source. The optional manifest
`runner.messagePump` object selects the per-turn message and elapsed-time
budgets. Defaults remain 64 messages and 4000 microseconds; the Runner rejects
values outside the library hard maxima of 1024 messages and 16000 microseconds.

`test_support/include/dart_engine.h` is a declaration-only copy used solely to
warning-compile and unit-test source when the released SDK lacks the Engine
binary. Production `make runner` always includes the official header and links
the explicit, revision-validated dylib. The SDK checkout must remain at the
exact official revision without tracked source changes.

`PublicDartApiHostProbe.cc` is a conformance-only negative proof for the
previously proposed full public `dart_api.h` host. It uses no Engine or private
Dart interfaces and demonstrates in ARM64 JIT/AOT that the stock shared VM
carrier does not expose the platform, microtask, and child-isolate bootstrap
required to replace `dart_engine`. It is not linked into the production Runner.
The production contract does not include `Isolate.spawn`, multiple Engine
roots, VM restart, or product worker-process supervision.
