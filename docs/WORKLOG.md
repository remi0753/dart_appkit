# Implementation Worklog

This is the append-oriented evidence log for `ROADMAP.md`. Each completed task
ends with a roadmap checkpoint stating the current position and remaining path.

## 2026-09-03 — T8 started: same-group isolate lifecycle contract

### Purpose and background

Move the general same-process worker guarantee to the host library that owns
Dart Engine initialization and shutdown. A downstream product had temporarily
patched `runtime/engine/engine.cc` so ordinary `Isolate.spawn` children received
core-library initialization and Engine shutdown called VM-wide cleanup. That
product-specific patch application is rejected. A separately tested Engine
correction is still valid when it expresses a general embedder contract and is
managed honestly as an upstream candidate.

The initial evidence is based on stock Dart SDK revision
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. A disposable SDK checkout contains
candidate commit `28462f0fb37` (`Complete Dart Engine isolate lifecycle`), whose
upstream sample regressions passed Release and Product ARM64, JIT and AOT,
shared and static configurations. The candidate has not been reviewed, merged,
or released by Dart maintainers.

### Responsibility boundary

- Dart Engine must install its isolate-initialization callback during
  `Dart_Initialize`, initialize child core libraries consistently with roots,
  keep snapshot URI ownership valid, stop all Engine-owned isolates, call the
  paired VM/embedder cleanup, release loaded snapshots, and make repeated
  shutdown safe.
- `dart_appkit` must keep the UI root on the AppKit main thread, schedule every
  Engine message through its bounded main-run-loop pump, surface message errors,
  order bridge/pump shutdown before Engine shutdown, and prove ordinary Dart
  isolate APIs work in a real hosted application.
- Application code owns child `Isolate`/ports and uses standard Dart lifecycle
  APIs. It must never call AppKit from a worker.

Changing only the AppKit caller cannot safely fill the Engine gap. The
`initialize_isolate` callback is fixed when `DartEngine_Init` initializes the
VM, and the required core setup is private implementation already owned by
`dart_engine`. Likewise, an external `Dart_Cleanup` call cannot be ordered
safely around Engine-owned roots, persistent handles, snapshot buffers, and AOT
libraries. `dart_appkit` will not copy those internals or call cleanup behind
the Engine's ownership boundary.

### Scope, exclusions, and dependencies

T8 covers the candidate Engine commit, `dart_appkit` capability validation,
Runner conformance code/tests, and ownership/build documentation. It excludes
terminal-product behavior, process-worker IPC, broader AppKit APIs, VM Service,
Intel-first optimization, and publishing an upstream review. M1/arm64 is the
primary gate; x86_64 remains compatibility follow-up.

Dependencies are the pinned Dart source checkout, the existing bounded
`DartMessagePump`, `DartHost`, hello-window smoke workflow, and the candidate's
official Engine sample regressions. The current `dart_appkit` worktree and its
nested SDK checkout were clean when T8 began.

### Completion and validation plan

1. Preserve the Engine correction as a normal commit directly atop the pinned
   upstream revision, and verify its exact parent/diff/test provenance.
2. Update Engine configuration checks so base compatibility and candidate
   identity are explicit; stock Engine must fail the new worker-capability gate
   rather than fail later at runtime.
3. Add a minimal hosted Dart conformance app for async child work, error
   containment, live-child final shutdown, and AppKit-main-thread invariants.
4. Run upstream Engine sample tests, strict native/Dart tests, root-only GUI
   smoke, worker GUI smoke, formatting, architecture/symbol checks, and source
   diff review.
5. Record any reproduction dependency that cannot yet be fetched from an
   upstream or fork remote. Do not mark T8 complete while that dependency is
   hidden or while any required test is unavailable.

## 2026-08-31 — T0 started: source design and environment inventory

### Source design distilled

- AppKit/native Runner must own the process main thread and top-level run loop.
- The Runner embeds a Dart VM and starts a root UI isolate from a Kernel program.
- Dart calls AppKit synchronously only from that root isolate through a stable C
  ABI; AppKit events travel asynchronously through a Dart native port.
- Native objects stay behind validated integer handles. Dart exposes explicit
  lifecycle methods, with finalizers only as a safety net.
- The event-loop proof is more important than API breadth: a text window,
  periodic timer, close event, and clean shutdown are the MVP.
- A normal standalone `dart run` plus a dylib is not an acceptable final host,
  because it cannot establish that Dart executes AppKit calls on the macOS main
  thread or that AppKit remains the top-level run loop.

### Local environment observed

- Host architecture: Apple arm64.
- Xcode: 26.6 (build 17F113).
- macOS SDK: the SDK selected by Xcode 26.6.
- Dart executable: `/opt/homebrew/bin/dart`.
- Resolved Dart SDK: `/opt/homebrew/Cellar/dart/3.13.2/libexec`.
- Dart version: 3.13.2 stable, macos_arm64, dated 2026-08-25.
- The SDK includes `include/dart_api.h`, `dart_native_api.h`,
  `dart_tools_api.h`, `dart_api_dl.h`, the Kernel compiler snapshot, and
  `gen_snapshot`/`dartaotruntime` tools.
- The installed SDK does **not** contain `libdart*.dylib` or `libdart*.a` in the
  searched SDK tree. Its `dart` executable itself exports key embedding symbols,
  but a separate native Runner cannot treat that executable as its linkable VM
  library.

### Initial risk made explicit

The design document correctly identifies the first build gate: the regular Dart
SDK distribution provides embedding headers but not necessarily a library that a
third-party native host can link. The implementation will never conceal this by
silently changing to a standalone-Dart architecture. It will:

1. keep the true embedded Runner as the only production architecture;
2. discover and validate an explicitly supplied Dart VM library/snapshot set;
3. keep bridge and Dart API components independently buildable/testable; and
4. fail with a precise remediation message if the local SDK lacks the VM build
   artifact required for the end-to-end Runner.

### Next investigation

Read the installed 3.13.2 embedding headers for exact initialization, isolate,
message-notify, port, and cleanup contracts; inspect local artifacts for usable
snapshot data; then close T0 with a pinned build-input contract.

## 2026-08-31 — T0 completed: pinned engine and scheduling contract

### Revision and artifact findings

- The installed SDK revision is
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. The annotated official
  `3.13.2` tag resolves to the same commit, so source-built runtime artifacts
  can be matched exactly rather than merely by a marketing version.
- Dart 3.13.2 has a new official `DartEngine` layer under `runtime/engine`.
  Its `dart_engine_jit_shared` target is a complete JIT embedding library that
  includes the raw VM, core-library/`dart:io` embedder setup, Kernel ownership,
  isolate locking, and a pluggable per-message scheduler.
- The ordinary released SDK includes neither `dart_engine.h` nor
  `libdart_engine_jit_shared.dylib`. It only includes the lower-level public
  `dart_api.h` family. The engine must therefore come from a matching Dart SDK
  source build or an explicitly supplied compatible artifact.
- The official build source is not suitable for an implicit download during a
  normal application build. Dart's source instructions require a `gclient`
  checkout, and an upstream embedding report measured roughly 15 GB for the
  fetch. This machine currently has roughly 20 GB free, so automatically
  fetching/building it would create an unacceptable disk-exhaustion risk.

### API contracts verified against Dart 3.13.2

- `DartEngine_KernelFromFile` owns the Kernel buffer until engine shutdown;
  this satisfies the raw API's requirement that Kernel bytes remain valid for
  the isolate group's lifetime.
- `DartEngine_CreateIsolate` initializes the VM, creates a Kernel isolate,
  installs message notification, initializes core libraries including
  `dart:io`, sets the root library, and returns with the isolate exited.
- `DartEngine_AcquireIsolate`/`DartEngine_ReleaseIsolate` serialize entry and
  must bracket main-thread calls into Dart.
- The scheduler callback is invoked for each new isolate message and receives
  both the destination isolate and an embedder context. It must eventually
  schedule exactly one `DartEngine_HandleMessage` call for that notification.
- `DartEngine_HandleMessage` handles one message while managing isolate entry,
  API scope, error routing, and the isolate lock.
- `DartEngine_DrainMicrotasksQueue` is required after the host directly invokes
  Dart, because an embedder call does not itself guarantee a microtask drain.
- `Dart_PostCObject` remains the correct thread-safe native-to-Dart event path.
  AppKit delegates must only post messages and must not synchronously invoke a
  Dart function.

### Chosen build-input contract

The native Runner will require these explicit, version-matched inputs:

1. `DART_SDK` — released SDK root used to compile the application's full,
   platform-linked Kernel file and read its `version`/`revision` metadata.
2. `DART_ENGINE_ROOT` — the matching Dart source checkout's `sdk` directory,
   providing `runtime/include/dart_api.h` and
   `runtime/engine/include/dart_engine.h`.
3. `DART_ENGINE_LIBRARY` — the matching arm64 release artifact, normally
   `xcodebuild/ReleaseARM64/libdart_engine_jit_shared.dylib`.

Configuration will compare the released SDK revision to the engine source
checkout revision when metadata is available, verify architecture and required
symbols, and stop with remediation instructions on any mismatch. It will never
switch to `dart run` as the GUI host.

The build will also provide an explicit helper for users who already have a
proper `gclient` checkout. The helper will build only the official
`runtime/engine:dart_engine_jit_shared` target and will never fetch the large
checkout on its own.

### Implementation consequences

- The AppKit bridge itself will not link directly to Dart. It will accept an
  internal event-poster function installed by the Runner. This keeps bridge
  compilation and native contract tests independent of the missing VM artifact.
- The Runner's poster implementation calls `Dart_PostCObject` from the engine
  library.
- Scheduler notifications will enter a thread-safe FIFO, signal a
  `CFRunLoopSource`, and be drained on the macOS main thread under both a count
  and wall-clock budget. Remaining items will resignal the source.
- The Runner executable will export the bridge C symbols so Dart can resolve
  them through `DynamicLibrary.process()`; the bundled Dart Engine dylib will be
  located using an executable-relative rpath.

### Sources consulted

- Dart 3.13.2 installed headers in
  `/opt/homebrew/Cellar/dart/3.13.2/libexec/include`.
- Official Dart SDK 3.13.2 `runtime/engine` header/implementation and
  `samples/embedder` programs at
  <https://github.com/dart-lang/sdk/tree/3.13.2/>.
- Official source/build instructions at
  <https://github.com/dart-lang/sdk/blob/3.13.2/docs/Building.md>.

### Roadmap checkpoint after T0

- Current position: T0 is complete; T1 is now active.
- Evidence against T0 exit criteria: environment inventory, required symbols,
  artifact absence, official engine target, compatibility key, scheduler
  contract, and fail-fast strategy are all recorded above.
- Remaining path to the MVP: scaffold/contracts → native bridge → Dart API →
  native host → run-loop integration → developer command/example → integration
  verification.
- Goal check: the architecture still makes AppKit the process/run-loop root and
  does not compromise the main-thread proof to work around missing artifacts.

## 2026-08-31 — T1 started: scaffold and contract boundary

Created the roadmap-shaped project tree, public C ABI/event protocol,
architecture/build notes, a dependency-free Dart package shell, an example
shell, Make targets, and scripts that validate a revision-matched Dart Engine.

The first C/C++ header compilation exposed a local Xcode 26.6 behavior: invoking
the toolchain's absolute `clang++` path did not discover the macOS SDK's C++
standard library headers. Invoking through `xcrun` worked. The build now resolves
and passes an explicit `-isysroot` path, which is more deterministic for both
Make and subprocess invocation.

## 2026-08-31 — T1 completed: scaffold and ABI contract verified

### Artifacts established

- Created the native bridge/Runner, Dart package, developer executable, example,
  scripts, tests, tool, and documentation tree under the new `dart_appkit/`
  directory.
- Added a Make-based entry point with separate targets for contract validation,
  bridge build/tests, Dart checks, Dart Engine compatibility, and the true native
  Runner.
- Defined ABI version 1, stable status codes, opaque 64-bit handles, UTF-8
  pointer/length semantics, last-error lifetime, main-thread rules, finalizer
  behavior, and all MVP window/text-view functions.
- Defined versioned fixed-position event envelopes for close, resize, mouse, and
  key events, including stable modifier bits and top-left content coordinates.
- Added exact SDK/engine revision, architecture, header, and exported-symbol
  validation. With no engine configured, `make engine-check` fails immediately
  with `DART_ENGINE_ROOT is required` and links to the remediation document.
- Added a helper that builds only an already-fetched, exact-revision Dart source
  checkout's official JIT engine target. It never initiates the multi-gigabyte
  source fetch.

### Verification evidence

- `make validate`: passed.
- Public header syntax check as C11 with warnings as errors: passed.
- Public header syntax check as C++20 with warnings as errors: passed.
- All shell helper syntax checks: passed.
- Scaffold file validation: passed.
- `dart analyze` for the dependency-free package shell: `No issues found!`.
- Expected negative `make engine-check` with missing configuration: failed with
  the intended actionable message and no fallback architecture.

The first sandboxed Dart analysis itself found no source issues but exited after
the analysis because the CLI tried to update its user telemetry file outside the
workspace. Re-running with the normal user configuration permission returned
exit code zero. This is a test-host permission detail, not a project dependency.

### Roadmap checkpoint after T1

- Current position: T1 is complete; T2 is now active.
- Evidence against T1 exit criteria: the complete tree, C/event/ownership
  contracts, deterministic build entry points, actionable configuration failure,
  dual-language ABI compilation, script validation, and Dart analysis all pass.
- Remaining path to the MVP: native bridge → Dart API → native host → run-loop
  integration → developer command/example → integration verification.
- Next task dependency check: T2 can compile and test independently because the
  event poster is injected and no Dart Engine symbols are required.
- Goal check: T2 will add only the minimum AppKit surface needed for the timer,
  text, input, resize, close, and clean-lifecycle proof.

## 2026-08-31 — T2 completed: native AppKit bridge proven

### Native implementation

- Implemented a strong-reference object registry whose 64-bit handles encode a
  32-bit generation and one-based 32-bit slot. Reusing a released slot changes
  the generation, so stale Dart handles cannot resolve to the replacement.
- Implemented thread-local structured errors, status names, main-thread guards,
  finite/positive rectangle validation, strict UTF-8 pointer/length validation,
  and copy-before-return string semantics.
- Implemented an AppKit window owner/delegate, resizable native window, flipped
  custom text view, monospaced text drawing, title/text mutation, content-view
  attachment, show/close operations, and deterministic release cleanup.
- Implemented close, resize, mouse down/up/move/drag, and key down/up conversion
  to the versioned internal event model, including stable modifiers, top-left
  coordinates, repeat state, key code, click count, and UTF-8 character data.
- Implemented the injected thread-safe event sink. It copies the poster/context/
  port under a mutex and invokes the poster outside the lock, preventing lock
  re-entry and keeping this layer independent from the unavailable Dart Engine.
- Implemented `NativeFinalizer` support as an arbitrary-thread entry point that
  only schedules release on the process main queue. It never touches AppKit on
  the finalizer thread.
- Implemented shutdown/test reset that disables future event posting, closes
  windows without emitting teardown events, invalidates handles, and clears the
  registry.

### Build findings and corrections

The first native compile found one strict type mismatch: the local pointer to an
immutable drawing-attributes dictionary was declared `const`, while AppKit's
Objective-C API accepts a normal `NSDictionary*`. Removing the unnecessary
pointer-level `const` fixed the call without weakening the dictionary's runtime
immutability. No registry/ARC/event-model structural errors were reported.

Added a project clang-format configuration and mechanically formatted all C,
C++, and Objective-C++ bridge sources before the final verification.

### Verification evidence

- Objective-C++ bridge and test executable compile under ARC/C++20 with
  `-Wall -Wextra -Wpedantic -Werror`: passed.
- Native test suite result: `all native bridge tests passed`.
- Covered: ABI/status surface, main-thread probe, invalid output pointers,
  invalid geometry, malformed UTF-8, missing event poster, wrong handle kind,
  explicit/duplicate release, generation reuse/stale rejection, worker-thread
  UI rejection, main-queue finalizer release, resize/close event payloads, mouse
  modifiers/clicks, and key UTF-8/repeat/key-code payloads.
- Standalone bridge dylib build: passed as arm64 Mach-O.
- Export audit found all 16 expected `da_*` symbols, including the finalizer and
  debug probes.
- `make validate` after formatting: passed.

### Roadmap adjustment from the T0 architecture decision

The original T2 wording placed direct `Dart_PostCObject` serialization in the
bridge. T0 established that the bridge must remain Dart-independent so it can be
built and proven when the released SDK lacks the Engine library. T2 therefore
ends at a stable `NativeEvent` plus injected poster boundary. The exact
`Dart_CObject` list encoder and `Dart_PostCObject` call belong to the
Engine-linked Runner in T4/T5. This changes component placement, not the public
event protocol or the asynchronous no-re-entry guarantee.

### Roadmap checkpoint after T2

- Current position: T2 is complete; T3 is now active.
- Evidence against T2 exit criteria: warning-clean compilation, native contract
  tests, documented public calls, generation-safe ownership, all MVP AppKit
  operations, and event conversion pass.
- Remaining path to the MVP: Dart API → native host → run-loop/Dart event adapter
  → developer command/example → integration verification.
- Next task dependency check: T3 can test all Dart object/event behavior against
  an injected fake backend without loading a GUI dylib.
- Goal check: the native surface remains intentionally small and already covers
  the window/text/timer-event proof without introducing widgets or rendering
  infrastructure.

## 2026-08-31 — T3 completed: Dart API and FFI verified

### Dart implementation

- Implemented dependency-free low-level bindings using only `dart:ffi`,
  `dart:convert`, and libc `malloc`/`free`. UTF-8 buffers and all native output
  structs are scoped and released with `try/finally`; native error bytes are
  copied before any later bridge call can invalidate them.
- Bound the complete ABI, including struct-by-value `DaRect`, explicit string
  lengths, generation handles, debug probes, and the native finalizer function
  pointer.
- Implemented `AppKitApplication.attach()` with ABI equality, root-isolate main-
  thread verification, `ReceivePort.nativePort` registration, idempotent attach,
  event decode errors, and orderly subscription/port termination.
- Implemented the intended `Rect`, `TextView`, and `Window` API, native error
  exceptions, explicit idempotent disposal, use-after-dispose protection,
  content-view ownership checks, cached title/text, application/window streams,
  and typed close/resize/mouse/key events.
- Attached a `NativeFinalizer` to every native resource and detach it only after
  successful explicit release. Window routing uses `WeakReference<Window>` so
  the application event router does not accidentally keep abandoned windows
  alive and defeat finalization.
- The window keeps its current `TextView` strongly reachable on the Dart side,
  matching AppKit's native ownership while preserving a usable update object.

### Termination safety correction

While wiring `AppKitApplication.terminate`, it became clear that calling
`[NSApp terminate:]` synchronously inside a Dart FFI invocation could run the App
delegate's engine teardown before the current Dart message releases its isolate
lock. The bridge now queues normal application termination onto the main dispatch
queue. The FFI call returns, Dart finishes the current message/microtasks, and
only then can AppKit begin native shutdown. This preserves the no-re-entry and
no-shutdown-while-entered invariants.

### Test/build findings

- The first analyzer pass after adding package imports reported unresolved
  `package:` URIs because the new dependency-free package had not generated
  `.dart_tool/package_config.json`. `dart pub get` generated only local package
  metadata; no third-party dependency was added. Subsequent analysis exposed no
  source errors.
- A large initial patch was rejected atomically before modifying files because
  it attempted to delete and add the same path in one patch transaction. The
  change was split into normal updates/additions; no partial state had to be
  recovered.

### Verification evidence

- `dart analyze`: `No issues found!` under strict casts/inference/raw types and
  the selected lifecycle/async lints.
- Fake-backend tests all passed:
  - ABI and main-thread attach rejection;
  - text/window creation, mutation, attachment, show/close, live counts;
  - native status/message exception conversion;
  - explicit/duplicate disposal and finalizer attach/detach;
  - versioned close/resize/mouse/key decoding and weak window routing;
  - malformed event error surfacing; and
  - cross-application native-resource rejection.
- A real-dylib FFI smoke test loaded the arm64 bridge, read ABI version 1, called
  the main-thread probe, crossed the struct-by-value window function boundary,
  and copied the native failure message successfully.
- The smoke test measured standalone `dart run` as `mainThread=0` on this host.
  This is direct evidence that a dylib-only standalone architecture cannot meet
  AppKit's root-main-thread requirement.
- Full local `make test`: scaffold validation, native tests, Dart analysis,
  fake-backend tests, and real-dylib FFI smoke all passed.

### Roadmap checkpoint after T3

- Current position: T3 is complete; T4 is now active.
- Evidence against T3 exit criteria: strict analysis, dependency-free unit
  tests, real ABI smoke, typed stream routing, explicit/finalizer lifecycle, and
  the design-document API shape all pass.
- Remaining path to the MVP: native host → run-loop/Dart event adapter →
  developer command/example → integration verification.
- Next task dependency check: T4 source can be warning-compiled against the
  released `dart_api.h` plus an exact declaration-only DartEngine 3.13.2 test
  header; final linking still requires the explicit engine artifact from T0.
- Goal check: the API now expresses exactly the text/timer/close flow and rejects
  the empirically invalid standalone-main-thread execution mode.

## 2026-08-31 — T4 implementation completed: native Runner and Kernel host

### Runner implementation

- Added a native `NSApplication` entry point with strict parsing for Kernel,
  SDK version, SDK revision, and forwarded application arguments. Usage errors
  return 64, a missing Kernel returns 66, and host/VM failures return 70.
- Added an App delegate that starts the message pump and Dart host only from
  `applicationDidFinishLaunching`, keeps AppKit's run loop authoritative,
  activates the process after Dart startup, and performs idempotent teardown
  from `applicationWillTerminate`.
- Added a `DartHost` that verifies the runtime version and exact build revision,
  initializes Dart Engine, reads the full Kernel snapshot, creates the root
  isolate, invokes typed `main(List<String>)`, drains startup microtasks, and
  converts startup/message errors into deterministic native termination.
- Both the host and message pump check `pthread_main_np()` before starting.
  Dart isolate entry is scoped through the Engine's acquire/release API; AppKit
  delegates never synchronously enter Dart.
- Added exact `Dart_CObject` serialization for the versioned close, resize,
  mouse, and key envelopes. AppKit reaches only an injected poster, while the
  Engine-linked host owns the `Dart_PostCObject` boundary.
- Teardown disables new native events, reports live native handles, invalidates
  the bridge registry, stops scheduled message work, and finally shuts down the
  Dart Engine. Normal Dart-requested termination remains queued so Engine
  teardown cannot occur inside the initiating FFI frame.

### Official API reconciliation and correction

- Compared the declarations and implementation with the exact installed SDK
  revision `60a57cd42d64dc03e9f07aa60a2e250755c1ef28` in Dart's official source.
  `DartEngine_CreateIsolate` initializes the Engine lazily, but a failed
  isolate creation can still leave Engine state and an owned Kernel buffer.
- Changed the host to call `DartEngine_Init` explicitly and mark Engine
  ownership before loading/creating the isolate. Every later failure now calls
  `Shutdown`, so partial initialization and Kernel buffers are not abandoned.
- The official Engine header deliberately contains anonymous union structs.
  Runner targets suppress only Clang's two extension diagnostics for this
  third-party ABI declaration while retaining all other warnings as errors.
- The released SDK root contains a plain file named `version`, which shadowed
  libc++'s `<version>` when used as a normal include directory. Syntax checks
  now use a quote-only SDK search path, preserving the official
  `"include/dart_api.h"` layout without polluting system-header lookup.

### Verification evidence and external gate

- `make runner-syntax`: passed under ARC, C++20, macOS 13 deployment target,
  `-Wall -Wextra -Wpedantic -Werror`, the released 3.13.2 public headers, and an
  exact declaration-only copy of the 3.13.2 Engine API.
- The source contains independent main-thread guards in both startup layers,
  revision/version checks before VM ownership, and distinct usage/input/software
  process exit codes.
- A real Runner link and Kernel execution remain unavailable locally because
  the released SDK ships no `libdart_engine_jit_shared.dylib`. This is the
  already-recorded T0 artifact gate; `make runner` continues to fail fast unless
  callers provide a matching source checkout and Engine library. Runtime
  confirmation that the Kernel sees the process main thread is retained as a
  mandatory T7 integration check.

### Roadmap checkpoint after T4

- Current position: T4 implementation is complete; T5 is now active.
- Evidence against the locally satisfiable T4 criteria: warning-clean pinned
  API compilation, explicit Engine lifecycle cleanup, root-main-thread guards,
  full-Kernel root invocation, structured error propagation, and sysexits-style
  failure codes are present.
- Remaining path to the MVP: bounded run-loop integration → developer command
  and timer example → full local verification plus the explicitly gated Engine
  smoke run.
- Next task dependency check: T5 can prove its queue, main-thread handling,
  ordering, stop behavior, and bounded batches with a fake Engine handler; the
  real port/timer observation remains part of the same T7 artifact gate.
- Goal check: AppKit still owns the process thread and run loop. The next change
  is solely about fairness between AppKit work and Dart messages, not expanding
  the widget surface.

## 2026-08-31 — T5 started: bounded run-loop integration plan

Implementation order for this task:

1. Replace the temporary `dispatch_async`-per-message adapter with a FIFO that
   accepts Engine scheduler notifications from arbitrary threads without
   entering Dart.
2. Own a `CFRunLoopSource` in the main run loop's common modes. A scheduler
   callback only enqueues, signals the source, and wakes the run loop.
3. Drain exactly one `DartEngine_HandleMessage` call per queued notification,
   stopping each run-loop turn after 64 messages or 4 milliseconds, whichever
   comes first. At least one message may run because native calls cannot be
   preempted once entered.
4. Resignal when FIFO work remains so AppKit gets a scheduling opportunity
   between Dart batches. Stop must invalidate the source, clear pending work,
   and make later callbacks harmless.
5. Add an injected fake-handler test covering non-main start rejection,
   arbitrary-thread enqueue, FIFO order, main-thread handling, message and time
   budgets, multiple turns under a burst, and stop behavior. Then run the whole
   locally available suite before the T5 roadmap checkpoint.

The real Engine remains outside this unit-test boundary: production defaults
to `DartEngine_HandleMessage`, while tests inject a deterministic handler. This
tests the scheduling contract without pretending to validate Kernel/timer
execution in the absence of the T0 Engine artifact.

## 2026-08-31 — T5 implementation completed: bounded Dart scheduling

### Run-loop implementation

- Replaced one `dispatch_async` block per Engine notification with a mutex-
  protected FIFO and a single manual `CFRunLoopSource` installed in the main
  run loop's common modes.
- The Engine callback is safe on arbitrary threads and performs no Dart or
  AppKit work. It copies one isolate token into the FIFO, signals the source,
  and wakes the main run loop. The source alone invokes the Engine handler.
- Each source turn handles at most 64 notifications or 4 milliseconds of work.
  It removes one token for each `DartEngine_HandleMessage` call, preserving the
  Engine API's one-message contract. Native handling is non-preemptive, so a
  single slow message may exceed the time budget; no second message begins once
  the elapsed limit is observed.
- Remaining work resignals the source instead of draining recursively, giving
  AppKit a run-loop scheduling opportunity between batches. Notifications that
  arrive during a drain cannot be lost because enqueue independently signals
  the same source.
- Core Foundation references are retained while cross-thread signaling occurs.
  Stop atomically rejects later notifications, clears pending tokens, detaches
  and invalidates the source, and releases the run-loop references.
- Added internal debug counters for accepted notifications, handled messages,
  turns, resignals, largest batch, and longest observed turn. These are test
  instrumentation only and do not expand the Dart package API.

### Verification evidence

- A fake Engine handler received a 200-notification worker-thread burst in
  exact FIFO order, entirely on `pthread_main_np() != 0`.
- With a seven-message test limit, no turn exceeded seven messages and at least
  29 drain turns were required; remaining work was explicitly resignaled.
- With a 1 ms time limit and a deliberately 400 microsecond handler, an
  18-message burst split across multiple turns before the much larger message
  cap, proving the elapsed-time path.
- Tests also passed for non-main startup rejection, invalid zero limits,
  idempotent start, empty queue completion, and ignored callbacks after stop.
- Full `make test` after the change passed: scaffold/contracts, native AppKit
  bridge tests, Runner strict syntax, message-pump tests, strict Dart analysis,
  Dart API tests, and real bridge-dylib FFI smoke.

### Deferred observable behavior

The exact native-event `Dart_CObject` encoder is now connected to
`Dart_PostCObject`; the Dart-side decoder and all close/resize/mouse/key shapes
already pass T3 tests. Visible UI manipulation, periodic `Timer` progress, and
close-to-process-exit still require a real 3.13.2 Engine link. They are retained
as T7 gates and will not be reported as runtime-tested in this environment.

### Roadmap checkpoint after T5

- Current position: T5 implementation is complete; T6 is now active.
- Evidence against locally satisfiable T5 criteria: arbitrary-thread notify,
  no synchronous Dart re-entry, main-run-loop source ownership, FIFO ordering,
  two independent budgets, resignal, safe stop, and full regression tests pass.
- Remaining path to the MVP: developer command and timer example → complete
  regression/audit → Engine-backed run when its explicitly validated artifact
  is available.
- Next task dependency check: T6 can compile a full Kernel with the installed
  SDK and test all launcher validation/caching/bundle assembly paths. Only the
  final Runner link/launch correctly remains conditional on `DART_ENGINE_*`.
- Goal check: the event-loop proof now has a bounded native mechanism. T6 must
  expose it through one reproducible command without adding hot reload, VM
  Service, or broader UI abstractions.

## 2026-08-31 — T6 started: launcher and example plan

### Confirmed compiler/tool contract

- Dart 3.13.2 supports `dart compile kernel -o <output>
  --packages=<package_config.json> <entrypoint>` and links the platform Kernel
  by default. The launcher will pass `--link-platform` explicitly so the
  embedded Engine never depends on an implicit compiler default.
- The active executable resolves to an SDK containing `version` = `3.13.2` and
  `revision` = `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.
  Both values will be passed to the Runner and rechecked before isolate start.
- Runtime package lookup is unnecessary for the MVP because the compiler emits
  a full linked Kernel. The package config is a compile input and must exist in
  the application's `.dart_tool` directory.

### Planned command behavior

1. Parse `dart run dart_appkit:run [options] <entrypoint.dart> [-- app args]`.
   Support `--help`, an optional `--build-dir`, and explicit
   `--engine-root`/`--engine-library` overrides; environment variables remain
   the default configuration source.
2. Resolve the entrypoint and build directory against the caller's current
   directory, discover its nearest `.dart_tool/package_config.json`, resolve
   this package's repository root, and derive the SDK root from
   `Platform.resolvedExecutable`.
3. Fail before compilation when macOS, entrypoint, package config, SDK metadata,
   Engine checkout, or Engine library is absent. Error text must name the
   missing input and the Engine build document.
4. Compile a full Kernel plus depfile into the application-local cache. Let the
   compiler use its own dependency information; native products live under an
   SDK-revision cache directory and Make rebuilds only changed inputs.
5. Invoke the repository Make target with explicit SDK, Engine root/library,
   and build directory. Assemble a minimal `.app` containing the Runner,
   revision-matched Engine dylib, Kernel, and `Info.plist`.
6. Execute the bundle's binary directly with inherited stdin/stdout/stderr,
   passing Kernel/version/revision and all arguments after `--`; propagate its
   exact exit status.
7. Keep CLI parsing/process execution testable through an injected executor.
   Add tests for help/usage, path discovery, missing configuration, compiler
   failure, command construction, bundle contents, argument forwarding, and
   exit-code propagation. Add the real timer/close example and compile its
   Kernel with the installed SDK even when the final native link is gated.

## 2026-08-31 — T6 implementation completed: one-command workflow

### Launcher implementation

- Replaced the executable placeholder with
  `dart run dart_appkit:run [options] <entrypoint.dart> [-- arguments...]`.
  Help, `--build-dir`, `--engine-root`, and `--engine-library` are supported;
  Engine flags override the corresponding environment variables.
- The tool resolves its own repository through the Dart package URI, resolves
  the application entrypoint against the caller, walks upward to the nearest
  `.dart_tool/package_config.json`, and derives the exact SDK from
  `Platform.resolvedExecutable`. All existing files and directories are
  canonicalized before use.
- macOS, source suffix, package config, SDK metadata, Engine headers/library,
  and project Makefile are validated before external work. Missing Engine
  configuration returns 69 with a direct reference to the build document;
  usage, OS/process, I/O, compiler, Make, and Runner failures retain meaningful
  categories or the child process's exact exit status.
- Native output is cached by SDK revision and a stable hash of the canonical
  Engine library path. Make is still invoked on each run but recompiles the
  Runner only when its source/header/Makefile/Engine-library inputs changed.
- The installed SDK compiles the application with explicit `--link-platform`,
  its discovered package config, and a depfile. The resulting app bundle holds
  `Contents/MacOS/dart_appkit_runner`, the Engine under its official
  `@rpath/libdart_engine_jit_shared.dylib` name, the full Kernel under
  `Contents/Resources`, and a minimal `Info.plist`.
- The bundle executable inherits stdin/stdout/stderr. Kernel path, SDK version,
  exact SDK revision, and every post-`--` argument are passed without shell
  interpolation; the Runner's exact exit code becomes the command's exit code.
- Engine validation now checks all DartEngine symbols used by the Runner and
  verifies the official macOS install name before linking. The Make target also
  depends on its Makefile and Engine dylib, closing two stale-cache paths.

### Hello-window application

- Added the real example entrypoint. It attaches on the root main isolate,
  creates a text view/window, updates visible text every second with
  `Timer.periodic`, logs resize/mouse/key input, and waits for the native close
  event.
- On close (or event-stream error), it cancels the Timer and subscription,
  explicitly disposes window and view handles, requests queued native
  termination, and logs the clean-shutdown milestone.
- Its first runtime line states that attach succeeded on the AppKit main thread;
  `AppKitApplication.attach` can only reach that line after the native
  `pthread_main_np` check succeeds.

### Verification evidence

- Real `dart run dart_appkit:run --help`: exit 0 with the documented usage.
- Real invocation with deliberately missing Engine paths: exit 69 before Make
  or compilation, naming the missing path and remediation document.
- Launcher tests passed for option parsing, path canonicalization, SDK/Engine
  forwarding, full Kernel command, cache directory, all `.app` contents,
  rpath-name placement, inherited stdio, argument ordering, exact Runner exit,
  missing Engine/package config, and injected Make/compiler failures.
- `dart analyze` reports no issues for both the package and example.
- The real Dart 3.13.2 compiler produced an 8.3 MB linked hello-window Kernel
  plus a depfile listing the example and package sources.
- `make test` now includes scaffold/native/Runner syntax/message-pump/Dart API/
  launcher/example analysis/example Kernel/real FFI smoke checks; the complete
  target passed.

### Roadmap checkpoint after T6

- Current position: T6 implementation is complete; T7 is now active.
- Evidence against locally satisfiable T6 criteria: the user-facing executable,
  full Kernel generation, Make input cache, bundle assembly, argument and stdio
  forwarding, child exit propagation, actionable validation, and Timer/close
  example are implemented and tested.
- Remaining path to the MVP: final requirement/ownership/security audit,
  documentation reconciliation, all-check rerun, and the Engine-backed visible
  smoke command if the external artifact is supplied.
- Next task dependency check: every source component is present. T7 needs no new
  product surface; it should fix only audit findings and distinguish verified
  behavior from the external runtime gate.
- Goal check: the documented command now reaches exactly the designed native
  Runner architecture. It never falls back to launching AppKit from standalone
  `dart run`, whose non-main thread was measured in T3.

## 2026-08-31 — T7 started: final audit findings

The first full source/document audit found no change to the chosen architecture
and no locally observed regression. It identified these bounded cleanup items:

1. Native handles are unsigned 64-bit values, while the event envelope uses a
   `Dart_CObject_kInt64`. Current handles are small, but an unconstrained 32-bit
   generation could theoretically set the sign bit after billions of slot
   reuses and make Dart reject the event handle as negative. Keep generations
   in the positive signed 31-bit range and add a contract assertion.
2. Runner usage/input codes exist in `main.mm`, but argument parsing is inside
   that Engine-linked translation unit. Extract the parser into an Engine-free
   component and test required values, unknown options, delimiter forwarding,
   duplicates, and published exit constants directly.
3. Root/Runner/tool/test documentation still describes portions as scaffolding
   and does not show the finished one-command workflow, bundle layout, budgets,
   or exact verified-vs-gated boundary. Reconcile these and add a final
   verification matrix.
4. `docs/C_ABI.md` says a failed event post is logged, while delegates currently
   drop it without blocking or synchronous Dart entry. Correct the text rather
   than adding potentially noisy logging during startup/shutdown.
5. `/Users/remi/dart` is not a Git working tree, so a Git dirty-file audit is
   unavailable. Filesystem inventory, generated-file exclusions, formatting,
   and isolated clean-build checks will be used instead and this limitation
   will remain visible.

The official 3.13.2 `NativeFinalizer` contract was also rechecked locally: both
the value and detach key are weak for reachability purposes and may be the same
object. The package's same-object detach key therefore does not keep abandoned
native resources alive. Its callback only queues a main-thread release and does
not call a Dart C API, matching the native-finalizer restriction.

## 2026-08-31 — T7 completed: audit, documentation, and clean verification

### Audit corrections

- Limited registry generations to the positive 31-bit range. Combined with the
  32-bit one-based slot, every generated `DaHandle` remains positive when
  serialized through `Dart_CObject_kInt64`; native tests assert this contract.
- Extracted Runner argument handling into an Engine-free component. It now
  resets output configuration, rejects invalid/null vectors, empty and duplicate
  values, unknown options, and preserves every argument after `--`.
- Added direct parser tests and a full Runner shell-link target. The shell build
  uses delayed unresolved Dart symbols only for testing and executes code paths
  that return usage 64 and missing-Kernel 66 before any VM call. Production
  `make runner` still requires and links the validated Engine dylib normally.
- Pinned both pub packages to `>=3.13.2 <3.14.0`; the launcher, Engine validator,
  and Engine build helper explicitly reject an SDK version other than 3.13.2.
  Exact revision equality remains a separate stronger check.
- Expanded Engine validation to include every DartEngine symbol used by the
  host and the official `@rpath/libdart_engine_jit_shared.dylib` install name.
- Reconciled root, architecture, ABI, Engine, Runner, bridge, tooling, example,
  and test documentation. Added `docs/VERIFICATION.md` as the concise
  verified-versus-gated handoff.

### Final isolated-build evidence

Ran the complete suite with a newly created, empty output directory:

```text
make BUILD_DIR=/private/tmp/dart_appkit_release.n6uHWG test
```

Results:

- scaffold and all shell syntax: passed;
- C11/C++20 ABI headers: passed;
- warning-as-error AppKit bridge build and native tests: passed;
- strict Runner source compilation: passed;
- Runner parser tests: passed;
- full pre-VM Runner shell link plus exits 64/66: passed;
- arbitrary-thread/bounded-run-loop message-pump tests: passed;
- Dart package analysis and API tests: passed;
- launcher validation, bundle, forwarding, and failure tests: passed;
- hello-window analysis and real full-Kernel compile: passed;
- real bridge-dylib FFI smoke: passed, again measuring standalone Dart as
  `mainThread=0`.

The clean bridge dylib is arm64 and exports all 16 expected public `da_*`
symbols. The clean linked hello Kernel is approximately 8.3 MB and its depfile
lists the example and package sources. Both generated pub locks now constrain
Dart to `>=3.13.2 <3.14.0`. A repository-wide stale-marker search found no
remaining scaffold placeholder, TODO/FIXME, or old broad SDK constraint outside
this historical worklog.

`make engine-check` without an external artifact still fails immediately with
`DART_ENGINE_ROOT is required` and points to the Engine build document. This is
the intended behavior, not a silently skipped test.

### Final roadmap checkpoint after T7

- Current position: T0 through T7 are complete for all locally executable work.
- MVP source delivered: native AppKit ownership, exact Dart Engine host path,
  bounded scheduler, stable C ABI, Dart lifecycle/events, launcher/bundle, and
  Timer/close example.
- Outstanding external acceptance: real Engine link, Kernel-observed main
  thread, visible Timer/UI fairness, and close-to-zero-handle exit. These are the
  four `Gated` rows in `docs/VERIFICATION.md` and have not been relabeled as
  verified.
- Workspace limitation: `/Users/remi/dart` is not a Git working tree, so no Git
  status/diff evidence exists; a 66-file source inventory and isolated build
  were used instead.
- Next milestone: provide the revision-matched 3.13.2 Engine dylib and run the
  exact acceptance command in `docs/VERIFICATION.md`. No broader feature should
  begin before those observations close.

## 2026-08-31 — Pinned Engine bootstrap and real GUI acceptance completed

The earlier external-artifact gate above is now closed.

### Bootstrap implementation and artifact evidence

- Added `scripts/bootstrap_dart_engine.sh` as the complete provisioning path.
  It derives the active SDK, requires version 3.13.2 and revision
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`, configures the official Dart
  gclient solution, performs a history-free sync, rejects tracked changes,
  verifies origin and `HEAD`, builds the official JIT shared target, and runs
  compatibility validation.
- Added project-local defaults through `scripts/dart_engine_env.sh`, the
  Makefile, and the Dart launcher. Normal project commands now need no manual
  Engine exports. The bootstrap also writes
  `.dart_tool/dart-engine/env.zsh` for ad-hoc shell commands.
- The official checkout and build occupy approximately 10 GiB. The resulting
  `libdart_engine_jit_shared.dylib` is a 36 MB arm64 Mach-O dylib. Symbol,
  architecture, install-name, header, SDK revision, Kernel compiler, and
  platform Kernel validation all passed.
- The first Engine build compiled 1,193 Ninja actions in 244.651 seconds. A
  second bootstrap completed safely, regenerated the same configuration, and
  reported `ninja: no work to do`, proving the incremental path.

### Real-runtime finding and correction

The first real Runner linked successfully but isolate creation rejected
`dart:io::_NetworkProfiling`. Although the released SDK and Engine source had
the same Git revision, `dart compile kernel` linked the released SDK's product
platform Kernel. The release JIT Engine initializes development-mode
`dart:io` entry points, so that Kernel did not retain the native entry point.

The official Dart embedder samples compile Kernel snapshots with the Engine
build's `bootstrap_gen_kernel.exe` and matching `vm_platform.dill`. The launcher
now follows that contract, including the SDK hash and non-product defines.
Engine validation requires both companion artifacts, preventing the invalid
combination from recurring. The Runner deployment target and generated app
metadata were also aligned with the Engine's macOS 14 minimum.

### Final runtime evidence

`make example-smoke` displayed the real AppKit window and exited 0 with:

```text
Dart root isolate is attached to the AppKit main thread.
Application arguments: --auto-close-after=3
Automated close scheduled after 3 seconds.
Timer tick 1 reached Dart.
Timer tick 2 reached Dart.
Timer tick 3 reached Dart.
Automated smoke close requested.
Window close event reached Dart.
Clean shutdown requested; native handles released.
```

A second direct launch explicitly removed every `DART_ENGINE_*` variable and
also attached, ticked, closed, released, and exited 0, verifying default
discovery. The full `make test` regression suite passed afterward. The four
formerly gated Engine rows in `docs/VERIFICATION.md` are now verified.
