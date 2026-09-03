# Architecture

## Runtime ownership

```text
macOS process main thread
└─ NSApplication / AppKit run loop
   ├─ Dart AppKit C ABI bridge
   ├─ official DartEngine JIT shared library
   │  └─ single root UI isolate loaded from a full Kernel file
   └─ bounded CFRunLoopSource message pump
```

The native Runner is the real GUI executable. Its Dart SDK checkout must remain
at the exact published revision with no tracked source changes. A standalone
Dart process used by this repository is only a developer-side compiler/launcher
and never owns the GUI. A consuming product may run compute workers in separate
official Dart JIT or AOT processes, but that process protocol is outside
`dart_appkit` and no worker process may call AppKit.

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
be preempted, so root-isolate handlers must remain short. Consumers that need
dynamic background workers must move that work across an explicit process
boundary rather than spawning hosted in-process isolates.

## Native event protocol

The event protocol is negotiated independently from `DA_ABI_VERSION`. The
original `da_application_set_event_port` entry point remains a compatibility
API and selects version 1. Current clients call the additive versioned entry
point with an inclusive supported range; the bridge selects the highest common
version and clears the registration if the ranges do not overlap.

Version 1 remains
`[version, type, source_handle, monotonic_micros, ...payload]`. Versions 2
through 4 use
`[version, type, source_handle, source_generation, monotonic_ns, operation_id,
...payload]`. Version 3 adds window focus, visibility, occlusion,
backing-scale, and screen events. Those types are suppressed before posting to
a version-1/2 sink. Version 4 adds application active/reopen/termination,
user-close request, and menu-action records; these are suppressed for v1-v3.
Application records use source handle/generation zero. Registry-sourced records
carry a generation matching the handle's high 32 bits. Notifications use
operation ID zero, while deferred close and termination requests carry a
positive reply identity. The Dart decoder accepts all four versions, preserves
the existing `monotonicMicros` API, and exposes exact negotiated metadata.

The internal event model stores nanoseconds. A version-1 serializer converts
to microseconds only while posting, so an old Dart client receives its original
field order and timestamp unit. The Runner owns the shared encoder; consuming
AOT hosts use the same encoder to prevent JIT/AOT wire drift.

After `makeKeyAndOrderFront:`, the window owner posts one deduplicated snapshot
of key focus, normalized visibility, occlusion, backing scale, and associated
screen. Delegate callbacks post later transitions. Visibility means
`isVisible && !isMiniaturized`; occlusion independently means that
`NSWindowOcclusionStateVisible` is absent. Screen events carry an explicit
presence bit, the unsigned `NSScreenNumber` value widened to 64 bits, and full
plus visible frames in global AppKit point coordinates.

Event-port registration posts an application-active snapshot, after which
AppDelegate posts active/resign and reopen transitions. User close and
termination decisions remain synchronous inside AppKit only long enough to
return `NO`/`NSTerminateLater`; Dart is never entered from the delegate. An
opted-in target holds one positive operation ID until Dart replies. A duplicate
delegate request is coalesced, a stale reply is rejected, and posting failure
allows the OS action. Programmatic close/termination bypass this deferral so
the ordinary disposal and shutdown path remains one-way.

## Hosted-isolate boundary

The stock Dart 3.13.2 Engine contract used here supports one process-lifetime
root UI isolate. It does not expose an individual-root retirement operation,
and its VM initialization does not register the platform initializer needed by
ordinary child isolates. Consequently, `dart_appkit` does not promise
`Isolate.spawn`, `Isolate.run`, or multiple `DartEngine_CreateIsolate` roots
as a worker topology.

A complete host built directly on the public `dart_api.h` surface was tested in
both ARM64 JIT and AOT. VM/root creation and cleanup worked, but the public
surface could not initialize `Platform.script`, microtasks, or ordinary worker
lifecycle. Completing those facilities requires unexported Dart
`runtime/bin` bootstrap code. This project does not call, copy, patch, or fork
that implementation. The negative proof is reproducible with
`make public-dart-api-host-probe` and is recorded in `VERIFICATION.md`.

## State and ownership

Native AppKit objects live in a generation-checked registry. Handles contain a
slot index and generation so a stale Dart object cannot accidentally address a
new native object reusing the same slot. Each occupied slot also records its
owning thread domain. Ordinary lookup checks the requested domain and actual
caller; a handle integer alone does not grant cross-thread access.

Dart owns the registry handle and must dispose it explicitly. Synchronous
`da_release` remains main-thread-only. `da_release_async` is safe on any thread:
it atomically claims one live generation, changes it to release-pending, and
queues completion on the AppKit main domain. Pending handles are invalid for
new access but continue retaining and counting the object and cannot be reused.
`NativeFinalizer` uses this same claim path rather than scheduling a competing
synchronous release. Attaching a view to a window does not transfer or consume
its handle.

`NSWindow` retains its content view independently, as normal AppKit ownership.
Closing a window emits an event but does not release its handle, which keeps
event identity stable until Dart explicitly disposes it.

`View` is the reusable content-view base. Native `DaTextView` subclasses
`DaView`, and the registry records the two actual kinds separately. A text-view
handle satisfies a generic-view lookup, while a generic view never satisfies a
text-only lookup. `Window.contentView` borrows either kind and retains its Dart
wrapper without transferring the registry lease.

Handles use a one-based slot plus a generation. Generations remain in the
positive signed range so a handle has the same value in `Uint64` FFI calls and
the event envelope's `Int64` field. A slot that exhausts that range is retired
instead of wrapping.

## Shutdown

Dart receives `windowClosed`, cancels asynchronous work, disposes its window and
view handles, and asks the bridge to terminate `NSApplication`. Termination is
queued on the main dispatch queue so teardown cannot run inside the initiating
FFI frame.

`applicationWillTerminate` closes asynchronous-release admission, records both
live and release-pending handles, disables event posting, and performs their
remaining AppKit teardown before clearing the registry. A main-queue callback
that was already queued observes closed admission and becomes a no-op. The
Runner then stops the message pump and shuts down DartEngine and its single
root isolate. The stock Engine API has no supported VM restart contract for
this host, so final VM-global cleanup is the containing process exit.
Shutdown is therefore process-lifetime and `dart_appkit` never starts a second
root after shutdown. Unhandled Dart message errors and startup failures return
software error 70; usage and missing-input failures return 64 and 66.

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

Only the single root UI isolate may call AppKit. In-process worker isolates are
not a supported feature of the pinned stock Engine host. A consuming product is
responsible for any official-Dart worker processes, IPC, recovery, and
packaging; workers must send results back to the UI process for AppKit changes.
The MVP does not implement widgets, layout, Metal, VM Service, hot reload, AOT
GUI packaging, signing, sandbox entitlements, or terminal-specific
input/rendering.
