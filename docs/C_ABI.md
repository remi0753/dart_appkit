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
FD readiness and `waitpid` remain on the session reactor. PTY ABI version 2 adds
the idempotent `force_close` operation without changing the size-prefixed V1
configuration or statistics layouts. It remains valid during graceful close
and moves SIGKILL process-group delivery onto the reactor immediately.

An OUTPUT callback carries at most 64 KiB and borrows its byte pointer until the
exact sequence/length pair is acknowledged in order. The high watermark
disables the kqueue read filter and the low watermark re-enables it. Writes are
copied only when the configured capacity admits the entire call; saturation
returns `DPTY_STATUS_BACKPRESSURED` without waiting. EXIT reports either the
child status or `128 + signal`, after the owning reactor has reaped the PID.
Destroy requires a finished session with no unacknowledged output and retires
that handle generation.

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

## Event envelope

Version 1 remains the legacy fixed-position list:

```text
[protocolVersion, eventType, windowHandle, monotonicMicros, ...payload]
```

Versions 2, 3, and 4 use the six-field common prefix:

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
  microseconds; versions 2 through 4 use nanoseconds.
- Notifications use operation ID zero. Deferred close/termination requests use
  a positive ID that must be echoed exactly once in the matching reply call.
- Version 4 is current. Version-specific event types are suppressed for an
  older negotiated sink.

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
| mouse down/up/moved/dragged | `x: double, y: double, button: int, modifiers: int, clickCount: int` |
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
