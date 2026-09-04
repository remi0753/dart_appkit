# Dart AppKit Embedder — MVP Roadmap

## Goal

Build the smallest macOS host in which AppKit owns the process main thread and
run loop, a Dart root isolate runs in that host, Dart calls AppKit through a C
ABI, AppKit posts events to a Dart port, and `Timer` work continues while the
window remains responsive.

The MVP is intentionally limited to one simple text view, basic window events,
debug/JIT Kernel execution, and a restart-based developer workflow.

## Working protocol

1. Work on exactly one roadmap task at a time.
2. Record facts, decisions, commands, and verification results in
   `docs/WORKLOG.md` as they are discovered.
3. On completing a task, update its checkbox and the **Current position** below.
4. Re-read the next task, its dependencies, and the MVP goal before starting it.
5. Do not mark a task complete unless its stated exit criteria have evidence in
   the worklog.

## Current position

- Active task: **none; the native capability loading proof is complete**
- Completed: **T0, T1, T2, T3, T4, T5, T6, T7, T8, T9, T10**
- Engine acceptance gate: **official source only**. Dart Engine source changes,
  candidate commits, and downstream patches are prohibited. The stock Dart
  3.13.2 Engine is pinned at revision
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.
- Verified baseline: root-main-thread execution, periodic Timer work, native
  close delivery, handle release, and process exit 0.
- Selected topology: one stock Engine root for the AppKit process lifetime.
  The full public `dart_api.h` host was rejected by M1/arm64 JIT and AOT
  evidence because required platform/microtask bootstrap is private.
- Next concrete milestone: consuming products move terminal rendering and PTY
  adapters into independent capability packages using this loading contract.

## Detailed tasks

### [x] T0 — Feasibility and environment gate

Scope:

- Inventory macOS architecture, Xcode/macOS SDK, Dart SDK revision, embedding
  headers, VM artifacts, Kernel compiler, and package configuration behavior.
- Inspect the installed `dart_api.h` contracts required for VM initialization,
  isolate creation, message notification, port posting, and shutdown.
- Decide the exact native build inputs and fail-fast behavior when an
  embeddable VM library is unavailable.
- Record risks and the chosen architecture before implementation.

Exit criteria:

- `docs/WORKLOG.md` contains a reproducible environment inventory.
- Required Dart embedding symbols and artifacts are listed.
- The build strategy is explicit and does not silently fall back to running
  AppKit on a non-main thread.

### [x] T1 — Project scaffold and contracts

Scope:

- Create the native runner/bridge, Dart package, developer tool, example, test,
  script, and documentation directories.
- Add a deterministic build entry point and configuration discovery.
- Define the public C ABI types, status codes, ownership rules, and event wire
  format.
- Add repository hygiene and contributor-facing build instructions.

Exit criteria:

- The tree and contracts match the architecture in the design document.
- Configuration validation gives actionable errors.
- Format/static checks for the initial scaffold pass.

### [x] T2 — Native AppKit bridge

Scope:

- Implement a main-thread guard and a strong-reference object registry using
  generation-safe integer handles.
- Implement application event-port registration, window create/show/close/title
  operations, text-view create/update, content-view attachment, and release.
- Implement window close/resize, mouse, and key events as the stable internal
  event model consumed by the Runner-injected poster, without synchronously
  re-entering Dart. The Engine-linked poster performs `Dart_PostCObject`
  serialization in T4/T5.
- Add native tests for handle validity, stale handles, UTF-8 validation,
  ownership, and event encoding where those tests do not require a visible UI.

Exit criteria:

- The bridge compiles with warnings treated as errors.
- Native contract tests pass.
- Every public function documents thread, ownership, and error behavior.

### [x] T3 — Dart FFI and public API

Scope:

- Add generated-style low-level FFI declarations plus an injectable bindings
  interface for tests.
- Implement `AppKitApplication`, `Window`, `TextView`, `Rect`, event classes,
  explicit disposal, and `NativeFinalizer` safety behavior.
- Decode native event lists into broadcast streams and route events by handle.
- Add Dart unit tests with a fake native backend for lifecycle, errors, event
  routing, UTF-8, and use-after-dispose protection.

Exit criteria:

- `dart analyze` reports no issues.
- Dart unit tests pass without requiring a GUI session.
- The example-facing API matches the intended API in the design document.

### [x] T4 — Embedded Dart host and Kernel launch

Scope:

- Implement `NSApplication`, `AppDelegate`, and `DartHost` in Objective-C++.
- Initialize the Dart VM from pinned runtime/snapshot inputs, create the root
  isolate from a Kernel file, set package configuration and arguments, invoke
  `main`, and report Dart errors deterministically.
- Ensure all root-isolate entry and FFI calls occur on the macOS main thread.
- Implement orderly isolate, VM, registry, and application teardown.

Exit criteria:

- The runner compiles against the pinned embedding API.
- A Kernel program logs that `pthread_main_np()` is true.
- Startup and failure paths return meaningful process exit codes.

Environment-adjusted completion note: the complete Runner source passes the
pinned-header warning gate, argument/input failures have distinct `sysexits`
codes, and both the message pump and host reject a non-main thread. A real
Kernel launch cannot be linked with the released SDK alone, so this evidence
was initially deferred; the final Engine-backed acceptance now closes it.

### [x] T5 — AppKit/Dart event-loop integration

Scope:

- Install the Dart message-notify callback and wake a main-run-loop source.
- Drain Dart messages with a bounded time/message budget and resignal remaining
  work so AppKit cannot be starved.
- Post AppKit events to a Dart `ReceivePort` and prevent Dart re-entry from
  delegates.
- Exercise `Future.delayed`, periodic `Timer`, close, resize, mouse, and keyboard
  events; record fairness observations.

Exit criteria:

- Timers continue while the UI is operated.
- Close reaches Dart and shuts down cleanly.
- A burst test demonstrates bounded Dart draining and responsive AppKit work.

Environment-adjusted completion note: the scheduler integration and exact port
encoder compile, and deterministic tests prove arbitrary-thread enqueue,
main-thread FIFO handling, message/time budgets, resignal, and stop behavior.
The later Engine-backed smoke records three real Timer callbacks while the
AppKit window is active.

### [x] T6 — Developer command and hello example

Scope:

- Implement a Dart command that resolves the input/package config, compiles a
  full Kernel file, builds the native runner only when inputs changed, creates a
  minimal `.app`, launches it, and forwards arguments/stdout/stderr/exit status.
- Add `examples/hello_window/bin/main.dart` that creates text, updates it from a
  timer, observes events, and exits after close.
- Make the documented one-command workflow reproducible from a clean checkout.

Exit criteria:

- One command builds and starts the example.
- Re-running uses cached native build products when inputs are unchanged.
- Invalid paths and compiler/runner failures are actionable.

Environment-adjusted completion note: the real package executable, matching
Engine Kernel compiler, end-to-end bundle workflow, caching inputs, argument
and stdio/exit contracts, and early failures are verified. The final visible
Engine-backed launch also passes.

### [x] T7 — Integration verification and handoff

Scope:

- Run formatting, analysis, Dart tests, native tests, native compilation, and
  the highest available end-to-end smoke test.
- Audit leaks, stale handles, main-thread checks, exit codes, and dirty files.
- Reconcile the implementation with every MVP requirement and record any
  environment-dependent test that could not run.
- Finish `README.md`, architecture notes, and a concise next-phase backlog.

Exit criteria:

- All locally runnable checks pass.
- The worklog contains exact results and unresolved limitations.
- This roadmap states the final position and the next concrete milestone.

Completion note: all local checks and the real Engine-backed GUI smoke pass.
The project now bootstraps the missing released-SDK Engine artifact from the
official pinned source checkout and records the runtime evidence in
`docs/VERIFICATION.md`.

### [x] T8 — Public Dart embedder decision and stock-runtime host

Scope:

- Keep the pinned SDK checkout byte-for-byte compatible with the official
  revision; never add an Engine commit, patch, fork, generated diff, copied
  private helper, private header, or private runtime symbol.
- First implement the missing full product-owned host proof using documented
  public Dart C interfaces. It must own VM initialization, isolate callbacks,
  scheduling, snapshots, and cleanup rather than wrapping `dart_engine`.
- Accept that host only if M1/arm64 JIT and AOT both support the existing
  AppKit-main-thread root plus ordinary `Isolate.spawn`, `Future`, microtasks,
  `Platform.script`, worker error/forced-stop/replacement, live-child cleanup,
  and repeated shutdown.
- If any gate requires private Dart implementation, reject the host and stop
  same-process investigation. The sole fallback is the already validated
  official Dart/AOT worker process; there is no further candidate search.
- Implement only the selected host responsibility that belongs in
  `dart_appkit`. Terminal protocol, pane recovery, and terminal worker
  packaging remain owned by Dart Terminal.
- Preserve the AppKit process-main-thread root, bounded run-loop scheduling,
  public C ABI, and existing root-only example behavior.

Exit criteria:

- One explicit public-host accept/reject decision is supported by both JIT and
  AOT evidence; no hybrid probe is presented as a full-host test.
- The nested SDK remains at the exact official revision with a clean worktree,
  and a source/symbol audit finds no project-owned Dart modification or private
  Dart dependency.
- `dart_appkit` conformance tests cover every selected host responsibility and
  bounded cleanup using only documented public interfaces.
- Existing `make test` and GUI smoke coverage still pass on the primary
  M1/arm64 environment.
- `docs/WORKLOG.md`, architecture/build documentation, and verification
  evidence explain ownership, compatibility, failure behavior, and why each
  earlier alternative was accepted or rejected.
- The configured official Engine and worker inputs are reproducible from their
  published sources without a private fork or unpublished commit.

### [x] T9 — Reusable macOS JIT/AOT application runtime

Scope:

- Add a separate `dart_macos_runtime` Dart package and generic native runtime
  sources while keeping `dart_appkit` focused on reusable AppKit primitives.
- Provide one declarative application manifest, common lifecycle/resource API,
  configurable diagnostics, and Developer JIT / Release AOT bundle assembly.
- Preserve the stock Dart Engine, AppKit-main-thread root, bounded message pump,
  public bridge, and process-lifetime shutdown contracts.
- Keep terminal worker protocol, PTY behavior, and terminal rendering outside
  this repository.

Exit criteria:

- The runtime package's format, analysis, unit, native-header, lifecycle,
  diagnostics, and manifest tests pass.
- Generic host sources build against the pinned official JIT and AOT Engine
  inputs without product-specific native subclasses or terminal symbols.
- A manifest-driven hello-window bundle passes in both Developer JIT and
  Release AOT modes.
- Existing `dart_appkit` tests and legacy developer command remain compatible.

### [x] T10 — Versioned native capability loading

Scope:

- Add a versioned AppKit native-extension service table and a generic runtime
  contract for staging and retaining dependency-owned native code assets.
- Register and instantiate a dependency-owned custom `NSView` in hello-window
  without compiling application-specific Objective-C++ into the runner.

Exit criteria:

- ABI mismatch, missing plugin, duplicate initialization, wrong-thread use,
  failed creation, release, shutdown, and image lifetime are tested.
- Developer JIT and Release AOT hello-window integrations pass with the same
  plugin and public Dart facade.

### [x] T11 — Terminal renderer native capability package

Scope:

- Add `dart_terminal_renderer_macos` as a dependency-owned native capability.
- Move the accepted `TerminalMetalView` shell and its native contract tests
  behind the versioned AppKit extension service table.
- Expose initialization and view creation only through a public Dart facade.

Exit criteria:

- The package build hook produces a loadable macOS dylib with a versioned ABI.
- Native and Dart tests cover initialization, provider creation, AppKit view
  invariants, attachment, ownership, teardown, and image lifetime.
- The implementation does not become part of generic runtime or AppKit host
  source inventories.

## Beyond this MVP

VM Service, incremental Kernel compilation, hot restart/reload, CoreText terminal
rendering, IME, clipboard, PTY, accessibility, signing, sandboxing, and App Store
distribution remain later phases and are not allowed to dilute the event-loop
proof in this roadmap.
