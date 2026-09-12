# MVP Verification

Verification date: 2026-09-04 (Asia/Tokyo). Latest regression update:
2026-09-12.

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
| Per-window key routing and raw-input responder suppression | Native default/exclusive/menu dispatch tests plus Dart state/failure and legacy-symbol tests | Verified |
| v4 application/window lifecycle decisions | Exact encoder records, native delegate coalescing/fail-open/stale-reply tests, Dart state/typed-stream/API tests | Verified |
| v7 application effective appearance | Initial light/dark snapshot, KVO change/deduplication/shutdown native tests, exact shared encoder record, strict Dart cache/typed-stream/malformed/legacy filtering tests | Verified |
| v8 exclusive global hot keys | Native register/conflict/release/re-register/thread/validation tests, exact shared encoder and older-sink filtering, typed Dart ownership/routing/failure tests, and current/legacy FFI smoke | Verified |
| Balanced Secure Event Input and generic view badge | Injected native acquire/yield/reacquire/failure/external-owner/shutdown tests; bounded copied visible/accessibility strings, malformed-input rejection, no-layout overlay checks; typed Dart owner/snapshot/badge/failure tests; optional current/legacy FFI | Verified |
| Current-screen and interruptible window presentation | Negative/mixed-origin screen selection and fallback, copied scale/visible-frame query, level/Spaces mapping, zero/bounded endpoints, stale hide/show completion tests, Dart cache/failure coverage, and current/legacy FFI | Verified |
| Plain-text pasteboard snapshot/write/clear | In-process pasteboard-double native tests, nullable/empty/Unicode/NUL Dart tests, FFI thread guard and legacy fallback | Verified |
| Application-owned external URL policy | Dart default/custom typed-policy matrix, native condition recorder after repeated validation, invariant bound/text/thread guards, current and exact-default legacy FFI smoke | Verified |
| Bounded local notifications and Dock badge mechanism | Immutable Dart input validation, native main-thread/boundary/recorder tests, duplicate badge suppression, authorization-pending cancellation contract, and current/legacy FFI smoke | Verified |
| Menu ownership, attachment, enabled/checked state, validation policy, and actions | Native configured/default/invalid creation, current/legacy FFI, Dart cache-on-success ownership/routing/cross-application tests, real GUI action smoke | Verified |
| View-local context menus and release ownership | Native generic/specialized attach/replace/clear/type/thread/stale/release tests, Dart cache-on-success/failure/retry/cross-application tests, current/legacy FFI | Verified |
| v9 View Quick Look requests and definition presentation | Native stage transition/deduplication/reset/protocol filtering/definition validation and placement recorder, exact shared encoder record, typed Dart weak routing/failure/disposal tests, current/legacy FFI | Verified |
| v10 cached View Services requestor and returned text | Native deepest-responder/fallback/send/return/type/limit/release tests, exact shared encoder and older-sink filtering, typed Dart cache/routing/failure/disposal tests, current/legacy FFI | Verified |
| v11 bounded View text/file-URL drop destination | Native copy-only enter/update/exit/prepare/perform, deepest-target/type/text/URL/limit/stale/release tests, exact shared encoder and v10 filtering, typed Dart packet/cache/routing/failure/disposal tests, current/legacy FFI | Verified |
| v12 application local-folder Services provider | Native primary/secondary actions, filesystem directory/file normalization, ordered de-duplication, type/URL/limit/error/disable/shutdown tests, exact encoder and v11 filtering, typed Dart packet/cache/routing/failure/legacy tests, current/legacy FFI | Verified |
| Registered native custom-view boundary | Objective-C++ provider validation, generic-handle attach/release tests, Dart factory and optional FFI fallback | Verified |
| Configurable base/display-text views | Immutable Dart configurations, native focus/autoresize/font/padding/color validation and state inspection, current/legacy FFI | Verified |
| Bounded attributed multiline editor | Same-surface editable switching; atomic UTF-8 text/UTF-16 selection/style publication; text-preserving restyle; key-free initial glyph paint with independent full-width logical-line background; explicit selection-to-visible viewport follow; native scroll/focus/IME/Undo state; Dart fake, native edge cases, and current/legacy FFI | Verified |
| Explicit two-pane split helper boundary | `TwoPaneSplitView` current API, deprecated `SplitView` construction alias, nested two-child state tests, and unchanged C ABI | Verified |
| Reusable runtime public ABI | C11/C++20 headers plus main-thread/conflict lifecycle tests | Verified |
| Configurable bounded diagnostics | Native validation, permissions, phase ordering, previous-unclean retention, and clean finish tests | Verified |
| Manifest-driven Developer JIT application | Generic host build and real hello-window Timer/menu/close smoke | Verified |
| Manifest-driven Release AOT application | Generic host/snapshot build and the same real hello-window smoke | Verified |
| Runtime package and builder | Strict manifest/resource tests, fake-process JIT/AOT assembly, Dart analysis | Verified |
| Closed folder Services declarations | Strict generic action/menu/duplicate/unknown-key validation, exact escaped JIT/AOT `NSServices`, legacy omission, build-manifest audit, and pre-signing plist lint | Verified |
| Versioned native extension services | Size/version C ABI, main-thread registration, invalid UTF-8, duplicate/conflict, and factory failure tests | Verified |
| Dependency-owned native capability | Dart 3.13 build-hook asset test plus dynamic image ABI/init/create/release/shutdown/lifetime native test | Verified |
| Generic repository ownership audit | Tracked/untracked path and UTF-8 source scan, historical-worklog-only content exemption, positive clean-tree run, and temporary forbidden-content rejection probe | Verified |
| Capability-enabled JIT/AOT GUI | Same Dart facade and manifest create the dependency view in both real generic hosts; bundles pass deep signature verification | Verified |
| Dart FFI crosses the real Mach-O bridge | Struct/error/ABI FFI smoke | Verified |
| Runner startup matches Dart 3.13.2 | Strict compile plus exact source revision check | Verified |
| Scheduler cannot re-enter and has configurable hard-bounded turns | Strict manifest/plist tests plus default/custom/rejected-bound FIFO, count-budget, and time-budget message-pump tests | Verified |
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

The 2026-09-05 regression additionally verifies manifest-declared Dart helper
compilation/staging/lookup, both `void` and Future-returning application mains,
explicit bundle-path native-asset loading, gated generic host-start failure, and final
Release diagnostics. Full `make test` and native-capability hello-window GUI
smokes pass in Developer JIT and Release AOT.

`make run-example` keeps the window open for interactive resize, mouse, and key
testing. Both this project and the nested Dart checkout are Git working trees.
The final audit checks the project diff explicitly; the Engine validation
requires the nested SDK's exact `HEAD` and an empty tracked-source status.

## Next-phase backlog

The 2026-09-10 Runner activation-policy regression check additionally verifies
that applying an already-effective AppKit policy is idempotent even when the
platform setter would return false. `make runner-configuration-test` covers the
native branch without changing the public ABI or manifest contract. The
complete `make test` regression matrix also passes after the correction.

The 2026-09-11 attributed-editor regression adds an optional full-width
logical-line background whose checked UTF-16 location and color remain
independent from syntax foreground, underline, selection, caret, and editable
state. Native line-fragment tests, Dart public/fake tests, current/legacy FFI,
and the complete `make test` matrix pass.

The 2026-09-11 initial-paint follow-up prepares the highlighted editor's text
layout before the first background and glyph draw. A native fresh-window test
uses no key, selection, or reveal event, records layout-before-background draw
ordering, and verifies syntax-colored glyph pixels in the initial cached
display. The assertion fails against the former background-draw layout order;
focused and complete verification pass with the corrected prepaint order.

- Add VM Service and restart only after deciding the desired debugging model.
- Treat AOT, signing, hardened runtime, sandboxing, accessibility, IME,
  clipboard, native assets, and distribution as separate milestones.
- Consider a smaller prebuilt Engine cache for contributors who should not
  carry the approximately 10 GiB source/build workspace.
- Keep product worker IPC, supervision, recovery, and packaging in the
  consuming product rather than adding product-specific behavior here.
