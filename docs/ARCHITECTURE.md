# Architecture

## Runtime ownership

```text
macOS process main thread
└─ NSApplication / AppKit run loop
   ├─ Dart AppKit C ABI bridge
   ├─ official DartEngine JIT shared library
   │  └─ root UI isolate loaded from a full Kernel file
   └─ bounded CFRunLoopSource message pump
```

The native Runner is the real executable. A standalone Dart process is only a
developer-side compiler/launcher and never owns the GUI.

## Startup sequence

1. `main.mm` validates Kernel/version/revision arguments on the process main
   thread and creates `NSApplication`.
2. `applicationDidFinishLaunching` installs the `CFRunLoopSource` scheduler.
3. `DartHost` rejects a non-main thread, checks the linked runtime version and
   build-time source revision, and initializes Dart Engine.
4. The Engine owns the full-Kernel buffer and creates an exited root isolate.
5. The host installs the event poster, acquires the isolate, invokes
   `main(List<String>)`, drains startup microtasks, and returns to AppKit.
6. AppKit remains the outer run loop for the process lifetime.

## Directional boundaries

- Dart → AppKit: synchronous C ABI calls from the root UI isolate. Every UI call
  validates `pthread_main_np()` before touching AppKit.
- AppKit → Dart: delegates encode immutable C object lists and use a Runner-
  installed thread-safe poster backed by `Dart_PostCObject`.
- Dart message notification → AppKit: DartEngine invokes a scheduler callback on
  an arbitrary thread. The callback queues one isolate token per notification
  and signals a `CFRunLoopSource`; it never enters Dart itself.
- Main run loop → Dart: the source drains a bounded number of queued tokens under
  a short wall-clock budget and calls `DartEngine_HandleMessage` once per token.

The production limits are 64 messages or 4 milliseconds per source turn. Work
remaining after either limit resignals the source. A single Dart message cannot
be preempted, so root-isolate handlers must remain short and move CPU-heavy work
to worker isolates.

## State and ownership

Native AppKit objects live in a generation-checked registry. Handles contain a
slot index and generation so a stale Dart object cannot accidentally address a
new native object reusing the same slot. Dart owns the registry handle and must
dispose it explicitly; `NativeFinalizer` only schedules a best-effort main-thread
release. Attaching a view to a window does not transfer or consume its handle.

`NSWindow` retains its content view independently, as normal AppKit ownership.
Closing a window emits an event but does not release its handle, which keeps
event identity stable until Dart explicitly disposes it.

Handles use a one-based slot plus a generation. Generations remain in the
positive signed range so a handle has the same value in `Uint64` FFI calls and
the event envelope's `Int64` field.

## Shutdown

Dart receives `windowClosed`, cancels asynchronous work, disposes its window and
view handles, and asks the bridge to terminate `NSApplication`. Termination is
queued on the main dispatch queue so teardown cannot run inside the initiating
FFI frame.

`applicationWillTerminate` records any live handles, disables event posting and
clears the registry, stops the message pump, then shuts down DartEngine and its
isolates. Unhandled Dart message errors and startup failures return software
error 70; usage and missing-input failures return 64 and 66.

## Developer process and bundle

The outer `dart_appkit:run` process only compiles and launches. It discovers the
application package config and the project-local Engine checkout, validates the
exact SDK/Engine revision, asks Make for a cached native Runner, and compiles a
linked Kernel with the Engine build's matching `bootstrap_gen_kernel.exe` and
development-mode platform Kernel. It then assembles:

```text
DartAppKitRunner.app/Contents/
├─ Info.plist
├─ MacOS/dart_appkit_runner
├─ Frameworks/libdart_engine_jit_shared.dylib
└─ Resources/application.dill
```

The Engine's official install name and the Runner's rpath meet at
`@executable_path/../Frameworks`. The bundle executable inherits the outer
process's stdio and receives SDK metadata plus application arguments directly,
without a shell.

## Deliberate limits

Only the root UI isolate may call AppKit. Worker isolates may compute and do I/O,
but must message the root isolate for UI changes. The MVP does not implement
widgets, layout, Metal, VM Service, hot reload, AOT packaging, signing, sandbox
entitlements, or terminal-specific input/rendering.
