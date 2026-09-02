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

- Active task: **T8 — same-group isolate lifecycle contract**
- Completed: **T0, T1, T2, T3, T4, T5, T6, T7**
- Engine acceptance gate: **reopened** for same-group child initialization and
  complete Engine-owned VM cleanup. The stock Dart 3.13.2 Engine remains the
  accepted root-only baseline at revision
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.
- Verified baseline: root-main-thread execution, periodic Timer work, native
  close delivery, handle release, and process exit 0.
- Next concrete milestone: validate a general Engine correction and make
  worker lifecycle a fail-closed `dart_appkit` host capability.

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

### [ ] T8 — Same-group isolate lifecycle contract

Scope:

- Define which same-group isolate initialization and final cleanup
  responsibilities belong to Dart Engine and which scheduling/host guarantees
  belong to `dart_appkit`.
- Integrate the product-independent Engine correction as a reviewable SDK
  commit based directly on the pinned upstream revision; do not add a product
  patch-application step or copy private Dart runtime helpers into this repo.
- Add a real Runner conformance program covering `Isolate.run`/`Isolate.spawn`,
  `Future`, microtasks, `Platform.script`, contained worker errors, a live child
  during final shutdown, and repeated host shutdown protection.
- Make configuration and documentation distinguish the upstream base revision
  from the candidate Engine revision and fail closed for an unsupported stock
  Engine.
- Preserve the AppKit process-main-thread root, bounded run-loop scheduling,
  public C ABI, and existing root-only example behavior.

Exit criteria:

- The Engine change is an auditable clean commit with upstream-style Engine
  sample tests passing in JIT and AOT; the `dart_appkit` repository contains no
  patch file for it.
- `dart_appkit` conformance tests demonstrate working same-group async child
  isolates and bounded cleanup without private SDK calls from AppKit code.
- Existing `make test` and GUI smoke coverage still pass on the primary
  M1/arm64 environment.
- `docs/WORKLOG.md`, architecture/build documentation, and verification
  evidence explain ownership, compatibility, failure behavior, and the fact
  that the candidate is not yet a stock Dart release.
- The configured Engine inputs are reproducible or the remaining upstream/fork
  publication dependency is reported as a blocker rather than hidden.

## Beyond this MVP

VM Service, incremental Kernel compilation, hot restart/reload, CoreText terminal
rendering, IME, clipboard, PTY, accessibility, signing, sandboxing, and App Store
distribution remain later phases and are not allowed to dilute the event-loop
proof in this roadmap.
