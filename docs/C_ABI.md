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
FD readiness and `waitpid` remain on the session reactor. PTY ABI version 4
retains the idempotent `force_close` operation and size-prefixed V1 diagnostic
configuration introduced in v3. `dpty_session_write_tracked` returns an
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

## Handle ownership

- Successful create calls return one registry-owned handle.
- Every occupied registry slot records its object kind, positive generation,
  and owning thread domain. Current objects belong to the AppKit main domain.
- `da_view_create` returns a generic view handle. `da_text_view_create` returns
  a specialized handle that is accepted by generic-view lookups.
- `da_view_create_custom` copies a non-empty provider identifier, asks the
  native provider registry to construct its `NSView` subclass, and returns the
  instance as a generic view handle.
- `da_window_set_content_view` borrows both handles, accepts either view kind,
  and consumes neither.
- Menu and menu-item create calls return independent handles. Adding an item,
  attaching a submenu, and setting the application main menu borrow every
  handle and consume none; AppKit's retain graph is not a registry lease.
- Releasing a menu item clears its target/action/handle before dropping the
  registry reference. Releasing the currently attached main menu detaches it
  from `NSApplication`.
- Text-only calls require the specialized kind and reject a generic view.
- `da_window_close` performs an unconditional programmatic window action but
  does not release ownership. `da_window_request_close` follows the user-facing
  delegate path.
- `da_window_set_represented_file_path` copies at most 4096 UTF-8 bytes into an
  absolute local file URL, while an empty input clears it.
  `da_window_set_tab_color` creates or clears an `NSWindowTab` accessory owned
  by AppKit. Neither operation inserts a registry object or transfers a handle.
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
accessibility snapshots. ABI version 10 bounds the packet, UTF-8 and UTF-16
text lengths, physical lines, and per-line terminal-column boundaries. The
provider validates canonical offsets, exact newline topology, UTF-8/UTF-16
agreement, surrogate-safe ranges, terminal-boundary selection and cursor
positions, and a strictly increasing generation before atomically replacing
its native copy. Malformed or stale packets leave the previous accessible
state intact. AppKit selectors and notifications are implemented by the
provider-owned `NSView`; the bridge never interprets terminal text.

## Event envelope

Version 1 remains the legacy fixed-position list:

```text
[protocolVersion, eventType, windowHandle, monotonicMicros, ...payload]
```

Versions 2 through 6 use the six-field common prefix:

```text
[protocolVersion, eventType, sourceHandle, sourceGeneration,
 monotonicNanoseconds, operationId, ...payload]
```

- `protocolVersion` is negotiated independently from `DA_ABI_VERSION`.
- `eventType` is a `DaEventType` integer.
- `sourceHandle` is the stable registry handle of the originating window or
  menu item. Application-scoped v4 events use zero.
- `sourceGeneration` is positive and matches the handle's high 32 bits for
  registry objects. Application-scoped v4 events use zero.
- Timestamps are monotonic rather than wall-clock time. Version 1 uses
  microseconds; versions 2 through 6 use nanoseconds.
- Notifications use operation ID zero. Deferred close/termination requests use
  a positive ID that must be echoed exactly once in the matching reply call.
- Version 6 is current. Version 3 adds window state, version 4 adds lifecycle
  decisions and menu actions, version 5 adds precision scroll, and version 6
  adds outer-frame and native-fullscreen state. Version-specific types are
  suppressed for an older negotiated sink.

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
port also posts the current application-active snapshot.

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

`da_application_open_external_url` accepts at most 4096 UTF-8 bytes and opens
only structurally valid absolute `http`, `https`, or `mailto` targets. Web URLs
require a nonempty host and reject embedded credentials. Raw controls,
whitespace, backslashes, bidi/invisible formatting characters, malformed
escapes, and percent-encoded controls, backslashes, or bidi/invisible
characters are rejected before `NSURL` construction. The call is
main-thread-only, initializes `out_opened` to zero, and invokes
`NSWorkspace.openURL` directly without a shell.

The Dart API requires an `AllowedExternalUrl` produced by the same
deny-by-default policy, so ordinary callers cannot pass an unchecked string to
`AppKitApplication.openExternalUrl`. Native validation is deliberately
repeated at the trust boundary. The symbol is additive: a legacy ABI-v1 image
without it reports `DA_STATUS_UNSUPPORTED_VERSION` through current Dart
bindings. Automated native tests replace only the final workspace opener after
validation and therefore never launch an external application.

## Menu policy

Menu and item titles plus key equivalents use the same copied UTF-8 convention
as other bridge strings. Shortcut masks accept only the seven stable
`DaModifier` bits and translate them to AppKit flags internally. Menus disable
AppKit auto-enablement so the explicit enabled state remains authoritative.

Actionable items use a private native target that posts
`DA_EVENT_MENU_ITEM_INVOKED` with the item's generation-checked handle and
operation ID zero. Separators reject submenu, enabled-state, and perform calls.
`da_menu_item_perform_action` uses the same target path as an AppKit click and
exists for deterministic product/integration exercise; an enabled actionable
item is required. A v1-v3 sink suppresses the v4 action record without changing
the synchronous call result.
