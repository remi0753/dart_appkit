# MVP Verification

Verification date: 2026-09-04 (Asia/Tokyo).

## Result

The pinned Dart Engine has been fetched, built, linked, and exercised in the
real AppKit Runner. The unattended `hello_window` run attached the Dart root
isolate to the process main thread, processed three periodic Timer callbacks,
delivered an opted-in user-close request and reply, emitted the resulting close
event, released native handles, and exited 0.

The checkout is the official Dart repository at exactly
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. The arm64 release dylib is a 36 MB
Mach-O artifact with the required symbols and
`@rpath/libdart_engine_jit_shared.dylib` install name. The complete
history-free checkout and build occupy approximately 10 GiB in this workspace.

The accepted hosting contract is deliberately one stock Engine root for the
GUI process lifetime. A full public-API replacement host was exercised in both
M1/ARM64 JIT and AOT and rejected: the public library can create and clean up a
root, but cannot complete Dart platform, microtask, and child-isolate setup
without unexported `runtime/bin` implementation. Products that need dynamic
workers must use official Dart JIT/AOT worker processes and explicit IPC.

| Requirement | Evidence | Status |
|---|---|---|
| AppKit bridge is warning-clean | ARC/C++20 build with project warnings as errors | Verified |
| C ABI is usable from C and C++ | C11 and C++20 header compilation | Verified |
| Handle generations/domains, async release, UTF-8, errors, main-thread guard, finalizer | Native contract tests including concurrent claim, shutdown, and 1,000-slot churn | Verified |
| close/resize/mouse/key and v3 window-state native model | Native payload/snapshot/deduplication tests plus Dart decoder/routing/state tests | Verified |
| v4 application/window lifecycle decisions | Exact encoder records, native delegate coalescing/fail-open/stale-reply tests, Dart state/typed-stream/API tests | Verified |
| Plain-text pasteboard snapshot/write/clear | In-process pasteboard-double native tests, nullable/empty/Unicode/NUL Dart tests, FFI thread guard and legacy fallback | Verified |
| Menu ownership, attachment, state, and actions | Native retain/release and v4 suppression tests, Dart ownership/routing/cross-application tests, real GUI action smoke | Verified |
| Registered native custom-view boundary | Objective-C++ provider validation, generic-handle attach/release tests, Dart factory and optional FFI fallback | Verified |
| Reusable runtime public ABI | C11/C++20 headers plus main-thread/conflict lifecycle tests | Verified |
| Configurable bounded diagnostics | Native validation, permissions, phase ordering, previous-unclean retention, and clean finish tests | Verified |
| Manifest-driven Developer JIT application | Generic host build and real hello-window Timer/menu/close smoke | Verified |
| Manifest-driven Release AOT application | Generic host/snapshot build and the same real hello-window smoke | Verified |
| Runtime package and builder | Strict manifest/resource tests, fake-process JIT/AOT assembly, Dart analysis | Verified |
| Versioned native extension services | Size/version C ABI, main-thread registration, invalid UTF-8, duplicate/conflict, and factory failure tests | Verified |
| Dependency-owned native capability | Dart 3.13 build-hook asset test plus dynamic image ABI/init/create/release/shutdown/lifetime native test | Verified |
| Capability-enabled JIT/AOT GUI | Same Dart facade and manifest create the dependency view in both real generic hosts; bundles pass deep signature verification | Verified |
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
| Dart input is the exact unmodified release | `make engine-check` verifies official `HEAD` and rejects tracked SDK changes | Verified |
| Direct public host owns VM/root lifecycle | ARM64 JIT and AOT hosts created roots and completed `Dart_Cleanup` | Verified |
| Direct public host supplies the required Dart runtime contract | JIT and AOT both lacked platform bootstrap and microtasks; ordinary worker lifecycle timed out | Rejected |
| No private Dart bootstrap enters the host | Source audit excludes private headers/helpers; dylib audit confirms required helpers are not exported | Verified |
| Supported in-process topology stays bounded | One stock Engine root, one containing process lifetime, no dynamic hosted workers | Verified |

## Commands

Provision or update the Engine:

```shell
make engine
```

Run all noninteractive regression checks:

```shell
make test
make engine-check
make public-dart-api-host-probe
```

Run the real GUI integration smoke test:

```shell
make example-smoke
```

The generic JIT/AOT host and manifest path are verified from
`examples/hello_window` with:

```shell
dart run dart_macos_runtime:build \
  --manifest macos_application.json --mode developer-jit --run \
  -- --auto-close-after=2
dart run dart_macos_runtime:build \
  --manifest macos_application.json --mode release-aot --run \
  -- --auto-close-after=2
```

The verified smoke output includes:

```text
Dart root isolate is attached to the AppKit main thread.
Timer tick 1 reached Dart.
Timer tick 2 reached Dart.
Timer tick 3 reached Dart.
Automated smoke close requested.
Window close request reached Dart (operation 1).
Window close event reached Dart.
Clean shutdown requested; native handles released.
```

`make run-example` keeps the window open for interactive resize, mouse, and key
testing. Both this project and the nested Dart checkout are Git working trees.
The final audit checks the project diff explicitly; the Engine validation
requires the nested SDK's exact `HEAD` and an empty tracked-source status.

## Next-phase backlog

- Add VM Service and restart only after deciding the desired debugging model.
- Treat AOT, signing, hardened runtime, sandboxing, accessibility, IME,
  clipboard, PTY, and distribution as separate milestones.
- Consider a smaller prebuilt Engine cache for contributors who should not
  carry the approximately 10 GiB source/build workspace.
- Keep product worker IPC, supervision, recovery, and packaging in the
  consuming product rather than adding product-specific behavior here.
