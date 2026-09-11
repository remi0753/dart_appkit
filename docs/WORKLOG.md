# Implementation Worklog

This is the append-oriented evidence log for `ROADMAP.md`. Each completed task
ends with a roadmap checkpoint stating the current position and remaining path.

## 2026-09-10 — Application effective-appearance event

### Purpose and boundary

Expose the reusable AppKit application light/dark state required by consuming
applications without moving any product theme names, colors, or palette policy
into the native bridge. Keep the C ABI at version 1 and extend only the
independently negotiated immutable event protocol.

### Scope and verification plan

- Add protocol v7 application appearance event type 33. Its zero-source,
  zero-operation notification payload is one boolean: false for light and true
  for dark.
- Best-match `NSApplication.effectiveAppearance` against Aqua/Dark Aqua, post
  an initial v7 snapshot, observe the SDK-recommended KVO key, deduplicate the
  resulting two-state projection, and remove observation on re-registration or
  shutdown.
- Expose `AppKitAppearance`, `ApplicationAppearanceChangedEvent`, nullable
  `AppKitApplication.effectiveAppearance`, and a typed change stream. Update
  the cache before application observers receive an event.
- Verify v1–v6 filtering, exact shared JIT/AOT encoder layout, KVO lifecycle,
  strict/malformed Dart decode, typed cache/stream, and legacy registration.

### Findings and verification

- AppKit's effective appearance can represent more than two named variants.
  `bestMatchFromAppearancesWithNames:` provides the stable application-level
  light/dark projection while allowing accessibility variants to remain owned
  by later APIs.
- Event-port registration happens before the Dart receive-port listener is
  installed, but `ReceivePort` queues the native snapshot. The public cache is
  therefore nullable only until that queued v7 record is decoded; old v1–v6
  native images retain the nullable fallback indefinitely.
- Re-registering any event protocol first removes the observer. Successful v7
  registration installs a fresh observer and snapshot; older registration and
  failed negotiation cannot retain a stale appearance callback.
- Focused `CI=true DART_SUPPRESS_ANALYTICS=true make native-test
  event-encoder-test dart-test` passed warning-clean Objective-C++/C++ builds,
  actual Aqua/Dark Aqua KVO change and deduplication, shutdown silence, exact v7
  wire encoding, Dart analysis, cache-before-stream routing, malformed v6/v7
  records, and legacy selection.
- Complete `CI=true DART_SUPPRESS_ANALYTICS=true make test` passed scaffold and
  C/C++ contract checks, every native bridge/Runner/runtime/capability/renderer/
  PTY suite, all Dart analyzers and tests, example Kernel compilation, current
  bridge FFI smoke, and the v1 legacy event fallback.
- Final diff and documentation review plus `git diff --check` passed. The C ABI
  remains version 1; v1–v6 layouts and behavior are unchanged, and type 33 is
  rejected before posting to every older negotiated sink.

### Roadmap checkpoint

The application appearance slice of G10 is implemented. G10 remains open for
its other published window/application operations; no later roadmap item was
implemented.

## 2026-09-10 — configurable menu enablement and message-pump budgets

### Purpose and boundary

Move AppKit menu auto-enablement and the Runner's per-turn Dart message count
and time budgets into application-selected immutable configuration. Keep the
existing explicit menu state plus 64-message/4000-microsecond behavior as
compatibility defaults, while retaining library-owned hard bounds that prevent
an application from monopolizing the main run-loop turn.

### Scope and verification plan

- Add immutable `MenuConfiguration(autoEnablesItems: false)` and a
  size-prefixed configured menu creation symbol. Old bridges accept only the
  exact explicit-state default.
- Add a nested `runner.messagePump` manifest object with positive integer
  `maxMessagesPerTurn` and `maxTimePerTurnMicros`; default to 64 and 4000.
- Enforce hard maxima of 1024 messages and 16000 microseconds in manifest
  parsing, native Runner metadata parsing, and `DartMessagePump.Start` so direct
  construction cannot bypass the scheduler invariant.
- Record both values in generated Info.plist and runtime-build-manifest, then
  construct the Runner pump from the parsed immutable limits.
- Test Menu default/custom/legacy behavior, strict/atomic manifest and plist
  parsing, hard-bound pump rejection, configured draining, generated metadata,
  and complete regressions.

### Findings and verification

- The first focused run passed every native bridge case, then Dart analysis
  rejected two accesses through the nullable configured-menu allocation kept
  for cleanup. The allocation now uses a non-null local for initialization and
  invocation, while the nullable owner remains solely for `finally` cleanup.
- `MenuConfiguration` is immutable and defaults to explicit item state. Its
  16-byte size-prefixed C record accepts only boolean zero/one and zero reserved
  data; the old create symbol delegates to the false default, and Dart uses an
  old image only for that exact policy.
- `runner.messagePump` is a strict optional nested object. Both values must be
  positive integers; application values flow unchanged through the generated
  Info.plist and runtime-build-manifest into the Runner configuration.
- The defaults remain 64 messages and 4000 microseconds. The manifest parser,
  native plist parser, and pump startup independently enforce hard maxima of
  1024 messages and 16000 microseconds, so direct native construction cannot
  bypass the run-loop fairness boundary.
- Focused `DART_SUPPRESS_ANALYTICS=true CI=true make native-test dart-test
  ffi-smoke runner-configuration-test message-pump-test runtime-dart-test`
  passes configured/default/invalid Menu creation, current and exact-default
  legacy FFI, strict and atomic metadata parsing, configured pump draining,
  both hard bounds, and generated bundle metadata.
- Complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` passes scaffold,
  warning-clean C11/C++20 bridge and Runner builds, all native runtime,
  capability, renderer, and PTY suites, every Dart analyzer/test suite, example
  Kernel compilation, current FFI, and legacy fallback.
- Final source and documentation review plus `git diff --check` pass. ABI and
  event protocol versions remain unchanged; both additions are optional or
  additive, and compatibility defaults reproduce the previous behavior.

### Roadmap checkpoint

All seven ordered genericity-audit corrections are complete. The broader G0,
G10, and G11 roadmap items remain open for their other published completion
conditions; no later feature work was pulled forward.

## 2026-09-10 — configurable base and simple text views

### Purpose and boundary

Move base-view first-responder/autoresizing behavior and the built-in display
text view's font, padding, foreground, and background presentation out of
native fixed values. Preserve the current behavior as immutable compatibility
defaults and do not impose these settings on registered custom views, whose
providers continue to own their native behavior and appearance.

### Scope and verification plan

- Add immutable `ViewConfiguration` for first-responder acceptance and
  independent width/height autoresizing. `View()` accepts it; `View.custom`
  remains provider-owned.
- Add immutable text font, padding, and color values plus
  `TextViewConfiguration`, including a nested base-view configuration. Preserve
  monospaced system 18-point regular text, 20-point padding, label foreground,
  and window-background fill as defaults.
- Bound font size, named-font UTF-8 bytes, and padding; use closed font kind,
  weight, system-color, and autoresizing values. Allow fixed sRGB colors.
- Add size-prefixed configured creation ABI calls. Keep old creation symbols as
  exact-default wrappers, and let current Dart bindings use old images only for
  exact compatibility configurations.
- Test public validation/state forwarding, native AppKit properties/drawing
  inputs and malformed configurations, current FFI thread guards, exact-default
  legacy fallback, custom rejection on old images, and full regressions.

### Findings and verification

- `ViewConfiguration` now selects first-responder acceptance and width/height
  autoresizing independently. Plain `View` stores and forwards it;
  `TextViewConfiguration` nests it; provider and container views expose no
  invented package configuration.
- `TextViewConfiguration` owns immutable font, padding, foreground, and
  background values. System and monospaced-system fonts support the closed
  weight set; a named font is an exact AppKit font name, so its style belongs in
  that name and a separate non-regular weight is rejected rather than ignored.
- Font size is capped at 512 points, an exact named font at 256 UTF-8 bytes, and
  each non-negative padding extent at 4096 points. Dynamic label/window
  background roles use canonical records; fixed sRGB components remain finite
  in `[0, 1]`.
- Native `DaView` stores the configured responder decision and autoresizing
  mask. `DaTextView` stores the resolved `NSFont`, edge-specific padding, and
  colors and uses them directly during drawing. Existing default initializers
  still reproduce the historical values.
- The new configured C records are size-prefixed and their C/C++ layouts are
  fixed at 24, 40, and 160 bytes. Old create symbols delegate with exact
  defaults; FFI falls back to them only for matching configurations and returns
  unsupported for custom values on an old image.
- Two initial documentation/header patches missed exact surrounding text and
  applied no changes; they were reapplied as narrower patches. No compile or
  behavior failure resulted.
- Focused `DART_SUPPRESS_ANALYTICS=true CI=true make native-test dart-test
  ffi-smoke` passes public forwarding/bounds, native default/custom AppKit state
  and malformed records, current FFI guards, and exact-default legacy fallback.
- Complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` passes scaffold,
  fixed C/C++ layouts, warning-clean native/Runner suites, every package
  analysis/test, manifest assembly, example compilation, current FFI, and
  legacy fallback.
- Final diff review and `git diff --check` pass. ABI version and event protocol
  remain unchanged, custom providers retain their own policy, and the additive
  APIs do not broaden existing handles or ownership.

### Roadmap checkpoint

Base and display-text view policy is configurable with compatibility defaults.
The next ordered correction is making menu auto-enablement and Runner
message-pump budgets application-selected within conservative hard bounds.

## 2026-09-09 — explicit two-pane split helper boundary

### Purpose and boundary

Define the existing two-child, one-divider, non-collapsible, binary-zoom split
surface by its actual scope instead of presenting it as the package's generic
split-view abstraction. Preserve source and C ABI compatibility while leaving
a future general split container free to use a different child and divider
model.

### Scope and verification plan

- Publish the implementation as `TwoPaneSplitView`, retaining the existing
  axis, ordered first/second children, fraction/minima, equalize, and binary
  zoom contract.
- Keep `SplitView` as a deprecated source-compatible type alias; do not rename
  native symbols or handles and do not change runtime behavior.
- Update current examples/tests and boundary documentation to use the explicit
  helper name and describe thin divider plus non-collapsible policy.
- Run Dart API/analysis tests and then the complete suite to prove source
  surface, native behavior, and ABI remain stable.

### Findings and verification

- The first Dart analysis correctly identified that an `is TwoPaneSplitView`
  assertion on the alias-typed compatibility fixture was statically always
  true. The fixture now checks its concrete runtime type, retaining the alias
  construction proof without an analyzer warning.
- The implementation is now published as `TwoPaneSplitView`; its API docs state
  the exact two-child, one thin non-collapsible divider, and binary zoom model.
  `SplitView` is a deprecated typedef to the same class, so existing source
  construction remains valid while new code does not mistake it for a future
  general split-container abstraction.
- Native class names, handles, exported symbols, axis values, layout behavior,
  and ownership are unchanged. The C header now labels those existing symbols
  as the two-pane helper ABI rather than implying an extensible split model.
- Focused `DART_SUPPRESS_ANALYTICS=true CI=true make dart-test native-test`
  passes analysis, current-name and compatibility-name construction, nested
  helper state/ownership, and all native bridge tests.
- Complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` passes all scaffold,
  C/C++ ABI, native/Runner, package analysis/test, manifest, example compile,
  current FFI, and legacy-symbol checks.
- Final review and `git diff --check` pass with no ABI or event-protocol change.

### Roadmap checkpoint

The existing split surface is now explicitly bounded as a two-pane helper. The
next ordered correction is parameterizing base-view and simple-text-view focus,
autoresize, font, padding, and color choices while preserving compatibility
defaults.

## 2026-09-09 — application-owned external URL policy

### Purpose and boundary

Retain structural URL validation, unsafe-character rejection, exact UTF-8
copying, and the 4096-byte hard limit in the library while moving the scheme
allowlist and per-scheme authority/host/credentials/path conditions into an
immutable application policy fixed when `AppKitApplication` attaches.

### Scope and verification plan

- Add immutable `ExternalUrlPolicy` and `ExternalUrlSchemePolicy` values with
  the current HTTP/HTTPS/mailto behavior as the compatibility default.
- Make `AllowedExternalUrl` parse against an explicit or default policy and
  revalidate against the attached application's policy immediately before FFI.
- Add an additive native open call carrying the selected lowercase scheme and
  closed condition flags. Native code repeats structural and selected-policy
  validation without owning a universal scheme list.
- Preserve the old native function and use it only when an old image receives
  exactly the compatibility rules; custom policies fail as unsupported.
- Test custom schemes, each policy condition, unsafe text independent of
  policy, policy mismatch at application open, current/legacy FFI, and bounds.

### Findings and verification

- The first warning-clean native build caught a test-only `1u << 63`
  expression whose left operand was 32-bit. The unknown-policy-bit fixture now
  uses a 64-bit operand so it exercises validation without undefined shifting.
- The next focused run passed native tests and then found that the public API
  test intentionally did not receive internal FFI flag constants from the
  package barrel. The test now imports only those internal constants needed to
  verify the fake boundary; they remain outside the supported public surface.
- `ExternalUrlPolicy` is deny-by-default and rejects duplicate normalized
  schemes. Each `ExternalUrlSchemePolicy` owns authority allowance/requirement,
  host requirement, credential allowance, and path requirement; scheme syntax
  and its 64-byte forwarding bound are validated when policy is built.
- `AllowedExternalUrl` preserves the exact source string while parsing under an
  explicit policy. `AppKitApplication.openExternalUrl` reparses under the
  immutable policy fixed at attach, preventing a value created under a broader
  policy from crossing a narrower application boundary.
- The additive native call receives only the already-selected lowercase scheme
  and closed condition bits. It repeats scheme identity and every condition,
  but owns no scheme list. Its structural URL checks, unsafe-text/escape
  rejection, main-thread guard, zeroed output, and 4096-byte hard limit remain
  unconditional.
- The original C entry retains the exact HTTP/HTTPS/mailto behavior. Current
  Dart bindings use that entry on an older image only when the selected rule
  exactly matches the compatibility default; custom schemes or conditions are
  rejected as unsupported.
- Focused `DART_SUPPRESS_ANALYTICS=true CI=true make native-test dart-test
  ffi-smoke` passes custom/default Dart policy cases, every native condition,
  structural invariant rejection, current FFI, and old-image exact-default
  fallback.
- Complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` passes scaffold and
  C/C++ header checks, warning-clean native/Runner suites, all package analyses
  and tests, manifest assembly, example compilation, current FFI, and legacy
  fallback.
- Final diff review and `git diff --check` pass. ABI version and event protocol
  are unchanged, default callers retain their prior behavior, and no external
  application is launched by automated tests.

### Roadmap checkpoint

Application-owned external URL policy is complete. The next ordered correction
is defining the current split view explicitly as a two-pane helper or widening
its presentation and child model without imposing product layout.

## 2026-09-09 — parameterized native-tab accessory

### Purpose and boundary

Separate a tab's color value from the library-owned 8×8 circular appearance.
The bridge may provide a simple native marker mechanism, but application code
must select its size and shape rather than inheriting product presentation.

### Scope and verification plan

- Keep `WindowTabColor` as an immutable sRGB value and add an immutable
  `WindowTabAccessory` with bounded width/height and rectangle/ellipse shape.
- Add `Window.tabAccessory`; retain `Window.tabColor` as the source-compatible
  8×8 ellipse helper used by existing consumers.
- Add a size-prefixed additive native setter and keep the existing color setter
  as the same compatibility helper. An old bridge accepts only that default.
- Validate finite positive dimensions under a hard 256-point bound, shape
  values, color components, current/legacy FFI behavior, and registry lifetime.

### Findings and verification

- `WindowTabColor` now represents only validated sRGB components.
  `WindowTabAccessory` owns the bounded logical size and rectangle/ellipse
  choice; a non-square ellipse is supported without inventing another shape.
- The size-prefixed native configuration reserves future extension space,
  rejects unknown shape/reserved values, and limits each dimension to 256
  points before allocating the AppKit view. The accessory remains retained by
  `NSWindowTab` and creates no registry handle.
- `Window.tabColor` maps to an 8×8 ellipse for source compatibility. The old C
  setter delegates to the same configured implementation, and FFI falls back
  to it only for that appearance or clearing.
- The first Dart analysis found a stale dispose cache name and that
  `RangeError.range` was not the suitable double-valued constructor; both were
  corrected without weakening validation. The first legacy fallback run also
  showed that the fixture lacked the intermediate tab-color symbol. Giving the
  fixture that old symbol now proves both the accepted default fallback and
  unsupported custom appearance.
- Focused `DART_SUPPRESS_ANALYTICS=true CI=true make native-test dart-test
  ffi-smoke` passes warning-clean native shape/size/color validation, public API
  and fake-backend tests, current FFI, and old-symbol compatibility behavior.
- Complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` passes scaffold and
  header checks, every native suite, all Dart analysis/tests, manifest
  assembly, example compilation, FFI loading, and legacy fallback.
- Final review confirms that ABI version and event protocol remain unchanged,
  existing `tabColor` callers retain the old appearance, and the bridge no
  longer selects one mandatory size or shape for the preferred API.

### Roadmap checkpoint

Parameterized native-tab presentation is complete. The next ordered correction
is moving external URL scheme and scheme-specific rules into application-owned
immutable policy while retaining library structural safety checks.

## 2026-09-09 — configurable Window style

### Purpose and boundary

Move the generic window's fixed titled/closable/miniaturizable/resizable choice
into an immutable public `WindowConfiguration`. AppKit remains responsible for
validating and applying the native style mask; application code chooses the
presentation while the compatibility default retains every existing style.

### Scope and verification plan

- Add four independent public style flags with the existing combination as a
  const default and a borderless all-false configuration as a valid choice.
- Add a size-prefixed configured-window creation ABI with a closed set of
  stable style bits. Keep `da_window_create` unchanged as the legacy default.
- Discover the additive native symbol lazily. An old bridge may create only the
  compatibility default and must return typed unsupported-version failure for
  a non-default configuration.
- Verify native style translation, malformed size/unknown-bit rejection,
  Dart forwarding/cache behavior, old-image fallback, and the complete gate.

### Findings and verification

- `WindowConfiguration` exposes the four existing style choices as immutable
  booleans. Its const default encodes all four legacy bits, while all-false
  reaches AppKit as the valid borderless mask.
- The new `DaWindowConfiguration` is size-prefixed and the configured creation
  symbol is additive under ABI version 1. Native validation rejects a null or
  short structure and any bit outside the declared stable mask before creating
  a registry object. The old symbol delegates to the same implementation with
  the compatibility mask.
- Current FFI bindings lazily discover the new symbol. Tests against the legacy
  fixture prove that the default still calls `da_window_create`, while a
  non-default configuration fails with `DA_STATUS_UNSUPPORTED_VERSION` instead
  of silently changing appearance.
- Focused `DART_SUPPRESS_ANALYTICS=true CI=true make native-test dart-test
  ffi-smoke` passes warning-clean style translation and invalid-input native
  tests, immutable Dart API/fake-backend tests, current-image FFI, and both
  default and non-default legacy behavior.
- Complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` passes scaffold and
  header checks, all native suites, every Dart package analysis/test, manifest
  assembly, example Kernel compilation, FFI loading, and the legacy fallback.
- Final diff review found no ABI-version or event-protocol increment, no
  product-specific style, and no change to old `Window(...)` call behavior.

### Roadmap checkpoint

Configurable window creation is complete. The next ordered correction is
removing the fixed 8×8 circular native-tab accessory policy.

## 2026-09-09 — configurable Runner lifecycle policy

### Purpose and boundary

Remove four product choices from the generic native Runner: activation policy,
forced launch activation, termination after the last window closes, and whether
the reopen delegate reports the request as handled. The host still owns AppKit
startup order and asynchronous lifecycle event delivery; each application
selects immutable policy before the run loop starts.

### Scope and compatibility plan

- Add a strict optional `runner` manifest object and a corresponding
  `RunnerConfiguration` value model shared by Developer JIT and Release AOT.
- Persist the validated settings in the generated bundle Info.plist so both
  runtime modes consume one startup contract without reserving application
  command-line arguments.
- Keep the existing regular/activate/continue/handled behavior as the default
  for old manifests and for the standalone `dart_appkit:run` launcher.
- Continue posting reopen requests asynchronously even when the configured
  AppKit delegate return value is false; no synchronous Dart callback is added.
- Cover manifest defaults and strict validation, generated bundle metadata,
  native metadata decoding, and delegate policy values before running the full
  regression gate.

### Findings and verification

- The generated Info.plist is the immutable handoff point shared by both host
  modes. This avoids reserving application arguments in Release AOT and also
  lets a copied bundle retain its validated startup policy.
- The native decoder accepts an absent dictionary and absent known fields as
  compatibility defaults, rejects unknown keys, non-boolean values, and
  unknown activation policies, and applies updates failure-atomically.
- The first focused compile found Objective-C forward declarations inside the
  C++ namespace; moving those declarations to global scope fixed the
  warning-as-error build. The first Dart analysis then found that the new enum
  was not exported by the package barrel; the public export now includes both
  Runner manifest types. Both failures are covered by the focused gates.
- `DART_SUPPRESS_ANALYTICS=true CI=true make runner-configuration-test
  runner-syntax runtime-dart-test` passes native metadata decoding,
  warning-clean Runner syntax, Dart analysis, strict manifest parsing, and JIT
  and AOT bundle assembly tests.
- `DART_SUPPRESS_ANALYTICS=true CI=true make runtime-jit-runner
  runtime-aot-runner` builds and links both real generic hosts against the
  pinned unmodified Engine.
- Complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` passes scaffold and
  C/C++ header checks, all bridge/runner/runtime/capability/renderer/PTY native
  suites, all Dart analysis and tests, manifest assembly, example Kernel
  compilation, FFI loading, and legacy event fallback.
- Final review confirms that lifecycle delegates still post active and reopen
  records asynchronously, no ABI or event protocol changed, and old manifests
  preserve the previous behavior exactly.

### Roadmap checkpoint

The Runner lifecycle audit correction is complete. The next ordered correction
is moving the fixed NSWindow style mask into a safe, configurable
`WindowConfiguration`.

## 2026-09-07 — mutable window frames and native fullscreen state

### Purpose and boundary

Provide the generic AppKit primitives needed by a consumer to restore and track
window placement without moving product restoration policy into this package.
The bridge owns only a finite positive outer frame, the currently observed
native fullscreen state, and AppKit's asynchronous transition lifecycle. Screen
selection, placement migration, persistence, terminal hierarchy, and reopen
policy remain consumer responsibilities.

### Scope and decisions

- Add optional ABI-v1 symbols for synchronous frame mutation and asynchronous
  fullscreen requests. Current Dart bindings discover them lazily and report
  the established unsupported-version status against an older native image.
- Extend the independently negotiated event protocol to version 6 with strict,
  immutable outer-frame and fullscreen-state records. Version 1 through 5
  layouts remain byte-for-byte unchanged, and v6-only records are suppressed
  for older sinks.
- Publish a deduplicated frame/fullscreen snapshot after a window is shown and
  publish later move, resize, fullscreen-completion, and transition-failure
  observations from `NSWindowDelegate`. No delegate synchronously enters Dart.
- Treat a request matching the observed or pending fullscreen target as an
  idempotent success. Reject an opposite target during a native transition so
  Dart cannot cache a guessed state; update `Window.isFullscreen` only from the
  observed completion event.
- Keep `Window.frame` failure-atomic and validate finite coordinates plus
  positive finite dimensions at both Dart and native boundaries. Negative
  origins remain valid for multi-screen AppKit coordinates.

### Tests and findings

- Native bridge coverage verifies frame set/deduplication, fullscreen current
  state, show-time snapshots, transition callbacks, invalid values, wrong
  handle kind, wrong thread, stale generation, and v5 filtering of both new
  event types. The shared runner encoder covers exact v6 records, malformed
  frame values, and v5 suppression.
- Dart coverage verifies public typed events/streams, cache-before-observer
  ordering, frame mutation/deduplication/failure atomicity, pending fullscreen
  behavior, malformed records, disposal, fake bindings, FFI thread guards, and
  legacy missing-symbol failures.
- The first focused native run exposed three obsolete fixture assumptions:
  protocol 6 was still expected to be unsupported, changing a frame also emits
  the pre-existing content-resize event, and the current scroll capture now
  carries the negotiated protocol rather than literal version 5. Updating only
  those expectations made the bridge, encoder, and Dart suites pass; no product
  contract was weakened.
- A later callback-coverage addition first passed `nil` to delegate parameters
  annotated nonnull by the current macOS SDK, which the warning-as-error build
  correctly rejected. The fixture now supplies real enter/exit notifications
  and the owned window to failure callbacks; production code was unaffected.
- Focused `DART_SUPPRESS_ANALYTICS=true CI=true make native-test
  event-encoder-test dart-test` passes, including warning-clean Objective-C++,
  the C/C++ public header checks, Dart analysis, API tests, and launcher tests.
  The first complete-gate invocation could not link its first test executable
  because the managed workspace denied writes to this adjacent repository's
  `build/` directory; this was an execution-environment restriction, not a
  compiler or test failure. Re-running the identical command with the required
  scoped permission succeeded.
- Complete `DART_SUPPRESS_ANALYTICS=true CI=true make test` passes scaffold
  validation; warning-clean C11/C++20 headers and native bridge, runner,
  runtime, capability, renderer, and PTY tests; Dart analysis and tests for all
  packages; manifest JIT/AOT assembly; hello-window Kernel compilation; FFI
  main-thread coverage; and the legacy-event bridge fallback.
- Final diff review found no change to C ABI version, no synchronous native-to-
  Dart callback, no product restoration policy, and no generated artifact in
  the tracked change. The event version is the only wire-contract increment,
  and exact v1-v5 behavior remains covered.

### Consumer fullscreen sequencing correction

Terminal integration after commit `47b1f5e` found that a user-initiated native
fullscreen transition could publish move/resize frames before its completion
state. Publishing the final fullscreen frame before the state likewise gives a
consumer no reliable way to retain its last safe windowed frame. The window
owner now marks will-enter/will-exit transitions, suppresses only frame-state
records while that transition is pending, and publishes the observed
fullscreen state before the resulting frame on enter, exit, and failure.
Legacy content-resize delivery is unchanged so renderers can keep adapting
during animation.

The native fixture drives will/did/failure callbacks with real nonnull
notifications, verifies same-target and opposite-target behavior while pending,
proves transition frames are suppressed, and checks state-before-frame ordering
at both completion boundaries. This follow-up changes no ABI/event layout and
will be committed normally rather than amending the substrate commit. Focused
`DART_SUPPRESS_ANALYTICS=true CI=true make native-test` and the complete
`DART_SUPPRESS_ANALYTICS=true CI=true make test` both pass after the correction,
including every native, Dart, JIT/AOT manifest, FFI, and legacy-image gate.

### Consumer outer-frame creation correction

The terminal restoration acceptance exposed a remaining inconsistency in the
same public frame contract. `da_window_create` passed the requested rectangle
to `initWithContentRect`, so the native outer frame included title-bar and
border insets, while the cached Dart constructor value and later
`da_window_set_frame` calls treated the rectangle as the outer frame. A real
fullscreen exit therefore sometimes reported a larger window than the
pre-fullscreen cached value, depending on whether the show-time frame event had
arrived before the consumer captured its safe placement.

Creation now normalizes the new native window to the requested outer frame
before installing its owner, handle, or delegate. This cannot publish an extra
event and changes no ABI or event ordering. The native window-state fixture
checks all four components of the initial outer frame so constructor and setter
semantics cannot diverge again. Focused and complete verification results are
recorded below after execution.

`DART_SUPPRESS_ANALYTICS=true CI=true make native-test` passed the
warning-clean Objective-C++ bridge suite. The complete
`DART_SUPPRESS_ANALYTICS=true CI=true make test` gate also passed scaffold and
header validation, every bridge/runner/runtime/capability/renderer/PTY native
suite, all Dart analysis and tests, JIT/AOT manifest assembly, Kernel
compilation, real FFI loading, and the legacy-event fallback. Diff review found
only the pre-owner frame normalization, its exact native assertion, and this
evidence record; no generated build output is tracked.

## 2026-09-07 — represented paths and native-tab color markers

### Purpose and boundary

Expose two generic `NSWindow` presentation primitives required by a terminal
consumer without moving terminal metadata or trust policy into this package.
An optional absolute represented file path uses the standard proxy-icon/path
menu. An optional bounded sRGB color uses a small `NSWindowTab` accessory. Both
remain properties of the existing window and create no additional registry
handle.

### Scope and verification plan

- Add additive, optional FFI lookups and legacy failure behavior without
  changing ABI or event protocol versions.
- Validate main-thread, window-handle generation/type, UTF-8 absolute path,
  4096-byte path cap, and finite unit color components in the native bridge.
- Cache only successful set/replace/clear operations in the Dart `Window` and
  validate equivalent Dart input before crossing FFI.
- Exercise Objective-C++ state, FFI main-thread errors, legacy symbol absence,
  fake bindings, failure atomicity, disposal, formatting, analysis, and the
  complete repository gate before committing.

### Results

- Added cached `Window.representedFilePath` and `Window.tabColor` public state,
  pre-FFI validation, equality no-ops, failure atomicity, and disposal reset.
  Legacy images discover both new functions optionally and return the existing
  unsupported status rather than failing image construction.
- Added C ABI and Objective-C++ operations that retain proxy/tab presentation
  under the existing `NSWindow`. Direct native coverage verifies the file URL,
  Unicode path, exact sRGB components, marker geometry, set/clear, input limits,
  wrong kind/thread/stale generation, and unchanged registry count.
- The first focused native build found that the current macOS SDK declares
  `-[NSColor getRed:green:blue:alpha:]` with a `void` return, while the test had
  treated it as a Boolean. The test now calls the method and checks all four
  output components; no bridge or public API behavior changed.
- The rerun passed the native bridge test, Dart analysis/API/launcher tests,
  FFI main-thread smoke, and legacy missing-symbol smoke. The complete
  repository gate remained to be run before commit.
- `DART_SUPPRESS_ANALYTICS=true CI=true make test` passed scaffold/contract
  validation, every bridge/runner/runtime/capability/PTY native test, every
  package analyzer and Dart suite, the example build, FFI main-thread smoke,
  and legacy event-bridge smoke. All changed Dart sources were formatted.
- Final path validation accepts well-formed non-BMP filenames (covered by an
  emoji path) while rejecting an isolated UTF-16 surrogate before FFI. The
  complete gate passed again after this correction.
- Diff review found no additional registry object, synchronous Dart callback,
  terminal policy, or unrelated generated artifact. This AppKit subtask is
  complete and ready for its independent consumer-pinned commit.

### Consumer export correction

The first terminal-consumer analyzer run after commit `5e085cf` found that
`WindowTabColor` was present in `src/api.dart` and all package tests but absent
from the curated `package:dart_appkit/dart_appkit.dart` export list. No FFI or
native behavior failed. The public symbol is now exported, and the primary Dart
API test imports the public library rather than the internal source library so
this consumer boundary is covered directly. This correction requires a normal
follow-up commit; the prior commit will not be amended.

The first public-import test run then exposed that the package's documented
testing library exported raw-event injection but not its existing application
attachment helper. That helper is now exported only from `testing.dart`, and
the API test accesses it through the explicit testing namespace while all
production types continue to come from the public production library.

The public-import Dart test and complete repository gate now pass with no
analyzer issue. This follow-up changes only curated exports and test coverage;
the previously verified C ABI and native implementation are unchanged.

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

## 2026-09-04 — Versioned native capability loading

- Purpose: let a Dart dependency contribute native AppKit behavior without
  adding its Objective-C++ source, classes, or registration calls to the
  generic runtime executable or the consuming application repository.
- Scope: a versioned plain-C host service table; callback-backed custom-view
  providers; generic process-lifetime capability image loading; manifest and
  build-hook asset staging; a dependency-owned hello view and Dart facade; ABI,
  thread, duplicate, construction, release, shutdown, and image-lifetime tests;
  real Developer JIT and Release AOT hello integration.
- Out of scope: terminal renderer implementation, PTY, arbitrary plugin event
  protocols, unload/reload, and platform distribution signing.
- Dependencies: completed generic runtime commit `649a4ac`, existing custom-view
  registry/handle ownership, Dart 3.13 build hooks, and the unmodified official
  Engine toolchain.
- Completion requires the host/plugin headers to compile as C11/C++20, focused
  native and Dart tests to pass, plugin sources to remain absent from both host
  source inventories, both real GUI modes to create/release the dependency view,
  the complete existing suite to pass, and all findings to be recorded here.
- Initial decision: retain every successfully loaded capability image for the
  process lifetime. This is intentionally stronger than opportunistic unload
  and makes registered factory callbacks valid through asynchronous AppKit
  handle teardown and bridge shutdown.
- Added `dart_appkit_native_extension.h` with a size/version-prefixed v1 host
  service table and a plain-C retained-view factory. The bridge validates main
  thread, UTF-8 identifier, duplicates/conflicts, factory presence, and returned
  `NSView`, then uses the existing generation/domain registry for attachment,
  explicit release, asynchronous release, and shutdown.
- Added `dart_appkit_example_view` as a dependency-owned integration package.
  Its Dart 3.13 build hook uses `native_toolchain_c` to build one Objective-C
  dylib and its Dart facade explicitly initializes the image before requesting
  the named custom view. The view implementation is absent from generic JIT and
  AOT host source lists and from the consuming hello application.
- Extended the application manifest with exact native capability declarations.
  The builder invokes `dart build cli` to run the official dependency hook/link
  pipeline for the resolved package graph and target architecture, selects the
  declared dylib outputs, stages them under Frameworks, signs them as nested
  code, and records ID/package/library/ABI/symbol identity in the runtime build
  manifest.
- The first CLI hook integration failed because `native_toolchain_c` passed its
  framework and encryptable linker arguments through an intermediate compile
  step while the package enabled `-Werror`. The hook now explicitly routes a
  dynamic library to the app bundle and disables only clang's unused command
  line argument diagnostic; all source warnings remain errors.
- `MacosNativeCapability` rejects undeclared, malformed, missing, symbol-missing,
  and ABI-mismatched images. Successful loads are cached by ID and their
  `DynamicLibrary` objects are held for process life. Native tests verify host
  ABI mismatch, off-main initialization, idempotent initialization, conflicting
  registration, nil factory results, view construction/deallocation, bridge
  shutdown, and that the image remains loaded through teardown.
- Package-local analysis and the real build-hook asset invocation pass. Runtime
  tests cover strict declaration parsing, hook invocation/staging, generated
  build metadata, missing declarations/images, and one-time initialization.
  C11/C++20 headers, bridge registry tests, dynamic image tests, and the complete
  `make test` regression pass.
- Real Developer JIT and Release AOT hello bundles both report dependency-owned
  view initialization, two Timer ticks, Dart menu action, deferred close/reply,
  window close, handle release, and exit 0 through the same Dart facade. Both
  stage only the declared hook dylib; deep code-signature verification passes.
  The official Engine checkout remains clean at the pinned revision.

## 2026-09-04 — Terminal renderer native capability package

- Purpose: move the accepted terminal-specific `MTKView` shell out of the Dart
  Terminal application repository and into a dependency-owned native capability
  that can later own CoreText/Metal rendering resources without enlarging the
  generic AppKit or runtime layers.
- Scope: one `dart_terminal_renderer_macos` Dart package, versioned plugin ABI,
  Objective-C view implementation, build hook, Dart initialization/view
  facade, native contract tests, native-asset test, and documentation.
- Out of scope: terminal grid semantics, glyph shaping, atlas management,
  render submission, shaders, input/IME, and switching Dart Terminal's product
  build to the new package; that compatibility migration remains the final
  ordered packaging task.
- Dependencies: completed native capability contract `10f5425`, public
  `dart_appkit` view handles, and `dart_macos_runtime` process-lifetime image
  retention.
- Completion requires package-local formatting/analysis/build-hook checks,
  warning-clean native tests for view creation/attachment/release, complete
  `dart_appkit` regression, clean source inventories, and reviewed repository
  state.
- Initial fact: the existing `TerminalMetalView` is a paused, on-demand,
  framebuffer-only, flipped `MTKView` with autoresizing enabled and no delegate.
  It currently registers its class directly against an AppKit C++ helper and
  contains no terminal grid or GPU submission semantics.
- Migration decision: preserve provider identifier
  `dart_terminal.TerminalMetalView` for compatibility, but give the package its
  own `dtr_*` ABI and register a retained-view factory through
  `da_native_extension_services_v1`. The Dart facade is the only consumer entry
  point; application code does not receive Objective-C pointers.
- Added the package-owned Objective-C view, C-compatible ABI header, Dart 3.13
  build hook, `TerminalRendererMacos` facade, native-asset probe, and dynamic
  loading contract test. Generic host and AppKit bridge source inventories did
  not gain renderer implementation files.
- The first native ownership run expected the `MTKView` live count to reach
  zero synchronously when its hidden test window was released. AppKit defers
  part of `MTKView` teardown through its main run loop. The final contract now
  verifies handle invalidation and window retention synchronously, replaces the
  content view through the public API, drains one bounded main-loop turn, then
  requires zero renderer instances. This preserves the leak gate without
  encoding an invalid immediate-deallocation assumption.
- Focused C11/C++20 header compilation, warning-as-error Objective-C/native
  tests, Dart analysis, actual build-hook dylib generation, and native asset
  symbol calls pass.
- The complete `make test` regression passes, including bridge, Runner shell,
  message pump, event encoder, lifecycle, diagnostics, both native capability
  suites, runtime builder, all Dart APIs, example Kernel, real FFI, and legacy
  compatibility. The renderer dylib exports only `dtr_abi_version`,
  `dtr_initialize`, and the test diagnostic `dtr_debug_live_view_count` from
  project code.
- Source-inventory search confirms that renderer symbols and implementation do
  not occur in generic runtime, generic runner, or `dart_macos_runtime` source.
  `git diff --check` passes and the official nested SDK remains clean.

## 2026-09-04 — Reusable macOS PTY capability package

- Purpose: provide the process/PTY half of the Phase 2 vertical slice as a
  reusable dependency so Dart applications own sessions and terminal semantics
  without compiling C/C++ or depending on platform implementation paths.
- Scope: an AppKit-independent `dart_pty_macos` package; versioned C ABI;
  audited child exec path; one native reactor thread per live PTY; bounded
  asynchronous read delivery and write admission; resize, signals, close and
  reap; Dart facade; fake backend; native and Dart integration harnesses; and
  the minimum generic code-asset staging needed by non-AppKit capabilities.
- Out of scope: VT parsing/grid state, terminal query replies, pane policy,
  renderer submission, shell integration protocols, and switching the Dart
  Terminal product build; the final ordered migration owns that switch.
- Dependencies: the accepted Phase 0 `forkpty`/immediate-`execve` and kqueue
  batching spikes, Dart 3.13 native build hooks, and the generic runtime builder.
- Completion requires interactive shell/cwd/env/TTY evidence, resize and
  foreground interrupt, partial data and a bounded 10 MiB burst, write
  backpressure, graceful/forced close, exit/reap, stale handles, zero native
  sessions, fake-backend lifecycle tests, actual hook output, full regression,
  clean SDK, and reviewed source/export inventories.
- Initial design: `dpty_*` uses size/version-prefixed configuration, opaque
  generation handles, fixed-width callback events, copied argv/env/cwd before
  `forkpty`, a separately audited C child object, and explicit read ACK credits.
  Native callbacks may originate on the reactor thread; the Dart facade uses a
  listener-style native callback and never blocks the UI isolate on FD waits.
- Added `dart_pty_macos` with no AppKit dependency. `dpty_session_create`
  validates and copies the absolute executable/cwd, complete argv/environment,
  initial size, callback, and bounded queue limits. A slot/generation registry
  rejects stale handles after automatic child reaping and explicit destroy.
- The native reactor owns fork/exec confirmation, kqueue read/write/process/user
  filters, ordered output buffers retained to ACK, high/low read watermarks,
  whole-write admission, resize, foreground process-group signals, SIGHUP close
  and deadline-based SIGKILL, exact exit status, descriptors, and `waitpid`.
  Its caller-facing operations only copy or enqueue bounded work.
- The child branch remains a separately compiled C object. Its undefined-symbol
  audit permits and observes only errno access, `close`, optional `chdir`,
  `execve`, `write`, and `_exit`; no Dart, C++, allocator, Objective-C, logging,
  or lock symbol is reachable after `forkpty` returns zero.
- Added the public `PtyCommand`, `PtySize`, `PtyProcess`, `PtyBackend`, write
  admission, signal, exit, and stats types. The real backend uses
  `NativeCallable.listener`, copies each output chunk before ACK, and keeps that
  listener alive only while native sessions exist. `FakePtyBackend` exercises
  the same public lifecycle without native I/O.
- The first 10 MiB test appeared to stall after read-credit recovery even
  though native stats kept advancing. Its marker predicate rescanned the entire
  growing output on every callback, producing quadratic test work. A bounded
  256 KiB recent-marker window fixed the harness without relaxing byte-count or
  high-water assertions.
- Setting the listener permanently not-keep-alive then let an isolate awaiting
  its first native event exit early, causing the reactor to call an invalid
  trampoline. The final facade toggles `keepIsolateAlive` from the live-session
  map: the first session enables it and the final exit/error disables it. Real
  callback tests now complete and the standalone Dart process exits normally.
- Extended manifest schema 1 compatibly with optional plain `nativeAssets`.
  The builder runs the same official hook pipeline and stages/records those
  dylibs without inventing an AppKit initializer. `bundleFrameworkPath`
  validates their fixed Frameworks location. Existing manifests without the
  optional field remain valid.
- Focused native tests pass C11/C++20 headers, the child audit, asynchronous
  start, interactive/login TTY, cwd/environment, resize, foreground SIGINT,
  split UTF-8, a 10 MiB ACK-credit burst, bounded write rejection, exit 37,
  ECHILD reaping, asynchronous ENOENT, graceful HUP exit, forced SIGKILL, stale
  generations, and zero live sessions. Dart analysis and actual hook execution
  pass fake lifecycle plus real callback/process/error cases; runtime manifest,
  framework-path, and staging tests also pass.
- The complete `make test` regression passes with the new PTY native/Dart
  suites and plain-asset runtime tests alongside every existing bridge, host,
  renderer capability, example, FFI, and compatibility check. The PTY dylib
  links only libc++ and libSystem—not AppKit—and its project exports are the
  versioned `dpty_*` session/error/debug surface.
- Source-inventory search finds no PTY implementation file or `dpty_*` symbol
  in the generic host/runner sources. `git diff --check` passes and the pinned
  official SDK worktree remains clean.

## 2026-09-04 — Declarative Dart helper packaging

- Purpose: remove the last product-specific worker executable assembly from
  Dart-only macOS applications while keeping worker protocol and lifecycle
  policy outside the generic runtime.
- Scope: an optional manifest list of helper name/entrypoint pairs, generic
  self-contained Dart executable compilation, `Contents/Helpers` staging,
  build-manifest provenance, validated Dart lookup, and regression coverage.
- Out of scope: product worker arguments, process supervision, IPC framing,
  restart policy, and embedding another root isolate in the AppKit host.
- The helper is deliberately an ordinary executable. This preserves process
  isolation and lets both root runtime modes use one declarative contract
  without copying a developer SDK into the application bundle.
- The PTY facade now also accepts an explicit absolute dylib path. Ordinary
  `dart run` and `dart test` keep the native-assets mapping path, while custom
  embedded roots can open the manifest-staged Frameworks image without relying
  on an SDK tool's launch-time mapping.
- The first Dart Terminal bundle exposed that the generated root wrapper's
  expression body could return a `Future`, but could not type-check an ordinary
  `void main(List<String>)`. The wrapper now invokes the application entrypoint
  through its function value and awaits the result only when it is a Future,
  preserving both supported Dart main shapes without an application pragma.
- Direct `dart compile exe` correctly refused the helper because the product's
  dependency graph contains build hooks. Helper compilation now uses the same
  official hook-aware `dart build cli` pipeline as native capability discovery;
  only the declared helper executable is staged into the application bundle.
- The first Release AOT product smoke exited cleanly but left diagnostics with
  `outcome=running`. Unlike the Developer delegate, the generic Release
  delegate did not complete the shared lifecycle from
  `applicationWillTerminate`, and AppKit can end the process before `run`
  returns. Release now calls the same completion hook after bridge/VM shutdown,
  so final outcome and nonzero requested status are persisted deterministically.
- The product lifecycle regression also retained a host-start failure case.
  The generic host now exposes the equivalent product-neutral
  `DMR_RUNTIME_TEST_HOST_STARTUP_FAILURE` only when the diagnostics test gate is
  present, in both modes. Native tests cover the gate and real product
  integration covers the emitted failure, status, and finalized metadata.
- Final verification: runtime and PTY packages format and analyze cleanly;
  manifest/builder/facade unit tests pass; native lifecycle tests and both
  warning-as-error hosts build; the complete repository `make test` passes.
  The hello-window dependency capability passes real GUI smokes in Developer
  JIT and Release AOT after these changes. Dart Terminal separately passes both
  bundle audits and its complete lifecycle/traffic/resource/shutdown matrix.

## 2026-09-05 — Configurable key event routing

- Purpose: let raw-input applications prevent duplicate AppKit responder
  delivery after an asynchronous Dart key event, eliminating the system beep
  caused by a first-responder view with no native key handler.
- Scope: a typed per-window C/Dart policy, compatibility default, exclusive Dart
  routing with main-menu arbitration, native/Dart/legacy tests, and public
  architecture/ABI documentation.
- Out of scope: terminal key encoding, zsh EOF semantics, `NSTextInputClient`,
  marked text, IME candidate placement, or product-specific native code.
- Confirmed cause: `DaWindow.sendEvent:` posts a key event through the Dart port
  and then unconditionally calls `[super sendEvent:event]`; `DaView` accepts
  first-responder status but has no key responder, so ordinary terminal input
  reaches AppKit's unhandled responder path.
- The selected policy is configured before dispatch because Dart port delivery
  is asynchronous and cannot synchronously return a handled disposition. Dual
  routing stays the default; a consuming window explicitly opts into exclusive
  routing. Native main-menu key equivalents retain priority in exclusive mode.
- Added `DaKeyEventRouting` and the additive main-thread-only
  `da_window_set_key_event_routing` ABI. New windows explicitly initialize the
  compatibility default. Invalid values, wrong/stale handle kinds, and
  wrong-thread access return their existing typed statuses.
- Added the public `KeyEventRouting` enum and cached `Window.keyEventRouting`
  property. Failed native updates do not change cached state, repeated values
  do not make duplicate calls, and a bridge without the additive symbol returns
  the deterministic unsupported-version result.
- `DaWindow.sendEvent:` now gives `NSApp.mainMenu` first refusal in exclusive
  mode. A consumed key equivalent is not posted as raw input. Remaining key-down
  and key-up records are posted once to Dart and return before `NSWindow`'s
  responder dispatch; mouse and other events retain their existing route.
- Native tests use a recording first responder to prove that dual mode forwards
  key-down/up while exclusive mode suppresses both, without relying on audible
  output as a test interface. A recording main menu proves shortcut priority.
- Focused `make contract-check native-test`, `make dart-test ffi-smoke`, and the
  complete `make test` passed on 2026-09-05. The complete run included warning-
  clean C11/C++20 headers, bridge/runner/runtime/capability/PTY native suites,
  every Dart package analysis/test, Kernel compilation, real FFI loading, and
  the legacy bridge fallback.
- Final diff review and `git diff --check` passed. Audible confirmation belongs
  to the consuming terminal adoption because the generic hello window retains
  the compatibility default by design.
## 2026-09-05 — opt-in PTY boundary diagnostics for Control-D investigation

- Dart Terminal reported an intermittent path where Control-D writes were
  admitted but no native exit was observed, and a later force-close request
  also crossed the Dart FFI boundary without an exit callback. The existing
  PTY ABI exposes queue admission only, so it cannot distinguish reactor flush,
  terminal semantics, signal delivery, `waitpid`, and callback publication.
- The reusable PTY package will add opt-in, content-free diagnostic events and
  tracked-write receipts. Diagnostics are disabled by default, carry counts and
  opaque IDs rather than bytes, and expose terminal flags/control-character
  identity without commands, environment, cwd, or terminal text.
- Static inspection also found an unbounded `ReadAvailable` loop ahead of
  `ProcessControl`. With a continuously readable master this can starve queued
  writes and force-close control. The fix will add a per-turn read budget plus
  an explicit retry wake, with an output-flood force-close regression.

### Implemented contract and root-cause evidence

- PTY ABI v3 adds `dpty_session_write_tracked`, an opt-in diagnostic flag, and
  fixed scalar events for write enqueue/dequeue/completion/error, session and
  termios/VEOF snapshots, force-close dequeue, each `kill(2)` result, kqueue
  process-exit readiness, `waitpid`, and exit callback publication. The Dart
  facade exposes `PtyWriteReceipt`, `PtyDiagnosticEvent`, and a diagnostics
  stream; the fake backend implements the same surface.
- Ordinary writes and sessions do not emit diagnostics. A tracked request emits
  a bounded number of records, each with an opaque ID and numeric state only.
  Native tests reject non-null data pointers on every diagnostic event and
  prove diagnostics remain empty by default.
- `ReadAvailable` now returns after at most eight 64 KiB batches and explicitly
  wakes the reactor if unread work may remain. Write draining similarly returns
  after eight calls or 512 KiB. This ensures every turn returns to queued
  resize/signal/close processing and `waitpid` without weakening the existing
  high/low-water backpressure contract.
- Signal delivery now observes the actual child process group with `getpgid`,
  avoids duplicate group delivery, records each target/result/errno, and falls
  back to the child PID if no successful group delivery covers it.
- A clean checkout of the pre-change commit `6fa96b8` was built in a temporary
  directory. With `/usr/bin/yes x` continuously feeding an auto-acknowledged
  PTY, force close was not processed within 1 second; the probe required an
  external SIGKILL and reported `bounded=false elapsed_ms=1007`. The identical
  scenario against the bounded reactor completed in 6 ms and observed both
  `forceCloseDequeued` and `exitPublished`. This reproduces the intermittent
  queue/control starvation class rather than inferring it solely from source.

### Verification

- Focused `make dpty-native-test dpty-dart-test` passed. Native coverage includes
  diagnostic opt-in/privacy, tracked-write identity, state snapshots,
  force/signal/reap/publication order, and force-close fairness during continuous
  output. Dart coverage proves ABI v3 mapping and real listener delivery.
- Complete `make test` passed. All C11/C++20 warning gates, native bridge,
  runtime, renderer, PTY, Dart package, launcher, Kernel, FFI, and legacy-event
  regressions remained green.

## 2026-09-05 — PTY completion after an external Dart reap

- Purpose: prevent a terminated native PTY child from remaining logically live
  when the stock Dart macOS process handler reaps it before the PTY reactor.
- Scope: preserve kernel exit status, distinguish PTY-owned and external reap,
  clear stale writes, publish one exit, and cover normal/signal exits plus a
  real competing Dart child. The stock Dart Engine remains unmodified.
- A real Dart Terminal log and a minimal reproduction both recorded tracked
  Control-D completion, kqueue process-exit readiness, then
  `waitpid=-1/ECHILD` while a `Process.start` worker remained alive. The pinned
  stock runtime uses PID-unrestricted `wait()` and discards children absent
  from its private process list, proving a child-reap ownership race distinct
  from the earlier output-flood fairness defect.
- PTY ABI v4 requests `NOTE_EXITSTATUS`, records whether the kernel status is
  valid, and adds an explicit `externalReapObserved` diagnostic. The reactor
  prefers its own PID-specific `waitpid`; only a matching kernel exit with valid
  status can recover `ECHILD`. Pending input is then cleared, output drains, and
  the existing single exit publication reports the retained normal or signal
  status.
- Native tests install a blocking competing waiter and prove external normal
  exit 37 and SIGTERM retain exactly the same raw wait status reported by
  kqueue. A real Dart FFI test keeps a `Process.start` child alive while
  Control-D ends a PTY reader and proves status 37, external-reap
  classification, exit publication, disposal, and zero live sessions.
- Focused `make dpty-native-test dpty-dart-test` passes, including C11/C++20
  warning gates, analysis, the two deterministic native external-reap cases,
  and the real stock-Dart competing-reaper case. Complete repository
  `make test` also passes every bridge, runner, runtime, renderer, PTY, package,
  launcher, Kernel, FFI, and legacy-event regression.

## 2026-09-06 — Allowlisted external URL opening

- Added the closed `AllowedExternalUrl` Dart value type and a 4096-byte policy
  for absolute `http`, `https`, and `mailto` targets. Web hosts are mandatory;
  credentials, arbitrary schemes, raw controls/whitespace/backslashes,
  bidi/invisible characters, malformed escapes, and their unsafe encoded forms
  are rejected before FFI.
- Added an optional ABI-v1 symbol that repeats the complete validation on the
  AppKit main thread before calling `NSWorkspace.openURL`. The integer output
  distinguishes a refused workspace request from a bridge error and is zeroed
  on every failure path. Current bindings return unsupported-version status 8
  against an older image.
- Native tests inject a recorder only after policy validation, proving accepted
  targets dispatch exactly once and rejected targets never reach an opener.
  This avoids launching a browser or mail client. Dart tests cover the public
  type, exact-value preservation, false/error/lifecycle behavior, FFI thread
  guard, and legacy fallback.
- The first Dart test rejected a valid fragment URL because `Uri.isAbsolute`
  excludes fragment-bearing references; the policy was corrected to require a
  concrete allowlisted scheme instead. The first full native run then exposed
  over-rejection of ordinary `%20`; decoded ASCII space is now allowed while
  encoded control, backslash, bidi, and invisible characters remain blocked.
- Complete `make test` passed every bridge, runner, runtime, renderer, PTY,
  package, launcher, Kernel, FFI, and legacy-event regression after the policy
  corrections.

## 2026-09-06 — Copied terminal accessibility snapshot

- Purpose: expose the terminal renderer's visible text, selection, and cursor
  through the native `TerminalMetalView` without adding terminal semantics to
  generic `dart_appkit` views or synchronously entering Dart from VoiceOver.
- Terminal renderer capability ABI version 10 adds a bounded, versioned packet
  containing UTF-8 text, canonical UTF-16 line records, a terminal-column to
  UTF-16 boundary table, optional selection/cursor, and logical cell metrics.
  The Dart facade validates all topology and ranges before encoding it and
  requires strictly increasing generations.
- The provider copies and independently validates the complete packet before
  replacing its immutable native state. Rejected stale or malformed packets
  preserve the prior state. Limits are 4 MiB UTF-8, 2 Mi UTF-16 code units,
  4096 lines, 4096 columns per line, and a 9 MiB packet.
- `DtrTerminalMetalView` is a read-only AppKit accessibility text area with
  visible/shared ranges, selected text and insertion point, line/index/range
  navigation, attributed strings, point lookup, and screen-coordinate range
  frames. Selection/cursor endpoints must match published terminal-column
  boundaries, so a wide emoji continuation cannot split its surrogate pair.
  Focus follows first-responder state. Value and selected-text notifications
  are emitted only when their corresponding state actually changes.
- Native acceptance creates a real Metal view and window, publishes a two-line
  snapshot containing a wide emoji, verifies all selectors and geometry, then
  proves identical updates do not notify, cursor-only updates notify only the
  selected-text channel, and rejected packets do not corrupt native state.
  Dart tests verify deterministic packet bytes plus malformed topology, ranges,
  surrogate boundaries, cursor mapping, generations, and all declared limits.
- The first warning-clean native compile rejected Foundation's `MIN`/`MAX`
  macros as GNU statement expressions under `-Wpedantic -Werror`; explicit
  comparisons replaced those macros. A later emoji fixture exposed an expected
  UTF-16 offset that still assumed an ASCII character; the assertion was
  corrected to the cursor's actual offset after the surrogate pair.
- Focused `make terminal-renderer-native-test terminal-renderer-dart-test`
  passes after these corrections. The complete repository verification is
  also green: warning-clean C11/C++20 headers, every native capability suite,
  all Dart analysis and tests, launcher/Kernel compilation, real FFI loading,
  and the legacy bridge fallback passed under `make test`.
- The content-free native acceptance operation used by product integration
  additionally requires the view to be the focused first responder, observes
  at least one focused-element notification, and verifies the independently
  retained cursor line and range frame. The focused native suite remains green.

## 2026-09-08 — Content-free PTY foreground-process snapshot

- Purpose: let a Dart application make pane close/quit decisions from current
  PTY ownership rather than stale diagnostic events or terminal content.
- PTY ABI v5 adds the size/version-prefixed `DptyProcessSnapshotV1` and
  `dpty_session_get_process_snapshot`. The same-call result contains only the
  child PID, its owning process group, the terminal foreground process group,
  per-field syscall errors, and exit state. It does not inspect or expose a
  process name, argv, environment, cwd, or terminal bytes.
- Snapshot reads are serialized against master-FD replacement/closure so a
  concurrent session exit cannot make `tcgetpgrp` observe a reused descriptor.
  Individual lookup failure leaves its ID absent and records errno while the
  overall typed snapshot remains usable for conservative policy.
- Native coverage observes the idle zsh group, a distinct `sleep` foreground
  job, exited/unavailable state, and stale-handle rejection. Dart facade and
  fake-backend coverage pin typed availability and identity semantics.
- The first format/focused-test invocation was denied before tests because the
  sandbox could not overwrite this adjacent worktree or update Dart telemetry
  session metadata. It made no successful formatter change; verification is
  repeated with telemetry disabled and the required worktree permission.
- Focused `make dpty-native-test dpty-dart-test` passes warning-clean header and
  native compilation, child-symbol audit, the native process-group scenarios,
  real Dart FFI, fake availability/error semantics, lifecycle, force-close,
  diagnostics, and external-reap recovery. The complete `make test` also
  passes all bridge, Runner, runtime, renderer, PTY, package, launcher, Kernel,
  FFI, and legacy-event checks.

## 2026-09-08 — Test-only deferred application-termination request

- Purpose: let a real product integration fixture enter AppKit's native
  deferred application-termination state and validate its operation-ID reply
  without terminating the host before the fixture can inspect atomic refusal.
- The main-thread-only `da_debug_request_application_termination` calls the
  same `HandleApplicationShouldTerminate` state machine as the runtime
  delegate, requires it to return terminate-later, and never enables the
  programmatic termination bypass. It is exposed to Dart only through
  `package:dart_appkit/testing.dart`.
- The hook adds no event or payload type and leaves `DA_ABI_VERSION` and event
  protocol v6 unchanged. FFI lookup is optional so an older bridge fails with
  typed unsupported status only when the test hook is requested.

## 2026-09-08 — Bounded PTY delivery for UI-isolate parsing

- A four-pane terminal product acceptance found that one 64 KiB visible-output
  delivery occupied synchronous parser and transcript processing for 162070
  microseconds in Developer JIT, versus a 23476-microsecond same-launch idle
  input-to-Metal baseline. The existing native queue and reactor-turn bounds
  prevented growth but did not meet the consumer's 2x cross-pane latency gate.
- A global reduction was rejected because the existing throughput contract
  requires 64 KiB burst deliveries. Instead, ABI-v5's size-prefixed session
  config gains an optional suffix bound: an old prefix, zero, or an ordinary
  command preserves 64 KiB, while a synchronous parser consumer can select
  4 KiB. The ABI version, ordered ACK protocol, configurable 1 MiB/512 KiB read
  watermarks, queue caps, and eight-read reactor-turn budget are unchanged.
- Native capability acceptance now pins the 64 KiB default, a 4 KiB command,
  and an old config prefix. Dart coverage pins command validation and defaults;
  focused PTY native/Dart tests and the consuming 100 MiB Developer JIT product
  gate are required before this prerequisite is complete.
- The first native formatting command resolved the PATH-provided Chromium
  wrapper and exited because this repository is not a Chromium checkout; it
  changed no file. Formatting is repeated with Xcode's concrete clang-format
  binary. Dart formatting completed with no changes.
- The first focused native run rejected an assertion that a default burst must
  produce an exactly 64 KiB callback. A PTY `read(2)` may legitimately return a
  smaller available chunk, so the contract is an upper/default configuration,
  not a minimum observed event. The corrected test requires a positive event at
  or below 64 KiB. This also showed that an 8 KiB consumer request can remain
  above the platform's natural chunk; the terminal selects 4 KiB and the
  configured native fixture requires every event to stay at or below 4 KiB.
- The corrected native contract then passed, as did package analysis and the
  first seven Dart PTY cases. The pre-existing competing-reaper case reached
  the correct exit status but did not observe its race-dependent
  `externalReapObserved` event before calling `firstWhere`; the batch changes do
  not touch reap/event ordering. It is rerun once to distinguish an existing
  race from a reproducible regression before changing that coverage.
- The immediate focused Dart-only rerun passed all ten cases, including the
  competing-reaper event, without a source change. The transient race is
  recorded but not hidden by weakening its assertion.
- The first terminal Developer JIT rerun with only the 512-byte delivery cap
  still measured 168436 microseconds against a 28246-microsecond idle baseline
  (5.964x). The listener facade acknowledged native data before synchronously
  publishing it, so the reactor could refill its 1 MiB credit while parser work
  remained queued. ACK now occurs after the synchronous stream delivery
  returns. The terminal consumer pairs its 4 KiB delivery with a 4 KiB/0
  high/low watermark, admitting the next native chunk only after the current
  parser callback has returned; ordinary consumers keep existing defaults.
- Focused native and Dart PTY suites pass after post-consumer ACK and the 4 KiB
  one-batch terminal setting. The consuming Developer JIT hierarchy also
  passed its unchanged 2x 100 MiB flood gate in 16626 ms with every existing
  focus, IME, metadata, Close/Quit, cleanup, and worker assertion retained.
- Complete `make test` passes after the PTY change: scaffold, bridge, Runner,
  message pump/event encoder, runtime/capability/renderer/native PTY contracts,
  every package analysis and Dart suite, launcher/Kernel compilation, FFI
  smoke, and legacy-event fallback all remained green. Native code compiled
  warning-clean under C11/C++20 and the worktree diff passed whitespace checks.

## 2026-09-09 — Cooperative Dart event turns between bounded PTY batches

- The consuming terminal's isolated Developer JIT and Release AOT 100 MiB
  cross-pane gates passed after 4 KiB delivery and consumer-completed ACK, but
  a complete runtime matrix reproduced Release AOT input starvation: 1022984
  microseconds during flood versus a 23901-microsecond same-launch idle
  baseline (42.801x). The input still preceded flood completion and all native
  credit, render scheduling, frame, and cleanup bounds held.
- A 4 KiB high-water mark limits retained bytes but immediate ACK on the same
  Dart native-listener event lets the reactor enqueue the same port's successor
  indefinitely. That does not guarantee a ready timer or another PTY port a
  turn. `PtyCommand.yieldBetweenReadBatches` therefore adds an opt-in Dart
  facade policy: synchronous consumer delivery still finishes first, then the
  ordered ACK runs on a later event-loop turn. The default remains false, and
  the C ABI/native reactor are unchanged.
- The initial implementation paired equal batch/high-water sizes and zero low
  water with the deferred ACK. Its new real 1 MiB/4 KiB test was intended to
  pin the false default, true opt-in, exact one-turn separation, byte/batch
  bounds, exit, and zero live-session cleanup before the full consumer matrix.
- The first focused test rejected the assumption that equal byte batch/high
  water alone means one outstanding event. It received 1025 callbacks for
  1048578 bytes with a 1024-byte natural maximum and observed adjacent
  callbacks without the timer barrier. The extra two bytes were the input line
  echoed before the child applied `stty -echo`; more importantly, partial
  `read(2)` results let the native reactor fill 4 KiB with several events before
  Dart handled the first one.
- The size-prefixed config therefore appends an opt-in cooperative flag. Native
  reads pause before publishing each opted-in batch and resume only after its
  ordered ACK; the Dart facade defers that ACK by one event turn. A config
  prefix ending before the new flag still retains the previously added
  `read_batch_bytes`, while the older prefix retains the 64 KiB default. The
  real test now waits for an echo-disabled readiness marker before releasing
  its exact 1 MiB payload, so byte accounting and turn separation are both
  deterministic.
- Warning-clean native and Dart focused suites pass with the one-batch pause,
  deferred ACK, readiness handshake, exact 1 MiB accounting, and all existing
  lifecycle cases. Aggregating immediately available nonblocking reads into
  the configured 4 KiB batch also passed those suites, but did not restore
  product throughput: Developer JIT met the fairness gate at 8186 versus 25606
  microseconds (0.320x), then the complete hierarchy still exceeded its 120
  second outer deadline after the flood.
- The next bounded design would retain exactly one native batch in flight,
  ACK the first three synchronously consumed callbacks immediately, and defer
  every fourth ACK to the next Dart event turn. This caps one port's chain at
  four parser callbacks while reducing timer turns by four. The edit was not
  applied because automated safety review requested explicit user approval for
  the immediate/deferred ACK interaction; the worktree remains at the slower
  one-yield-per-batch implementation pending that approval.
- The user explicitly approved the maximum-four-callback design and required
  `dart_appkit` to remain a flexible general-purpose library. The public option
  is therefore `readBatchesPerEventLoopTurn`, not a terminal-specific boolean:
  zero preserves every prior consumer's immediate ACK/native delivery, while
  values one through eight select an application-owned fairness budget. The
  terminal alone opts in and currently passes two; no package default changes.
- For any nonzero limit, native retains at most one unacknowledged batch. The
  facade ACKs the first `limit - 1` synchronous deliveries immediately and
  defers only the limit-th ACK. Thus limit one is the conservative prior trial,
  limit four bounds a port to four callbacks, and limit eight offers a larger
  throughput budget without changing byte order. Real coverage also correlates
  callback count with native batch/pause stats and maximum in-flight bytes.
- Focused native and Dart PTY suites passed the configurable limit. The first
  Developer JIT product rerun then completed the exact 100 MiB fairness work at
  27115 microseconds versus a 26539-microsecond baseline (1.022x), but failed
  final cleanup with native destroy status 3. The native exit loop considered
  any in-flight byte count below the high-water mark to be sufficient capacity
  for `FinishExit`; a final partial batch can satisfy that condition while it
  is still unacknowledged, so exit publication raced the deferred ACK and
  `CanDestroy` correctly refused the nonempty outstanding queue.
- Exit must instead wait for `outstanding_` to be empty after EOF. Cooperative
  delivery already marks each batch read-paused, so its existing watermark ACK
  wake is sufficient; ordinary delivery retains its bounded reactor poll. This
  generic lifecycle correction keeps every payload owned until its exact ACK
  without adding cross-thread exit state.
- Focused PTY suites passed that correction and the next Developer JIT product
  run proved exact cleanup, but its four-callback consumer sample varied to
  57337 versus 24357 microseconds (2.355x). The reusable package retains its
  configurable zero-through-eight API; the terminal consumer is free to choose
  two for greater latency margin while other applications keep zero or select
  their own tested budget.
- The terminal's two-callback selection passed the real four-pane hierarchy in
  both supported runtimes with exact 100 MiB accounting and clean native
  teardown. Developer JIT measured 27210 versus 26221 microseconds (1.038x),
  and Release AOT measured 23723 versus 25299 microseconds (0.938x).
- `make test` passed the complete adjacent repository after the configurable
  API and outstanding-empty exit correction, including warning-clean native
  bridge tests, all package analyzers, the real configurable-turn PTY case,
  AppKit API tests, launcher tests, and FFI smoke tests. Formatting reported no
  source changes.

## 2026-09-10 — Idempotent Runner activation-policy application

- Dart Terminal's regular-policy runtime acceptance exposed a host-starting
  failure on macOS 26.6.2 before application Dart ran. Launching a signed
  minimal `APPL` probe through LaunchServices reported an already-effective
  `NSApplicationActivationPolicyRegular`, while setting that same policy
  returned false and left the effective policy unchanged.
- `ApplyRunnerActivationPolicy` previously treated every false setter return as
  a fatal transition failure. It now accepts an already-matching effective
  policy first and calls `setActivationPolicy:` only when AppKit must perform a
  real transition. Invalid or rejected transitions retain the existing typed
  startup failure; manifest defaults and public ABI are unchanged.
- The native Runner configuration test uses the command-line AppKit process's
  already-effective prohibited policy to cover the same idempotent branch. It
  starts with a stale error string, verifies success clears it, and verifies
  that the effective policy does not change.
- `make runner-configuration-test` rebuilt the Objective-C++ source with all
  project warnings as errors and passed every parsing, atomic-failure, bound,
  and activation-policy assertion.
- `make test` passed the complete noninteractive regression matrix: scaffold,
  bridge, Runner, scheduler/event encoding, runtime lifecycle/diagnostics,
  capability/renderer/PTY native contracts, all package analyzers and Dart
  suites, launcher/Kernel compilation, FFI bridge, and legacy-event fallback.

## 2026-09-11 — Bounded attributed multiline editor surface

- Dart Terminal's editable Settings design requires NORMAL and INSERT to use
  exactly one visual editor: changing interaction mode must not replace the
  buffer or remove syntax colors. The reusable boundary is consequently a
  generic `TextEditor`, not a terminal/settings-specific native view.
- `TextEditor.setDocument` publishes one text, UTF-16 selection, and attributed
  projection. Text is capped at 16 MiB of UTF-8; projections are capped at
  65,536 ordered, positive, non-overlapping runs whose endpoints cannot split
  a surrogate pair. `setStyleRuns` resets and reapplies foreground/underline
  attributes on the existing `NSTextStorage`, preserving its string and
  selection. `isEditable` and `setSelection` mutate that same surface.
- The native object is a generic-view handle wrapping one `NSScrollView` and
  one plain-text `NSTextView`. It retains native selection, scrolling,
  responder/input-client behavior, marked text, Undo infrastructure, and find
  panel support while disabling rich paste, smart substitution, and automatic
  spelling changes. `da_window_make_first_responder` first validates the
  wrapper's window hierarchy, then targets its inner `NSTextView`.
- The additive C structs and functions keep ABI/event-protocol versions
  unchanged. Dart FFI discovers every editor symbol optionally through the
  separate `NativeTextEditorBindings` capability, so older bridges continue to
  load and return unsupported status 8. Existing third-party `NativeBindings`
  fakes do not gain source-breaking abstract members.
- Public/fake tests cover atomic configuration/document transfer, editable and
  UTF-16 selection changes, style-only text preservation, invalid scalar and
  ordering boundaries, limits, and release. Native tests inspect actual sRGB
  foreground/underline attributes, removal of stale underline attributes,
  identical text-storage identity across restyling, native snapshot state,
  inner first-responder routing, invalid configuration/runs/UTF-8, wrong handle,
  stale handle, and wrong thread. Current and legacy FFI smoke tests cover the
  new signatures and optional-symbol fallback.
- The first formatting command used package paths while already inside the
  package and then encountered the sandboxed Dart telemetry timestamp; it
  changed no source. The corrected relative paths with analytics suppressed
  completed. Initial analysis also showed that a value typed as
  `NativeBindings` is not promoted to an unrelated optional interface; an
  explicit checked cast now follows the capability guard.
- The first expanded native build rejected an unused test helper under
  `-Werror`; it was removed. The next run exposed two test-only `NSString`
  pointer comparisons even though both printed equal; assertions now use
  `isEqualToString:`. No editor implementation change was needed for those
  comparisons.
- A whole-file `clang-format --dry-run` was not usable as an incremental gate:
  the `depot_tools` wrapper requires a Chromium checkout, while Xcode's binary
  reports extensive pre-existing style differences across these bridge files.
  No bulk reformat was applied. The established warning-as-error builds and
  `git diff --check` remain clean.
- Verification passes: package formatting and analysis; the Dart API suite
  including `attributed multiline text editor`; warning-clean native bridge
  tests; current Mach-O FFI smoke; and legacy bridge fallback smoke. Complete
  `make test` also passed scaffold/header contracts, Runner and scheduler,
  runtime/capability/renderer/PTY suites, every package analyzer/test,
  launcher/Kernel compilation, and both FFI paths without regression.

## 2026-09-11 — Retina glyph raster logical-size correction

- A Dart Terminal screenshot comparing its Metal surface with the AppKit
  Settings editor showed that both selected system monospace regular 14pt, but
  the terminal glyph ink was visibly much smaller than the native editor ink.
- A direct pixel probe of the current renderer confirmed the mismatch for the
  same system-monospace 14pt `M`: 1x produced a 10x13 record with 8x11 ink,
  while 2x produced a 17x23 record but still only 8x11 ink. Coverage was also
  effectively unchanged (9575 versus 9574).
- `RasterizeGlyph` scales the bitmap bounds and origin, but draws CoreText into
  an unscaled bitmap context. The resulting device-pixel record grows while
  the glyph itself remains at 1x. Existing checks only required larger 2x
  storage and nonzero coverage, so they did not enforce logical ink parity.
- The correction applies the requested device scale once to the Core Graphics
  context while retaining the existing point-space draw position. The same
  probe then measured the 2x `M` ink at 15x21 with coverage 38409; divided by
  two, that is within half a pixel of the 1x logical 8x11 extent. CJK `日`
  changed from 10x13 to 20x24 device pixels, and the color emoji cluster from
  18x18 to 32x34, with the expected approximately fourfold coverage.
- Dart and native renderer tests now compare nonzero alpha bounds and coverage
  at 1x/2x for alpha, CJK, and color glyphs with explicit quantization
  tolerance. Existing top-down orientation, mixed alpha/color conversion,
  bounds, generation, and ABI checks remain unchanged.
- Focused warning-as-error native capability tests and package analysis/Dart
  native-asset tests pass with the correction. Full repository verification
  also passes: `make test` completed the bridge, Runner, runtime, capability,
  renderer, PTY, package analysis/test, launcher, Kernel, and current/legacy
  FFI matrix without regression.
- The initial formatter check used `--output=none`, which correctly reported
  that the new Dart test would change but did not write the formatting update;
  a repeated check therefore reported the same result. Running `dart format`
  without that dry-run output mode applied the change, and the final
  `--output=none --set-exit-if-changed` check reported `0 changed`.
