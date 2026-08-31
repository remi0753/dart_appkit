# MVP Verification

Verification date: 2026-08-31 (Asia/Tokyo).

## Result

The pinned Dart Engine has been fetched, built, linked, and exercised in the
real AppKit Runner. The unattended `hello_window` run attached the Dart root
isolate to the process main thread, processed three periodic Timer callbacks,
closed through the native window API, delivered the close event back to Dart,
released native handles, and exited 0.

The checkout is the official Dart repository at exactly
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. The arm64 release dylib is a 36 MB
Mach-O artifact with the required symbols and
`@rpath/libdart_engine_jit_shared.dylib` install name. The complete
history-free checkout and build occupy approximately 10 GiB in this workspace.

| Requirement | Evidence | Status |
|---|---|---|
| AppKit bridge is warning-clean | ARC/C++20 build with project warnings as errors | Verified |
| C ABI is usable from C and C++ | C11 and C++20 header compilation | Verified |
| Handles, UTF-8, errors, main-thread guard, finalizer | Native contract tests | Verified |
| close/resize/mouse/key native model | Native payload tests plus Dart decoder/routing tests | Verified |
| Dart FFI crosses the real Mach-O bridge | Struct/error/ABI FFI smoke | Verified |
| Runner startup matches Dart 3.13.2 | Strict compile plus exact source revision check | Verified |
| Scheduler cannot re-enter and is bounded | FIFO, count-budget, and time-budget message-pump tests | Verified |
| Launcher validation, bundle, stdio, arguments, exits | Fake-process workflow plus real bundle run | Verified |
| Pinned checkout bootstrap is reproducible | First build succeeded; second run synced safely and Ninja reported no work | Verified |
| Engine dylib and Kernel toolchain match | Architecture, symbols, install name, compiler, and platform checks pass | Verified |
| Real Runner links the official Engine dylib | `make runner` links the validated arm64 release artifact | Verified |
| Embedded Dart runs on the AppKit main thread | Runtime log follows the native `pthread_main_np()` attachment gate | Verified |
| Timer advances in the visible Engine-backed run | Smoke log recorded Timer ticks 1, 2, and 3 | Verified |
| Native close reaches Dart and shuts down cleanly | Close event and handle-release logs followed by exit 0 | Verified |
| Default workflow needs no Engine exports | Direct run with all Engine variables removed succeeded | Verified |

## Commands

Provision or update the Engine:

```shell
make engine
```

Run all noninteractive regression checks:

```shell
make test
make engine-check
```

Run the real GUI integration smoke test:

```shell
make example-smoke
```

The verified smoke output includes:

```text
Dart root isolate is attached to the AppKit main thread.
Timer tick 1 reached Dart.
Timer tick 2 reached Dart.
Timer tick 3 reached Dart.
Automated smoke close requested.
Window close event reached Dart.
Clean shutdown requested; native handles released.
```

`make run-example` keeps the window open for interactive resize, mouse, and key
testing. The project root is not inside a Git working tree in this workspace,
so no project Git dirty-status evidence is available; the nested Dart checkout
itself is clean and its exact `HEAD` is validated by the bootstrap.

## Next-phase backlog

- Add VM Service and restart only after deciding the desired debugging model.
- Treat AOT, signing, hardened runtime, sandboxing, accessibility, IME,
  clipboard, PTY, and distribution as separate milestones.
- Consider a smaller prebuilt Engine cache for contributors who should not
  carry the approximately 10 GiB source/build workspace.
