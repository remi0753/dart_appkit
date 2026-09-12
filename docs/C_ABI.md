# C ABI and Event Protocol

The public contract is `native/bridge/include/dart_appkit.h`. It contains plain C
types only and compiles as both C11 and C++20. Objective-C/Swift object layouts
never cross the boundary.

Dependency-owned platform packages version their ABIs independently. The
terminal renderer uses `dtr_*`; the AppKit-independent PTY package publishes
`packages/dart_pty_macos/native/dart_pty_macos.h` and `dpty_*`. A change to one
does not consume or renumber the `da_*` ABI.

## PTY capability ABI

`DptySessionConfigV1` is size/version prefixed and all argv, environment, and
working-directory strings are copied before `dpty_session_create` returns.
Opaque handles encode a slot generation and zero is invalid. `start`, `write`,
`resize`, `send_signal`, `close`, and `force_close` only enqueue bounded work;
FD readiness and `waitpid` remain on the session reactor. PTY ABI version 5
retains the idempotent `force_close` operation and adds the size-prefixed
`DptyProcessSnapshotV1`. `dpty_session_get_process_snapshot` copies only child,
owning-process-group, and foreground-process-group IDs, per-field syscall
errors, and exit state. It serializes the same-call `getpgid`/`tcgetpgrp`
observation against master-FD closure and never inspects process names,
arguments, environment, paths, or terminal content. The size-prefixed V1
diagnostic configuration introduced in v3 remains unchanged.
`dpty_session_write_tracked` returns an
opaque request ID for correlating queue admission, reactor dequeue, and native
write completion. Diagnostic callbacks contain only fixed scalar counters,
state flags, process-group/signal results, termios flags/VEOF identity, and
`waitpid`/exit results; they never contain terminal bytes or process launch
strings. The process filter requests `NOTE_EXIT | NOTE_EXITSTATUS`. A successful
PID-specific `waitpid` remains authoritative. If a matching kernel exit event
with valid status is followed by `ECHILD`, the session classifies an external
reap, retains that status, clears pending writes, drains output, and publishes
exactly one exit. A bare `ECHILD` without the matching status is never promoted
to success.

An OUTPUT callback carries at most 64 KiB and borrows its byte pointer until the
exact sequence/length pair is acknowledged in order. The high watermark
disables the kqueue read filter and the low watermark re-enables it. Writes are
copied only when the configured capacity admits the entire call; saturation
returns `DPTY_STATUS_BACKPRESSURED` without waiting. EXIT reports either the
child status or `128 + signal`, after the owning reactor has reaped the PID or
verified that another process-wide waiter reaped it after `NOTE_EXITSTATUS`.
Destroy requires a finished session with no unacknowledged output and retires
that handle generation.

Read and write draining use fixed per-reactor-turn budgets. If work remains,
the reactor explicitly wakes itself before returning to control processing.
This preserves delivery and backpressure while preventing a continuously ready
master FD from indefinitely delaying queued writes, force-close escalation, or
child reaping.

The post-`forkpty` project child branch is a separate C object. It calls only
`close`, optional `chdir`, `execve`, error-pipe `write`, errno access, and
`_exit`; an object-symbol allowlist enforces this on every test run.

## Calls and errors

UI calls and synchronous registry release are main-thread-only.
`da_release_async`, ABI/status inspection, and documented debug/finalizer
entry points are safe on any thread. Status-returning calls never throw across
the ABI. `da_get_last_error` exposes thread-local detail; its message is
borrowed until the next bridge call on that thread.

Strings are an explicit UTF-8 pointer plus byte length. A null pointer is valid
only for a zero-length string. The bridge validates and copies the bytes before
returning and never retains Dart-owned memory.

`DaPasteboardText` is a same-call snapshot. `has_text == 0` distinguishes an
absent public-text item from a present empty string. Its UTF-8 pointer is
borrowed from thread-local bridge storage only until the next pasteboard read
on that thread; FFI callers copy it before returning to Dart. The associated
nonnegative change count describes that read, but is observational rather than
a compare-and-swap token. Write and clear return their resulting count.

Output pointers are mandatory. On failure, the bridge leaves them in a safe zero
state. Handles are opaque 64-bit values; zero is always invalid. Generated
handles stay within positive signed 64-bit range so the same value is preserved
in both FFI `Uint64` calls and the event protocol's signed integer slot.

`da_window_create_configured` accepts a size-prefixed
`DaWindowConfiguration`. Version 1 maps only the stable titled, closable,
miniaturizable, and resizable bits; zero is the valid borderless style and any
unknown bit fails before allocation. `da_window_create` remains the unchanged
compatibility entry point and supplies all four bits. Current Dart bindings
discover the configured symbol lazily, fall back to the legacy call only for
that default, and report unsupported version for a non-default style on an old
native image.

## Base and display-text view creation

`DaViewConfiguration` is size-prefixed and selects first-responder acceptance
plus a closed width/height autoresizing mask. `da_view_create_configured`
validates the prefix, boolean, reserved field, and mask before allocation.
`da_view_create` remains the compatibility wrapper with first-responder and
both autoresizing dimensions enabled.

`DaTextViewConfiguration` embeds that base configuration and adds closed font
kind/weight and color kinds, font size, four logical padding values, and two
color records. Font size is bounded to 512 points, each padding extent to 4096
points, and a copied exact named-font value to 256 UTF-8 bytes. Named fonts use
their exact AppKit name and therefore require regular weight in the separate
weight field; system and monospaced-system fonts consume the declared weight.
Colors may use dynamic label/window-background roles or finite sRGB components.
`da_text_view_create` remains the exact monospaced-system 18-point regular,
20-point padding, label/window-background compatibility wrapper.

Both configured calls are additive. Current Dart bindings fall back to old
symbols only for exact compatibility configurations and otherwise report
`DA_STATUS_UNSUPPORTED_VERSION`. Registered custom views bypass these values;
their provider remains responsible for native view policy.

## Handle ownership

- Successful create calls return one registry-owned handle.
- Every occupied registry slot records its object kind, positive generation,
  and owning thread domain. Current objects belong to the AppKit main domain.
- Base/default `da_view_create*` returns a generic view handle. Default/configured
  `da_text_view_create*` returns a specialized handle accepted by generic-view
  lookups.
- `da_view_create_custom` copies a non-empty provider identifier, asks the
  native provider registry to construct its `NSView` subclass, and returns the
  instance as a generic view handle.
- `da_window_set_content_view` borrows both handles, accepts either view kind,
  and consumes neither.
- Menu and menu-item create calls return independent handles. Adding an item,
  attaching a submenu, and setting the application main menu borrow every
  handle and consume none; AppKit's retain graph is not a registry lease.
- `da_view_set_context_menu` borrows a generic/specialized view and menu,
  attaches the menu through `NSView.menu`, and consumes neither handle. Zero
  clears the attachment. View release clears its menu; menu release scans only
  a weak set of attached views and clears every matching property before the
  registry reference is dropped.
- `da_view_set_services_text_requestor` borrows a generic/specialized View and
  replaces or removes a copied native snapshot. The requestor retains the View
  weakly, owns no registry handle, and is removed before View release.
- Releasing a menu item clears its target/action/handle before dropping the
  registry reference. Releasing the currently attached main menu detaches it
  from `NSApplication`.
- Text-only calls require the specialized kind and reject a generic view.
- `da_window_close` performs an unconditional programmatic window action but
  does not release ownership. `da_window_request_close` follows the user-facing
  delegate path.
- `da_window_set_represented_file_path` copies at most 4096 UTF-8 bytes into an
  absolute local file URL, while an empty input clears it.
  `da_window_set_tab_accessory` creates or clears an `NSWindowTab` accessory
  owned by AppKit from a size-prefixed rectangle/ellipse configuration. Each
  finite positive dimension is capped at 256 logical points and color remains
  bounded sRGB. `da_window_set_tab_color` is the legacy 8×8 ellipse helper.
  Neither operation inserts a registry object or transfers a handle.
- `da_release` invalidates exactly one live handle. A second release reports
  `DA_STATUS_INVALID_HANDLE`.
- `da_release_async` is safe on any thread. It atomically changes one live
  handle to release-pending and returns without waiting. Pending handles reject
  access and duplicate release but remain retained, counted, and unreusable
  until their domain executor finishes teardown.
- `da_release_finalizer` accepts a handle encoded as a pointer token and uses
  the same exclusive asynchronous-release path.
- AppKit-main completion clears window delegate/handle state before dropping
  the registry reference. Independent AppKit retainers, such as a window
  retaining its content view, keep their normal ownership.
- Shutdown closes async admission, returns `DA_STATUS_SHUTTING_DOWN` to new
  requests, owns live and pending entries, and makes an already queued callback
  harmless.
- A slot at the maximum positive signed generation is retired instead of
  wrapping to a value that could validate an ancient stale handle.

## Native custom-view providers

`dart_appkit_custom_view.h` is a separate Objective-C++ extension surface; it
is not part of the plain-C FFI header. A product registers a non-empty provider
identifier and an `NSView` subclass on the AppKit main thread before Dart
requests the view. The class must support `initWithFrame:`. Registering the same
identifier/class pair again is idempotent, while replacing an identifier with a
different class is rejected.

The provider registry retains class metadata for the process lifetime but
never owns live instances. `da_view_create_custom` constructs the instance on
the main thread and registers it as `ObjectKind::kView`; all later attachment,
generation, domain, release, finalizer, and shutdown rules are identical to
`da_view_create`. Unknown or empty identifiers fail with
`DA_STATUS_INVALID_ARGUMENT`, and a provider that cannot create a view fails
with `DA_STATUS_INTERNAL_ERROR`. Dart receives no class, callback, object
pointer, or arbitrary-handle adoption capability.

The size-prefixed native-extension service table also permits that same
provider to register one opaque synchronous view operation. The additive field
does not change extension ABI version 1: older providers use the original table
prefix, while providers that require the operation verify the larger
`struct_size`. `da_view_perform_custom_operation` first validates the AppKit
main thread, generation-checked view handle, and the exact provider that created
the instance. Only then does it borrow the provider's `NSView` pointer and the
caller payload for the duration of the native callback. Neither pointer nor an
AppKit registry handle is exposed to Dart, and non-provider views, stale
handles, missing operations, and malformed payloads fail closed.
The public Dart `View.performCustomOperation` API copies a `Uint8List` into
temporary native storage for this synchronous call; it exposes neither the
view handle nor the borrowed native pointer.

The terminal renderer capability uses that operation for complete, versioned
accessibility snapshots. ABI version 11 and snapshot version 2 bound the packet,
UTF-8 and UTF-16 text lengths, physical lines, per-line terminal-column
boundaries, and finite nonnegative logical content origin. The provider
validates canonical offsets, exact newline topology, UTF-8/UTF-16 agreement,
surrogate-safe ranges, terminal-boundary selection and cursor positions,
content origin at most 4096 logical points per axis, and a strictly increasing
generation before atomically replacing its native copy. Point lookup subtracts
the origin and rejects padding/out-of-grid points; range frames add the origin
once. Malformed, unsupported-version, or stale packets leave the previous
accessible state intact. AppKit selectors and notifications are implemented by
the provider-owned `NSView`; the bridge never interprets terminal text.

## Event envelope

Version 1 remains the legacy fixed-position list:

```text
[protocolVersion, eventType, windowHandle, monotonicMicros, ...payload]
```

Versions 2 through 12 use the six-field common prefix:

```text
[protocolVersion, eventType, sourceHandle, sourceGeneration,
 monotonicNanoseconds, operationId, ...payload]
```

- `protocolVersion` is negotiated independently from `DA_ABI_VERSION`.
- `eventType` is a `DaEventType` integer.
- `sourceHandle` is the stable registry handle of the originating window,
  menu item, global hot key, or View. Application-scoped v4 events use zero.
- `sourceGeneration` is positive and matches the handle's high 32 bits for
  registry objects. Application-scoped v4 events use zero.
- Timestamps are monotonic rather than wall-clock time. Version 1 uses
  microseconds; versions 2 through 12 use nanoseconds.
- Notifications use operation ID zero. Deferred close/termination requests use
  a positive ID that must be echoed exactly once in the matching reply call.
- Version 12 is current. Version 3 adds window state, version 4 adds lifecycle
  decisions and menu actions, version 5 adds precision scroll, version 6 adds
  outer-frame and native-fullscreen state, and version 7 adds an application
  effective-appearance boolean (`false` light, `true` dark). Version 8 adds
  global-hot-key presses. Version 9 adds View-local Quick Look requests with
  finite x/y coordinates. Version 10 adds bounded plain text returned by a
  Service to its registered View. Version 11 adds a bounded performed
  plain-text or local-file-URL drop with finite target-local coordinates.
  Version 12 adds bounded canonical directory URLs requested by the
  application folder Services provider.
  Version-specific types are suppressed for an older negotiated sink.

`da_debug_request_application_termination` is a main-thread, test-only entry
to the same deferred application decision and operation-ID state used by the
AppKit delegate. It requires active deferral and a current event port, never
sets the programmatic-termination bypass, and does not itself terminate the
host. The Dart wrapper exports it only from `package:dart_appkit/testing.dart`.

Payloads:

| Event | Payload after the version-specific common prefix |
|---|---|
| `WINDOW_CLOSED` | none |
| `WINDOW_RESIZED` | `width: double, height: double` |
| `WINDOW_FOCUS_CHANGED` | `isFocused: bool` |
| `WINDOW_VISIBILITY_CHANGED` | `isVisible: bool` |
| `WINDOW_OCCLUSION_CHANGED` | `isOccluded: bool` |
| `WINDOW_BACKING_SCALE_CHANGED` | `scaleFactor: finite positive double` |
| `WINDOW_SCREEN_CHANGED` | `hasScreen: bool, displayId: int, frame x/y/width/height: double, visible frame x/y/width/height: double` |
| `WINDOW_CLOSE_REQUESTED` | none; positive operation ID in the prefix |
| `WINDOW_FRAME_CHANGED` | `x/y/width/height: finite double`; dimensions are positive |
| `WINDOW_FULLSCREEN_CHANGED` | `isFullscreen: bool` |
| mouse down/up/moved/dragged | `x: double, y: double, button: int, modifiers: int, clickCount: int` |
| `SCROLL_WHEEL` | content `x/y`, precise `deltaX/deltaY`, scroll/momentum phase, device inversion, and modifiers |
| key down/up | `keyCode: int, modifiers: int, isRepeat: bool, characters: string, charactersIgnoringModifiers: string` |
| `APPLICATION_ACTIVE_CHANGED` | `isActive: bool` |
| `APPLICATION_REOPEN_REQUESTED` | `hasVisibleWindows: bool` |
| `APPLICATION_TERMINATE_REQUESTED` | none; positive operation ID in the prefix |
| `MENU_ITEM_INVOKED` | none; reserved v4 record used by the additive menu API |
| `GLOBAL_HOT_KEY_PRESSED` | none; the source handle identifies the owned v8 registration |
| `VIEW_QUICK_LOOK_REQUESTED` | `x: finite double, y: finite double`; the source handle identifies the registered View and the coordinates use that View's AppKit coordinate system |
| `VIEW_SERVICES_TEXT_RECEIVED` | `text: Uint8 typed data`; the source handle identifies the registered View, native admission bounds UTF-8 before posting, and Dart strictly decodes the length-carrying bytes |
| `VIEW_DROP_PERFORMED` | `contentKind: int, x/y: finite double, content: Uint8 typed data`; text is exact bounded UTF-8, while file URLs use a bounded little-endian count/length packet and the source handle identifies the destination View |
| `APPLICATION_FOLDER_SERVICE_REQUESTED` | `disposition: int, directoryUrls: Uint8 typed data`; application source identity is zero, disposition is new tabs or new windows, and directory URLs use the bounded little-endian count/length packet |

Coordinates use the content view's top-left origin. Modifier values use stable
`DaModifier` bits rather than exposing AppKit's enum representation.
Screen rectangles are global AppKit coordinates and may have negative origins.
An absent screen has a zero identifier and zero rectangles; a present screen
has a positive identifier and positive dimensions.

`da_window_set_frame` validates a finite outer frame with positive dimensions,
then asks AppKit to replace it. Native move, resize, and fullscreen callbacks
publish deduplicated `WINDOW_FRAME_CHANGED` records. `da_window_set_fullscreen`
accepts only 0 or 1 and starts AppKit's asynchronous native transition. A
request matching the current or pending target is idempotent; an opposite
target while a transition is pending returns `DA_STATUS_INVALID_ARGUMENT`.
The observed state is reported only by a deduplicated
`WINDOW_FULLSCREEN_CHANGED` record after an enter, exit, or failure callback.
Intermediate frame-state records are suppressed between AppKit's will/did
fullscreen callbacks, and completion publishes observed fullscreen state before
the resulting frame. Existing `WINDOW_RESIZED` delivery remains available
during the transition.
Both functions are additive symbols; a current Dart client loaded against a
legacy image returns `DA_STATUS_UNSUPPORTED_VERSION`.

## Screen resolution and window presentation

`da_application_resolve_screen` resolves current AppKit display state on the
main thread. `DA_SCREEN_SELECTION_MAIN` means the display containing the
keyboard-focus window, `MOUSE` tests the global mouse point against every
display frame, and `MENU_BAR` selects the first AppKit screen. A missing main
screen or mouse hit falls back deterministically to the first valid screen.
The size-prefixed `DaScreenSnapshot` copies the display identifier, full frame,
visible frame, and finite positive backing scale; callers must not cache it
across a later presentation.

`da_window_set_presentation_configuration` maps a closed level enum and typed
collection-behavior mask to `NSWindow`. The current mask supports join-all-
Spaces, fullscreen auxiliary, stationary, and transient behavior only.
`da_window_present` orders an existing window front, optionally activates the
application and restores its content first responder, and animates from one
validated frame to another. `da_window_hide` animates toward a target then
orders the window out without closing or releasing it. Durations are finite and
bounded to 0 through 5 seconds; zero applies the endpoint synchronously.

Each window owns a monotonically changing presentation generation. Present,
hide, direct frame mutation, ordinary show, close, and release invalidate an
older completion. In particular, a stale hide completion cannot hide a window
shown by a newer request. These additive APIs do not change the event protocol;
ordinary focus, visibility, screen, backing-scale, resize, and frame records
remain the observed-state path. A legacy image returns
`DA_STATUS_UNSUPPORTED_VERSION` through the optional Dart binding.

The event poster is injected internally by the Runner. No AppKit delegate enters
an isolate or invokes a Dart closure synchronously. A post that cannot be queued
is dropped; it never blocks AppKit waiting for Dart.

## Key event routing

`da_window_set_key_event_routing` takes a `DaKeyEventRouting` value on the
AppKit main thread. Every new window defaults to
`DA_KEY_EVENT_ROUTING_DART_AND_APPKIT`, preserving the original behavior: a key
is posted to Dart and then follows normal AppKit responder dispatch.

`DA_KEY_EVENT_ROUTING_DART_ONLY` is intended for raw-input views. For key-down,
the application main menu first receives normal key-equivalent arbitration. A
consumed menu shortcut produces its menu action and is not also posted as raw
input. Any remaining key-down or key-up is posted once to Dart and is not sent
through the content view's ordinary responder chain. Mouse and non-key window
events are unchanged.

The setting is per window and does not change event protocol payloads. The
function is an additive ABI symbol: current bindings expose it through the
typed `KeyEventRouting` property, while a legacy bridge without the symbol
returns `DA_STATUS_UNSUPPORTED_VERSION`. No synchronous Dart callback or
handled reply is introduced.

## Lifecycle decisions

Close and termination deferral are disabled by default, preserving the legacy
behavior. Dart must explicitly enable each window or the application before a
user request can produce a reply-required event. At most one request is pending
per target. Repeated delegate callbacks do not create new operations, mismatched
or reused operation IDs are rejected, and deferral cannot be disabled until the
pending request is answered.

`da_window_reply_to_close_request` and
`da_application_reply_to_termination_request` complete the corresponding
AppKit decision. If a v4 event cannot be posted, the bridge fails open and lets
the OS action continue. Programmatic `da_window_close` and
`da_application_terminate` bypass user-request deferral so shutdown cannot
deadlock after Dart has stopped listening for events. Registering a v4 event
port also posts the current application-active snapshot. A v7 registration
additionally posts the current effective light/dark appearance and starts a
deduplicating KVO observation that is replaced by re-registration and removed
at bridge shutdown.

## Global hot keys

`da_global_hot_key_register` creates one exclusive system-wide registration
for a macOS virtual key code from 0 through 127. The modifier mask must be
nonempty and may contain only Shift, Control, Option, and Command. The call is
main-thread-only and returns an owned generation-checked handle; `da_release`
unregisters it before invalidating the handle. A chord already claimed by this
or another process returns `DA_STATUS_GLOBAL_HOT_KEY_CONFLICT`, while other OS
registration failures return `DA_STATUS_GLOBAL_HOT_KEY_REGISTRATION_FAILED`.

A press posts the payload-free v8 `GLOBAL_HOT_KEY_PRESSED` event with the
registration handle as its source. The Dart `GlobalHotKey` facade routes that
record to both the application event stream and the registration-local
`onPressed` stream. Consumers retain the object for as long as the shortcut is
active and dispose the old registration only after a replacement succeeds.

## Secure Event Input

`da_secure_event_input_create` creates at most one generation-checked owner for
the process bridge. `da_secure_event_input_set_desired` stores one Boolean
request and acquires exactly one Carbon Secure Event Input reference only while
the application is active. AppKit activation notifications yield that owned
reference on resignation and reacquire it on activation. Repeated desired
states are idempotent; explicit, finalizer, and shutdown release balance only a
reference successfully acquired by this owner.

`DaSecureEventInputSnapshot` is size-prefixed and contains no input or terminal
content. It separates desired state, owned-reference state, the observational
global system state, and the last `OSStatus`. The global state is never used as
proof of ownership, so the bridge cannot disable a reference held by another
process. Carbon failures return `DA_STATUS_SECURE_EVENT_INPUT_FAILED` with the
numeric status in the last-error message while retaining ownership knowledge
for a later retry.

`da_view_set_secure_input_indicator` accepts hidden, automatic, or manual. It
adds at most one accessible, non-hit-testing overlay to any registered view and
removes it for hidden. The overlay is constrained only to the target's top and
trailing anchors and therefore does not change its bounds or terminal grid
geometry. These are additive symbols under ABI version 1; an older image is
reported as unsupported by the optional Dart binding surface.

## Pasteboard policy

The public pasteboard calls select `NSPasteboard.generalPasteboard` and expose
only `NSPasteboardTypeString`. Reads do not clear or claim ownership. Writes
copy and validate UTF-8, clear existing formats, and publish exactly one public
text item; an empty string remains present. Clear removes every item. All four
operations are main-thread-only and initialize outputs to a safe zero state
before validating the thread or arguments.

Automated native tests call the same conversion helpers with an in-process
pasteboard test double. They never connect to, read, or mutate the user's
general pasteboard. Product code is responsible for limiting
general-pasteboard reads to an explicit user action.

## External URL policy

`da_application_open_external_url_with_policy` accepts at most 4096 URL bytes,
a bounded lowercase ASCII expected scheme, and a closed set of application
condition flags for authority, host, credentials, and path. It rejects an
actual-scheme mismatch and contradictory or unknown flags. Raw controls,
whitespace, backslashes, bidi/invisible formatting characters, malformed
escapes, and percent-encoded controls, backslashes, or bidi/invisible
characters are unconditional library rejections before `NSURL` construction.
The call is main-thread-only, initializes `out_opened` to zero, and invokes
`NSWorkspace.openURL` directly without a shell.

The Dart API fixes an immutable `ExternalUrlPolicy` when the application
attaches. `AllowedExternalUrl` parses under that policy, and
`AppKitApplication.openExternalUrl` revalidates under the attached policy
before forwarding its selected rule to native code. The old
`da_application_open_external_url` remains the exact HTTP/HTTPS/mailto
compatibility policy. Current Dart bindings fall back to that old symbol only
for those exact rules; a custom policy on such an image returns
`DA_STATUS_UNSUPPORTED_VERSION`. Automated native tests replace only the final
workspace opener after validation and therefore never launch an external
application.

## User notification and Dock badge policy

`da_application_post_user_notification` accepts a required notification
identifier of at most 128 UTF-8 bytes and title/body fields of at most 4096
UTF-8 bytes each. Identifiers are restricted to ASCII letters, digits, dot,
underscore, plus, and hyphen. Title and body reject controls, bidi overrides,
and invisible formatting characters, and may not both be empty. All input is
copied before the function returns. The call is main-thread-only, starts an
asynchronous alert-authorization check when needed, and schedules an immediate
`UNNotificationRequest` only if that identifier has not subsequently been
removed or replaced. The bridge retains at most 256 authorization-pending
identifiers and returns `DA_STATUS_LIMIT_EXCEEDED` before growing past that
bound.

`da_application_remove_user_notification` cancels the bridge's pending token
and removes both pending and delivered system notifications for the identifier.
Neither operation exposes or transfers an Objective-C handle. Notification
rate, application-focus suppression, pane ownership, title fallback, and
lifecycle admission remain product policy rather than C ABI behavior.

`da_application_set_dock_badge_label` copies a nullable label of at most 32
UTF-8 bytes, applies the same unsafe-display-text rejection, and uses null to
clear `NSApplication.dockTile.badgeLabel`. It does not interpret progress or
draw a custom Dock tile. Current Dart bindings discover all three additive
symbols independently; an older image returns `DA_STATUS_UNSUPPORTED_VERSION`.

## Menu policy

Menu and item titles plus key equivalents use the same copied UTF-8 convention
as other bridge strings. Shortcut masks accept only the seven stable
`DaModifier` bits and translate them to AppKit flags internally.
`DaMenuConfiguration` is size-prefixed and selects AppKit auto-enablement when
the menu is created. Its false compatibility default leaves explicit enabled
state authoritative; `da_menu_create` remains that exact legacy wrapper.
Current Dart bindings return unsupported for an auto-enabled menu on an older
native image rather than silently changing validation policy.

`da_view_set_context_menu` uses AppKit's ordinary view-local menu presentation
for secondary-click and control-click. It adds no synchronous callback into
Dart and no event protocol record: commands selected from that menu follow the
same asynchronous `DA_EVENT_MENU_ITEM_INVOKED` path as main-menu items. The
bridge retains only a weak set of attached views for release cleanup, while
`NSView.menu` provides the native presentation retain graph. The Dart wrapper
tracks the inverse relationship with weak `View` references so release failure
leaves both caches retryable and successful release detaches both sides.

`da_view_set_quick_look_request_enabled` registers one generation-checked View
for non-consuming local pressure observation. The bridge retains the View only
weakly, selects the deepest registered ancestor under the event, resets state
below stage 2 or on mouse-up, and posts exactly one v9 request for each first
transition into stage 2. Disabling or releasing the View removes its observer;
the shared AppKit monitor is removed when no registered Views remain.

`da_view_show_definition` copies a non-empty term of at most 4096 UTF-8 bytes,
rejects control and invisible display scalars, and validates a size-prefixed
`DaDefinitionPresentationConfiguration`. The configuration reuses the closed
system/monospaced/named font kinds and weights, bounds font size and named font
bytes as text views do, and requires finite View-local baseline coordinates.
Presentation uses AppKit's attributed-string definition API. Word selection,
terminal grid lookup, and whether a request is actionable remain application
policy; no native callback synchronously enters Dart.

`da_view_set_services_text_requestor` installs or replaces a size-prefixed
`DaServicesTextRequestorConfiguration` plus an optional copied selection. The
snapshot distinguishes an absent selection from a present empty string,
independently declares whether returned plain text is accepted, and gives reads
a positive application-selected limit no greater than the 64 MiB native hard
maximum. A snapshot with neither send nor return capability is invalid; a null
configuration and empty input remove the requestor.

The known `DaWindow` responder boundary selects the deepest registered View
that contains its first responder and satisfies both requested pasteboard
types. `writeSelectionToPasteboard:types:` writes only the cached
`NSPasteboardTypeString`. `readSelectionFromPasteboard:` reads only that type
under the cached limit and posts `DA_EVENT_VIEW_SERVICES_TEXT_RECEIVED` to the
generation-checked View. Both synchronous AppKit methods use native state only;
neither synchronously calls Dart. View release clears the copied selection and
invalidates a retained requestor before registry ownership is dropped.

`da_view_set_drop_destination` installs or replaces a size-prefixed immutable
copy-only policy for a View, or removes it when configuration is null. The
policy independently enables `NSPasteboardTypeString` and
`NSPasteboardTypeFileURL`, requires at least one, and bounds text bytes, file
URL count, bytes per URL, and aggregate URL bytes beneath fixed 64 MiB/256/
1 MiB/64 MiB hard maxima. Every `DaWindow` advertises only those two drag
types, then uses target-local geometry and window ancestry to select the
deepest compatible registered View. A source without `NSDragOperationCopy`
is rejected.

Enter/update cache only the generation-owned native destination and drag
sequence. Exit/end, policy replacement, View release, and window release clear
that state. Prepare revalidates location, type, sequence, and owner. Perform
copies one bounded payload and posts `DA_EVENT_VIEW_DROP_PERFORMED`; no drag
callback synchronously enters Dart. Plain text preserves exact UTF-8 bytes.
File URL items must all be absolute local `file:` URLs without credentials,
ports, queries, or fragments; native standardizes them and serializes one
little-endian `uint32` count followed by `uint32 byteLength + UTF-8 bytes` per
item. Dart checks every framing, byte, URL, and generation invariant again.

`da_application_set_folder_services_provider` installs or replaces a
size-prefixed application provider, or removes it when configuration is null.
The fixed Service message bases are `performPrimaryFolderService` and
`performSecondaryFolderService`; the following runtime declaration layer uses
those names and this bridge does not mutate the bundle. The bridge preserves
only a generic primary/secondary action identity; the application owns its
meaning. Each synchronous callback reads only file-URL pasteboard items under
caller bounds no larger than 256 items, 1 MiB per URL, and 64 MiB aggregate.
Absolute local URLs without credentials, ports, queries, or fragments are
standardized, classified with filesystem directory metadata, and mapped to the
selected directory itself or a selected file's parent. Indeterminate/missing
items fail closed. Canonical directory URLs are de-duplicated in first-seen
order and encoded with the same little-endian packet framing.

The provider posts one v12 `APPLICATION_FOLDER_SERVICE_REQUESTED` record only
after the whole snapshot succeeds; the callback never enters Dart inline.
Failure sets one bounded deterministic Service error and posts no partial
record. Disable, application termination, and bridge shutdown detach the
provider from `NSApplication`; a stale retained provider cannot post. Dart
revalidates framing, limits, absolute local canonical directory shape,
uniqueness, zero source identity, and the closed disposition.

Actionable items use a private native target that posts
`DA_EVENT_MENU_ITEM_INVOKED` with the item's generation-checked handle and
operation ID zero. `da_menu_item_set_checked` maps an exact `0` or `1` to the
ordinary AppKit off/on state without changing enablement or action routing.
Separators reject submenu, enabled-state, checked-state, and perform calls.
`da_menu_item_perform_action` uses the same target path as an AppKit click and
exists for deterministic product/integration exercise; an enabled actionable
item is required. A v1-v3 sink suppresses the v4 action record without changing
the synchronous call result.
