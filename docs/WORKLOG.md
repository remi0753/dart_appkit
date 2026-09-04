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

### First candidate-import attempt

Both the `dart_appkit` repository and its nested SDK checkout were rechecked as
clean. The candidate parent exactly matched the checkout at
`60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. An initial local `git fetch` using
the abbreviated candidate ID `28462f0fb37` failed with `couldn't find remote
ref`; fetch treats that argument as a remote ref name and the disposable repo
does not advertise abbreviated object IDs. No object checkout or source file
changed. The verified full candidate ID is
`28462f0fb379e38be5c3ce4cd7263a9057ad02d7`; the retry will expose that commit
through a temporary full ref rather than converting it to a patch.

The full ref import succeeded. The nested SDK now has clean branch
`codex/engine-lifecycle-candidate` at full commit
`28462f0fb379e38be5c3ce4cd7263a9057ad02d7`, directly above the pinned upstream
commit. Recomputing `git diff HEAD^ HEAD | shasum -a 256` produced
`8d98a31a2042df252f0da55536150a20a46ddc75407fd35ef98acd0751286e00`, exactly
matching the independently validated candidate. No patch command or working
tree modification is involved; the SDK checkout is clean on the candidate
commit.

### Constraint correction: Dart Engine is immutable

The user clarified that modifying Dart Engine is prohibited even when the
integration work is owned by `dart_appkit`. This supersedes the candidate
adoption portion of the T8 plan. A normal SDK commit is still a Dart Engine
source modification, so the distinction between a commit and a downstream
patch does not make that route acceptable.

The candidate was not built, linked, or used by `dart_appkit` after import.
The nested SDK checkout was immediately returned to the exact official Dart
3.13.2 revision `60a57cd42d64dc03e9f07aa60a2e250755c1ef28` and rechecked with
an empty working tree. The candidate is rejected as a product dependency.

From this point onward T8 treats the official SDK checkout as immutable. The
allowed implementation surface is this repository and documented public Dart
Embedder/Engine interfaces exposed by that unmodified revision. The ordered
evaluation is:

1. Re-evaluate whether `dart_appkit` can own multiple stock Engine root
   isolates in one process, including lifecycle, scheduling, error containment,
   and an explicit public message bridge between isolate groups.
2. Re-evaluate a `dart_appkit`-owned host built only from public Dart Embedder
   APIs if it provides a complete, documented lifecycle without copying SDK
   internals.
3. If neither same-process route satisfies the contract, put the already
   validated official Dart executable/AOT process worker behind a
   `dart_appkit` API and retain process isolation as the supported fallback.

M1/arm64 JIT and AOT are the primary acceptance environments. x86_64 and
Universal verification remain later compatibility work. No Engine file,
commit, patch, generated Engine diff, or private runtime helper may become a
`dart_appkit` input.

### Additional same-process option before implementation

The prior probes already provide decisive evidence against two direct uses of
the stock Engine for dynamic workers: multiple Engine roots cannot be retired
individually through `dart_engine.h`, and public lightweight isolates cannot
use microtasks or preserve the original uncaught-error diagnostic because the
stock Engine registered no child initializer. Repeating those implementations
would not change their ownership or initialization contracts.

A distinct stock-runtime topology remains to be tested before selecting a
separate worker process: let the published `dart` executable (and its AOT
executable output) initialize the VM exactly as Dart's runner intends, then
hand the macOS process main thread synchronously to a native AppKit run loop.
Ordinary Dart application work runs in a standard spawned isolate. All AppKit
operations are marshalled by the `dart_appkit` bridge to the native main
thread, and native events continue to use Dart native ports. This keeps one
process and standard Dart isolate initialization without linking or modifying
`dart_engine`.

The option is accepted only if a minimal M1/arm64 proof establishes all of the
following before product code is migrated:

- the official JIT and AOT entrypoint can synchronously hand off the actual
  process main thread to AppKit;
- a standard worker isolate continues `Future`, microtask, Timer, and port work
  while that main thread is in the native run loop;
- AppKit calls from the Dart worker are synchronously and safely executed on
  the process main thread, with bounded behavior during shutdown;
- native events reach the Dart worker and the process exits cleanly without a
  private VM or Engine symbol.

If this topology fails any of those conditions, the next and final supported
route remains the official Dart/AOT process-worker boundary.

### Official-runner main-thread probe: first attempt

A minimal Dart FFI probe was prepared outside both repositories. It loads the
already built public `dart_appkit` bridge and asks
`da_debug_is_main_thread` whether synchronous startup, a microtask, and a timer
callback run on the macOS process main thread. Its first JIT and AOT attempts
stopped at Dart type checking because the probe passed `Pointer<Int32>` to a
local `free` wrapper typed as `Pointer<Void>` without an explicit cast. No
Engine or repository source was involved, and no runtime conclusion can be
drawn from this harness error.

`dart format` did format the temporary probe, then returned nonzero because the
sandbox denied a modification-time update to the user's Dart telemetry session
file. That is an environment-side post-command failure rather than a format
error. The pointer cast will be corrected and the same two runtime modes will
be retried with permission for Dart's normal telemetry bookkeeping.

The corrected probe ran successfully in both official Dart 3.13.2 JIT and an
official `dart compile exe` ARM64 AOT executable. Every phase reported
`status=0 main=0`: the initial synchronous Dart `main`, its microtask, and its
timer callback all ran away from the macOS process main thread. Therefore a
Dart entrypoint cannot synchronously hand its current thread to AppKit in
either mode.

One narrower possibility remains before rejecting this topology: the official
runner might service the process main dispatch queue even though Dart executes
on a mutator thread. A temporary native probe will post an asynchronous block
to that queue and wait at most one second on the Dart thread. If the block does
not execute on the process main thread, `dart_appkit` cannot install an AppKit
run loop there from Dart code without replacing or modifying the official
runner.

The bounded dispatch probe returned `main_dispatch=0` in both official JIT and
ARM64 AOT. The posted block did not execute within one second, so this
supplementary same-process topology is rejected. No repository or SDK source
was changed by either temporary probe.

### T8 reset: frozen execution plan

Reviewing the task against the user's original direction exposed a planning
error: the full product-owned public embedder proposed at the beginning was
never actually implemented. The completed public probe created lightweight
children inside an already initialized stock Engine. Its negative microtask
result is valid for that hybrid, but does not by itself test a host that owns
`Dart_InitializeParams` from the start. The roadmap must not claim otherwise.

T8 is therefore reset to one fixed decision sequence:

1. Implement the smallest complete `dart_appkit` host using only documented
   public Dart C headers/symbols from the exact published SDK. It owns VM and
   isolate initialization, message scheduling, JIT/AOT snapshot inputs, and
   final cleanup.
2. Test the full mandatory lifecycle in M1/arm64 JIT and AOT. Accept only if all
   gates pass without `runtime/bin`, private symbols, copied Dart internals, or
   an SDK source change.
3. Apply the result once. If accepted, finish that host here. If rejected,
   record the exact public-contract gap and end same-process work; Dart
   Terminal will adopt the already validated official process worker. No new
   topology is added.
4. Keep ownership strict: this repository owns AppKit and generic VM-host
   integration; Dart Terminal owns terminal protocol, pane recovery, and
   terminal worker packaging.

The multiple-root, lightweight-child, modified-Engine, and official-runner
main-thread alternatives are closed evidence, not future branches. The
corresponding normative plan is
`../dart_terminal/docs/phase1/stock-dart-runtime-migration-plan.md`; the two
roadmaps now expose the same next action and decision rule.

After restoring detached HEAD to the official revision, the local
`codex/engine-lifecycle-candidate` branch was deleted. A final comparison
against `60a57cd42d64dc03e9f07aa60a2e250755c1ef28` produced no diff, and the SDK
working tree is empty. No candidate Engine reference remains in the active
`dart_appkit` SDK checkout.

Roadmap-reset validation passed `git diff --check`, package `dart analyze`,
`dart run test/run_tests.dart`, and `dart run test/launcher_tests.dart`. The
SDK HEAD and clean-tree checks passed again at the official revision. This
checkpoint changes only `ROADMAP.md` and this worklog; no AppKit, host, package,
build, or SDK source has changed. T8 remains active at the full public-host
proof and is not marked complete.

### Full public-host proof design before source changes

The stock source and exported-symbol audit separates the available public VM
surface from the missing platform integration:

- `dart_api.h` exports VM flags and initialization, platform-Kernel
  registration, JIT and AOT isolate-group creation, per-isolate initialization
  callbacks, message notification/handling, native ports, isolate shutdown,
  and VM cleanup. It also documents the Mach-O AOT snapshot symbols consumed by
  `Dart_CreateIsolateGroup`.
- `dart_embedder_api.h` says `dart::embedder::InitOnce` must run before
  `Dart_Initialize`, but `InitOnce` is not exported by either stock shared
  library. Its implementation starts Dart IO process/timer/event-handler and
  SSL subsystems through `runtime/bin` implementation.
- Stock `dart_engine` calls the private
  `bin::DartUtils::SetupCoreLibraries` after every root creation. That routine
  installs builtin/IO native resolvers, finalizes loading, supplies print and
  URI hooks, installs the isolate scheduler closure into `dart:async`, and
  invokes isolate hooks. Neither the routine nor the native resolver tables are
  exported as public symbols.

The proof will not call or reproduce either private routine. A native test host
under `native/runner` will include only `dart_api.h` and
`dart_native_api.h`, link the unmodified stock shared VM carrier, provide the
documented file/entropy/lifecycle/message callbacks, load JIT Kernel or the
documented AOT snapshot symbols, and invoke a Dart conformance program. The
Dart program tests a synchronous call first, then `Platform.script`, a
microtask, standard child work, fault/forced-stop/replacement lifecycle, and a
live child at final cleanup. Once a required primitive fails, later outcomes
are reported as unavailable rather than emulated with private code.

A Make target will rebuild the required Release ARM64 JIT and Product ARM64 AOT
artifacts from the exact clean revision, compile both probe payloads, run them
under an outer timeout, audit that public symbols are present and the two
private helpers are absent, and recheck the SDK worktree. The proof is accepted
only if both modes satisfy every frozen gate. Otherwise it records one explicit
rejection and the fixed roadmap selects the official process worker.

The first C++ formatting command could read the newly added probe but could not
replace it because command-based writes to the adjacent `dart_appkit`
repository are sandbox-restricted (`Operation not permitted`). It changed no
source or SDK file. The same repository-local ARM64 clang-format invocation
will be repeated with write permission; this is an environment constraint, not
a host-probe result.

After formatting, the strict C++ syntax check passed. The first focused Dart
analysis reported one warning: the deliberately retained live-child `Isolate`
handle was assigned but not read. The probe will include that child's debug
name in its completion report, making both the retention and the intended
live-at-cleanup state observable instead of suppressing the warning.

### Full public-host result and fixed decision

`make public-dart-api-host-probe` rebuilt the stock Release ARM64 JIT and
Product ARM64 AOT shared libraries plus their published compiler inputs from
the exact official revision. Both native hosts compiled with strict warnings,
both payloads compiled, and both executions completed within the outer
15-second bound. The pre- and post-run Engine checks reported the official
revision and an empty tracked worktree.

The JIT and AOT results were semantically identical:

- the native host and root Dart invocation started successfully on the macOS
  process main thread;
- a synchronous Dart function returned the expected value;
- `Platform.script` failed because its required embedder value was null;
- `scheduleMicrotask` failed with the exact public runtime diagnostic
  `Unsupported operation: Microtasks are not supported`;
- the async lifecycle entry could not advance and timed out, so no child
  initialization callback ran;
- root shutdown, VM cleanup, isolate/group cleanup callbacks, and the host's
  repeated-shutdown guard completed successfully.

The shared-library audit found all public VM symbols used by the proof, but no
exported `dart::embedder::InitOnce` or
`bin::DartUtils::SetupCoreLibraries`. Supplying the missing platform values,
native resolvers, IO event handler, async scheduler closure, and isolate hooks
would therefore require private `runtime/bin` implementation or a copied
reimplementation. Both are prohibited by the frozen boundary.

Decision: reject the full public-API host for Dart 3.13.2. This is now the
actual test of the initially proposed product-owned embedder, distinct from the
earlier lightweight-child hybrid. The fixed decision rule is applied exactly
once: the selected worker topology is the already validated official Dart JIT
executable / self-contained AOT executable process boundary. No other
same-process candidate will be considered in this migration.

The ownership consequence is also fixed. `dart_appkit` remains the stock
Engine, one-root, process-main-thread AppKit host and enforces a pristine SDK
input. It does not grow terminal-specific process supervision. Dart Terminal
owns the worker executable, IPC protocol, pane recovery, and packaging because
those are product runtime concerns. Process exit is the authoritative worker
cleanup boundary; final UI-host cleanup is the containing application process
exit after stock Engine root shutdown.

### T8 completed: stock-root contract and final verification

The selected `dart_appkit` responsibility is now explicit and enforced:

- `scripts/check_dart_engine.sh` rejects any tracked SDK source change in
  addition to the exact revision, architecture, symbols, install name, Kernel
  compiler, and platform-Kernel checks;
- production remains the existing one-root stock `dart_engine` host, with
  AppKit and its bounded message pump on the process main thread;
- no public-host proof source is linked into the production Runner, and no
  process-worker protocol or terminal recovery policy was added here;
- architecture, build, verification, root README, and Runner documentation now
  reject in-process dynamic workers and place official Dart JIT/AOT worker
  ownership in the consuming product.

Final M1/ARM64 verification results:

- ARM64 clang-format dry run for `PublicDartApiHostProbe.cc`: passed;
- focused Dart format check: 2 files, 0 changed;
- focused Dart analysis: no issues;
- `git diff --check`: passed;
- `make test`: all scaffold, ABI, native bridge, Runner, message-pump, Dart API,
  launcher, example Kernel, and FFI smoke checks passed;
- `make engine-check`: passed at official revision
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`, ARM64, with no tracked SDK
  source changes;
- `make example-smoke`: root attached to the AppKit main thread, Timer ticks 1
  through 3 ran, native close reached Dart, handles were released, and the
  process exited 0;
- `make public-dart-api-host-probe`: both stock JIT and AOT roots started and
  cleaned up, both reproduced missing platform/microtask bootstrap, no child
  initializer ran, and the final decision remained
  `accepted=false public_platform_bootstrap=false jit_runtime=false
  aot_runtime=false`.

All T8 exit criteria are therefore closed for the primary environment. The
same-process search is finished rather than deferred. Intel/Rosetta/Universal
work remains lower-priority compatibility work and cannot change the selected
M1 topology. The next implementation milestone is in Dart Terminal: replace
its patched-Engine worker lifecycle with the already validated official Dart
process-worker boundary, then delete patch infrastructure after both Developer
JIT and Release AOT migrations pass.

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

## 2026-09-03 — Native event protocol negotiation extension

- Dart Terminal's next platform-substrate task required the existing event
  list to evolve without breaking the MVP API. The C ABI version had also been
  used as the event discriminator, the port registration could not negotiate,
  and the Dart decoder accepted only version 1.
- Kept `DA_ABI_VERSION` at 1 and kept the original event-port registration as
  a version-1 compatibility entry point. Added an additive range-negotiation
  entry point that chooses the highest common event version, reports a stable
  unsupported-version status for disjoint ranges, and clears registration on
  failure.
- Added version 2 with source generation, monotonic nanoseconds, and operation
  ID in its six-field common prefix. Current unsolicited window/input events
  use operation ID zero. The shared Runner encoder continues to serialize the
  exact original version-1 lists for legacy registration.
- The Dart API now negotiates version 2 when available, falls back through the
  legacy symbol when paired with an older native bridge, decodes both v1 and
  v2, preserves public constructors and `monotonicMicros`, and exposes current
  protocol metadata.
- Native negotiation tests cover v1, v2, invalid ranges, disjoint ranges, and
  legacy registration. A standalone encoder test verifies the exact v1 resize
  and v2 key `Dart_CObject` layouts and fail-closed invalid input. Dart tests
  cover both versions plus malformed envelope/type/length/generation/time/
  operation cases.
- The first standalone FFI assertion expected the missing Runner poster status,
  but standalone Dart is also off the AppKit process main thread and therefore
  correctly returned the earlier wrong-thread guard. The test was corrected to
  accept either valid precondition failure while still requiring a native
  diagnostic; no product behavior changed for that failed attempt.
- `make test` passed scaffold/header validation, native bridge tests, strict
  Runner compilation/link checks, message-pump and exact event-encoder tests,
  Dart analysis/API/launcher tests, example analysis/Kernel compilation, the
  current FFI bridge smoke, and the explicit new-Dart/legacy-native fallback
  fixture. Native and Dart formatting checks reported no changes.

## 2026-09-03 — Handle domains and asynchronous destruction

- Extended every occupied registry slot with an AppKit-main thread domain and
  replaced its occupied bit with explicit live, release-pending, free, and
  retired states. Registry metadata is mutex-protected; AppKit work and object
  deallocation remain outside the lock.
- Ordinary lookup now validates the stored domain and actual caller. A new
  any-thread `da_release_async` call claims one live handle before returning,
  immediately rejects later access and duplicate release, and completes
  teardown on the AppKit main queue without blocking the requester.
- Routed `NativeFinalizer` through the same claim path. Shutdown closes
  admission, drains both live and pending handles on the main thread, and
  leaves queued callbacks harmless. Exhausted positive generations retire
  their slots instead of wrapping.
- Native coverage now checks domain mismatch, off-main access, immediate
  pending invalidation, main-thread deallocation, sixteen concurrent claimers
  with exactly one winner, pending window teardown during shutdown,
  post-shutdown rejection, and 1,000 reuse generations. The first focused
  warning-as-error native build and test run passed.
- While updating the ownership record, `docs/C_ABI.md` was found to still
  describe only the legacy event envelope. It now records the already-shipped
  v1/v2 negotiation contract together with the new release semantics.
- Final native and Dart formatting checks reported zero changes. The complete
  `make test` suite passed header/scaffold checks, warning-as-error native and
  Runner builds, registry/event/message-pump tests, Dart analysis/API/launcher
  tests, Kernel compilation, real-dylib FFI, and the legacy-native fallback.
- The race-bearing native bridge suite then passed 25 consecutive executions.
  The built dylib exports 18 public `da_*` symbols, including
  `da_release_async`, and the real FFI smoke resolves that symbol and verifies
  its invalid-handle status.

## 2026-09-04 — Generic view boundary

- Dart Terminal's next platform-substrate item needs a reusable content-view
  type before later terminal-specific view work. Added native `DaView` and
  public Dart `View` bases while retaining `DaTextView`/`TextView` as the
  specialized text implementation.
- The registry now models one explicit subtype relationship: a text-view kind
  satisfies a generic-view lookup. Generic views remain invalid for text-only
  operations, and window handles remain invalid for all view operations.
- Added the additive `da_view_create` entry point and changed content-view
  attachment to borrow any registered view. Existing generation, thread-domain,
  synchronous/asynchronous release, finalizer, and AppKit retain relationships
  are unchanged.
- The FFI lookup for the additive symbol is optional so a current Dart client
  can still load the legacy event compatibility fixture. Attempting to create
  a generic view against that fixture returns the stable unsupported-version
  status instead of failing library construction.
- Native and Dart tests cover generic and text-view creation, both attachment
  paths, exact text-kind rejection, wrong window-kind rejection, Dart subtype
  use, finalizers, disposal, and the legacy-symbol fallback.
- Focused `make validate`, `make native-test`, and `make dart-test` runs passed.
  The complete `make test` suite then passed header/scaffold checks,
  warning-as-error bridge and Runner builds, registry/event/message-pump tests,
  Dart analysis/API/launcher tests, example Kernel compilation, real-dylib FFI,
  and the legacy-native fallback.
- The bridge exports 19 `da_*` symbols including `da_view_create`. Dart
  Terminal's `make runtime-source-check` also passed formatting, native header
  checks, plist lint, analysis, and unit tests against the new `View` API.

## 2026-09-04 — Window-state event protocol

- Bumped the independently negotiated current event protocol to version 3.
  Version 3 keeps the version-2 six-field prefix and adds focus, visibility,
  occlusion, backing-scale, and screen event types. Existing event payloads
  remain unchanged in versions 1, 2, and 3.
- Added protocol-aware filtering in the event sink and the shared encoder.
  Version-3-only events never reach a poster selected for version 1 or 2, so
  old decoders do not receive an unknown event type.
- The AppKit window owner now posts one deduplicated state snapshot after show
  and translates key/resign, miniaturize/deminiaturize, occlusion, backing
  property, screen, and close callbacks into normalized immutable values.
  Visibility excludes miniaturized windows; occlusion is the inverse of
  `NSWindowOcclusionStateVisible`.
- Screen events represent absence explicitly. Present screens carry the
  positive `NSScreenNumber` display identifier and finite, positive-dimension
  full/visible frames in global AppKit point coordinates.
- Added public Dart event classes, `AppKitScreen`, typed streams, and cached
  `Window` state. State is applied before application-level and window-level
  observers receive the event. The decoder rejects state types before v3,
  non-boolean state, non-finite/non-positive scale, malformed screen presence,
  identifier, rectangles, and field counts.
- Updated the hello example to exhaustively consume the new sealed event
  subclasses and log state transitions.
- The first focused native build exposed that adding one nullable Objective-C
  annotation enabled a completeness warning for older declarations under
  `-Werror`. The internal annotation was removed because nil remains a valid
  Objective-C argument and the header does not otherwise declare nullability.
- The first encoder test retained protocol 3 as its unsupported-version probe
  after version 3 became current, so it posted a valid key record and produced
  cascading layout assertions. The probe was corrected to version 4 while
  retaining separate v3 invalid-screen and invalid-scale cases.
- The first complete `make test` stopped at the C header fixture because its
  explicit current-version assertion still expected 2. Both C11 and C++20
  assertions were updated to 3 before rerunning the complete suite.
- The corrected complete `make test` passed scaffold/header validation,
  warning-as-error bridge and Runner builds, registry/event/message-pump and
  exact encoder tests, Dart analysis/API/launcher tests, example Kernel
  compilation, real-dylib FFI, and the legacy-native fallback fixture.
- The native bridge suite passed ten consecutive executions. The real hello
  example negotiated v3, reported focus, visibility, occlusion, backing scale,
  and screen state from AppKit, then auto-closed and released cleanly.
- An export audit was first pointed at the obsolete
  `build/libdart_appkit.dylib` path and found no file. Repeating it against the
  Makefile output `build/native/libdart_appkit_bridge.dylib` confirmed exactly
  19 public `da_*` symbols; this protocol-only extension added no C ABI entry
  points.
- Final native/Dart formatting and `git diff --check` reported no changes or
  whitespace errors.

## 2026-09-04 — Application and window lifecycle protocol

- Dart Terminal's next platform-substrate item was split before implementation.
  Its first deliverable requires lifecycle request/reply semantics before menu
  actions can safely drive Close and Quit.
- Bumped the independently negotiated event protocol to version 4 while keeping
  C ABI version 1 and the exact v1-v3 record layouts. V4 adds application
  active, reopen, and termination events; a window-close request; and the
  payload-free menu-action record needed by the following additive menu API.
- Application events use source handle/generation zero. Registry-backed window
  and menu records retain generation-checked identity. Notifications require
  operation ID zero; close and termination requests require a positive ID.
- Deferral is opt-in and one request may be pending per application or window.
  Duplicate delegate calls are coalesced, stale/wrong-target/reused replies are
  rejected, and deferral cannot be disabled while a decision is outstanding.
  A failed or down-negotiated event post permits the OS action. Programmatic
  close and termination bypass the user-decision path so Dart teardown cannot
  wait on an event source it has already closed.
- Registering a v4 event port posts the current active-state snapshot. Later
  AppDelegate callbacks post active/resign and reopen transitions without
  entering Dart synchronously.
- The Dart API exposes cached application activity, typed application and close
  request streams, explicit request/reply methods, and opt-in deferral toggles.
  New FFI symbols are optional so loading the legacy-native fixture still works;
  using an unavailable lifecycle feature returns the stable unsupported status.
- The first combined verification stopped in the native test compile because
  the diagnostic-heavy equality macro tried to stream a scoped enum. The four
  decision assertions were changed to boolean comparisons; product code was
  unaffected. The second combined run passed header checks, the exact event
  encoder, and native bridge tests, then found unhandled malformed-event errors
  on three derived typed streams. No-op error handlers were added to those test
  subscriptions while the primary application stream retained and asserted all
  seven `FormatException` values.
- The corrected Dart analysis, API/launcher tests, and Runner warning-as-error
  syntax check passed. The first full `make test` then passed every scaffold,
  header, warning-as-error native/Runner, scheduler/encoder, Dart, example
  Kernel, real-dylib FFI, and legacy-native fixture check.
- The first two real hello-window close-request smokes did not deliver a request
  after the unattended Dart timer called `performClose:` and were interrupted.
  Adding a temporary arrival log confirmed the request, rather than the reply,
  was missing. The public `da_window_request_close` implementation now invokes
  the owner delegate decision directly and closes only when it returns true;
  actual title-bar user actions still enter the same delegate through AppKit.
  The final smoke delivered operation 1 to Dart, accepted its reply, emitted
  focus/visibility/closed events, released both handles, and exited 0.
- The final full `make test` passed after that runtime correction. The native
  bridge suite also passed ten consecutive executions. Header/native and Dart
  format checks, `git diff --check`, and Dart Terminal's complete
  `runtime-source-check` passed.
- A `clang-format` invocation resolved to depot_tools and refused to run outside
  a Chromium checkout without changing files; the pinned Dart SDK ARM64 binary
  was used successfully. A sandboxed no-write Dart format audit reported zero
  changed files but failed while updating a user telemetry timestamp; the same
  audit passed with the required filesystem permission.
- The built bridge exports 24 public `da_*` symbols, including all five new
  application/window lifecycle calls. `make engine-check` passed and the
  official SDK remains clean at
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.

## 2026-09-04 — Plain-text pasteboard boundary

- Added a four-operation main-thread C surface for general-pasteboard text
  snapshots, UTF-8 replacement, clear, and change-count observation. A snapshot
  carries an explicit presence flag, byte length, borrowed thread-local bytes,
  and the count observed in the same call, so absent and present-empty text are
  distinct without relying on NUL termination.
- Native conversion helpers accept an `NSPasteboard` selected by the caller.
  Public functions always select the general pasteboard; automated tests use
  an in-process test double and therefore never connect to, inspect, or replace
  user clipboard contents.
- Writes validate and copy UTF-8 before clearing existing formats, then publish
  one `NSPasteboardTypeString` item. Native tests cover absent, empty, Unicode,
  embedded NUL, increasing counts, invalid UTF-8, null outputs, unavailable
  pasteboard, and all public off-main guards with zeroed outputs.
- Added a stable application-owned Dart `Pasteboard` facade and immutable
  `PasteboardTextSnapshot`. FFI copies borrowed bytes before freeing its output
  struct and validates presence, pointer, length, UTF-8, and nonnegative count
  invariants. Unit tests cover facade identity, nullable/empty/Unicode/NUL
  round trips, count propagation, native errors, and use after application
  termination.
- All four symbol lookups are optional. The old native fixture still loads and
  returns status 8 only on pasteboard use; the real dylib smoke resolves the
  count call and observes the expected standalone wrong-thread diagnostic.
- The first ten-run audit exposed that repeatedly creating globally retained
  `pasteboardWithUniqueName` instances eventually makes the pasteboard server
  return `nil`. Reusing and globally releasing one test-only name passed the
  immediate repeat, but a later cross-feature audit reproduced service
  exhaustion after a real GUI run. The unit fixture now uses an in-process
  pasteboard double and never depends on the system pasteboard server.
- Final verification passed the full scaffold/header/native/Runner/event/Dart/
  example/real-FFI/legacy suite, warning-as-error native formatting, Dart
  Terminal's complete runtime source check, and `git diff --check`. The built
  bridge exports exactly 28 public `da_*` symbols, including all four new
  pasteboard calls.

## 2026-09-04 — Menu ownership and action boundary

- Added independent registry kinds and C/Dart creation APIs for menus,
  actionable items, and separators. Attachment calls add items, attach or clear
  submenus, and attach or clear the application main menu without consuming a
  handle. Dart mirrors the public graph with strong item/submenu/main-menu
  references and rejects cross-application attachment before FFI.
- Menu shortcut masks accept only the existing seven stable modifier bits and
  convert them to AppKit flags internally. Menus disable auto-enablement;
  actionable items expose explicit enabled state and deterministic action
  performance, while separators reject state, submenu, and action operations.
- Each item handle owns a native target. AppKit clicks and the explicit test
  operation post the same v4 payload-free event with the item's encoded
  generation and operation ID zero. Dart publishes it on the application
  stream and routes it through a weak handle map to the live item-local stream.
  V1-v3 sinks suppress the record.
- Release clears an item's handle, target, action, and enabled state before
  dropping its registry lease, making an AppKit-retained late action harmless.
  Releasing the currently attached main-menu handle detaches it from
  `NSApplication`. Other AppKit retain edges remain independent of handles.
  Dart updates its route/main-menu state only after native release succeeds;
  injected failures prove the wrapper and routing stay usable on failure.
- New FFI lookups remain optional; the legacy fixture reports unsupported only
  when menu operations are called. The real-dylib smoke resolves menu creation
  and confirms its main-thread guard without altering application UI state.
- The first focused run passed the native menu suite, then Dart analysis caught
  a lost type promotion at the later item-dispatch site. Rechecking the decoded
  event type at that call fixed the static error without changing behavior. The
  focused header/native/Dart/FFI/legacy rerun passed.
- The hello example now installs an application menu. Its unattended path
  performs the real Quit item action, waits for the Dart action event, and then
  enters the existing deferred window-close request/reply path.
- The first post-GUI ten-process audit exposed two AppKit test assumptions:
  the pasteboard server can refuse even a reused private name after rapid
  process churn, and assigning `nil` to `NSApplication.mainMenu` may result in
  AppKit installing a replacement empty menu. The pasteboard test now uses an
  in-process double, and main-menu release asserts detachment from the released
  object rather than requiring `nil`; neither change weakens the public
  ownership contract.
- Final verification passed the complete scaffold/header/native/Runner/event/
  Dart/example/real-FFI/legacy suite and ten consecutive native executions.
  The real Engine-backed GUI reported the Quit action in Dart, delivered close
  operation 1, accepted its reply, released all handles, and exited 0.
- Native and Dart format audits, `git diff --check`, Dart Terminal's complete
  `runtime-source-check`, and `make engine-check` passed. The dylib exposes
  exactly 36 public `da_*` symbols, including all eight new menu calls, and the
  official SDK is clean at
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.

## 2026-09-04 — Registered custom-view provider boundary

- Added a separate Objective-C++ provider surface that registers named
  `NSView` subclasses on the AppKit main thread. Registration copies the name,
  accepts an idempotent same-name/same-class call, and rejects empty names,
  non-view classes, and conflicting replacement.
- Added `da_view_create_custom`, which copies a UTF-8 provider identifier,
  constructs the registered class with `initWithFrame:`, and inserts the
  instance as an ordinary generic-view handle. Generic lookup now returns
  `NSView*` rather than assuming every generic handle is a `DaView` subclass.
- Added `View.custom` and optional FFI symbol lookup. The API intentionally has
  no numeric-handle constructor: Dart can request a registered provider but
  cannot forge a view wrapper around an event-exposed handle or pass an
  Objective-C pointer across FFI.
- Native tests cover provider validation, missing/conflicting registrations,
  class identity, window attachment, text-only rejection, wrong-thread create,
  stale/double release, and the independent AppKit retain edge. Dart tests
  cover provider-name forwarding, generic attachment, ownership, and disposal.
- The complete scaffold/header/native/Runner/event/Dart/example/real-FFI/
  legacy suite passed, followed by native and Dart format audits and
  `git diff --check`. The dylib exposes 37 public `da_*` symbols including
  `da_view_create_custom`, exports the native registration entry point, and the
  official SDK remains clean at
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`. Consuming-product verification
  remains in the ordered Dart Terminal subtasks.

## 2026-09-04 — Reusable macOS JIT/AOT application runtime

- Purpose: turn the accepted stock AppKit/Dart host into a reusable
  `dart_macos_runtime` package so consuming application repositories do not
  compile native runner code or dependency internals.
- Scope: a separate Dart package; a declarative application manifest; common
  lifecycle, bundle-resource, and configurable diagnostics contracts; generic
  Developer JIT and Release AOT host sources; bundle assembly and focused
  tests. Existing `dart_appkit:run` behavior remains compatible during the
  additive migration.
- Out of scope: terminal worker protocol and recovery, PTY, terminal renderer,
  native-plugin registration, signing/notarization completion, and later
  platform features.
- Dependencies: the pinned unmodified Dart 3.13.2 Engine, the existing AppKit
  bridge/event encoder/message pump, and the Phase 1 product evidence in the
  adjacent Dart Terminal repository.
- Completion requires format/analysis/unit/native contract checks, generic JIT
  and AOT host compilation against official inputs, manifest-driven
  hello-window smoke in both modes, existing suite compatibility, clean SDK,
  and reviewed repository state.
- Initial risk: the current Release AOT host interleaves generic host behavior
  with terminal diagnostics, worker-resource injection, custom-view
  registration, and product failure gates. The reusable host must reconstruct
  the accepted teardown order without copying those policies.
- Initial repository state is clean at `52ddd2c`; local `main` is one commit
  ahead of `origin/main`. The adjacent Dart Terminal plan and ownership ADR are
  committed at `2602891` and `ec85382` respectively.
- Added a separate `packages/dart_macos_runtime` package. Its exact-key JSON
  manifest owns product name, executable, identifier, version, minimum macOS,
  Dart entrypoint, declared resources, and diagnostics enablement/storage name.
  Absolute, empty, duplicate, dot-segment, backslash, and runtime-reserved
  resource paths are rejected before bundle mutation.
- The builder validates the exact Dart 3.13.2 SDK/revision, selects the matching
  official Release or Product Engine output for the host architecture, builds
  only a generic host target, compiles linked Kernel, creates the AOT Mach-O
  snapshot when selected, stages a fixed bundle layout and SDK license, emits a
  bounded build manifest, applies an ad-hoc signature, and optionally launches
  with inherited stdio and direct arguments.
- The first Release AOT smoke reached the native host but `Dart_Invoke` could
  not find `main`: the AOT compiler had correctly tree-shaken an entrypoint
  retained only by native name lookup. Requiring product code to add a VM pragma
  would leak embedder policy into every application. The builder now generates
  a private `@pragma('vm:entry-point')` wrapper importing the ordinary
  `main(List<String>)`; both build modes compile that wrapper.
- Added independent `dmr_*` lifecycle and diagnostics ABIs. Lifecycle accepts
  any nonzero process result representable by the portable 1–255 exit range,
  is AppKit-main-only, preserves the first result, and queues termination.
  Diagnostics are manifest-disabled by default, use generic metadata identity,
  validate all persisted fields, write 0700/0600 atomically, enforce monotonic
  phases, and retain at most current plus one prior unclean record.
- `MacosRuntime` validates host ABI, exposes lifecycle and phase calls, and
  resolves declared bundle resources using normalized relative names. The
  application receives no Objective-C pointer, native source path, or mutable
  runner configuration.
- Native C11/C++20 header checks, lifecycle tests, and diagnostics tests pass.
  Both generic hosts compile warning-clean against the unmodified official
  Engine. Package format, analysis, strict manifest tests, runtime facade tests,
  and fake-process JIT/AOT bundle tests pass.
- `make test` passes the complete pre-existing bridge, Runner, message-pump,
  event, Dart API, legacy launcher, example Kernel, real FFI, and compatibility
  fixture suites together with the new runtime tests.
- Real manifest-driven hello-window GUI smokes pass in Developer JIT and Release
  AOT. Each reports root attachment, two Timer ticks, the Dart menu action,
  deferred close request/reply, window close, handle release, and exit 0. The
  official nested SDK remains clean at
  `60a57cd42d64dc03e9f07aa60a2e250755c1ef28`.
