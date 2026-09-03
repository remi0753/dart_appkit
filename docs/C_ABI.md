# C ABI and Event Protocol

The public contract is `native/bridge/include/dart_appkit.h`. It contains plain C
types only and compiles as both C11 and C++20. Objective-C/Swift object layouts
never cross the boundary.

## Calls and errors

UI calls and synchronous registry release are main-thread-only.
`da_release_async`, ABI/status inspection, and documented debug/finalizer
entry points are safe on any thread. Status-returning calls never throw across
the ABI. `da_get_last_error` exposes thread-local detail; its message is
borrowed until the next bridge call on that thread.

Strings are an explicit UTF-8 pointer plus byte length. A null pointer is valid
only for a zero-length string. The bridge validates and copies the bytes before
returning and never retains Dart-owned memory.

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
- `da_window_set_content_view` borrows both handles, accepts either view kind,
  and consumes neither.
- Text-only calls require the specialized kind and reject a generic view.
- `da_window_close` performs a window action but does not release ownership.
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

## Event envelope

Version 1 remains the legacy fixed-position list:

```text
[protocolVersion, eventType, windowHandle, monotonicMicros, ...payload]
```

Versions 2 and 3 use the six-field common prefix:

```text
[protocolVersion, eventType, sourceHandle, sourceGeneration,
 monotonicNanoseconds, operationId, ...payload]
```

- `protocolVersion` is negotiated independently from `DA_ABI_VERSION`.
- `eventType` is a `DaEventType` integer.
- `sourceHandle` is the stable registry handle of the originating window.
- `sourceGeneration` is positive and matches the handle's high 32 bits.
- Timestamps are monotonic rather than wall-clock time. Version 1 uses
  microseconds; versions 2 and 3 use nanoseconds.
- Current unsolicited events use operation ID zero.
- Version 3 is current. Version-3-only event types are suppressed for a sink
  that negotiated version 1 or 2.

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
| mouse down/up/moved/dragged | `x: double, y: double, button: int, modifiers: int, clickCount: int` |
| key down/up | `keyCode: int, modifiers: int, isRepeat: bool, characters: string, charactersIgnoringModifiers: string` |

Coordinates use the content view's top-left origin. Modifier values use stable
`DaModifier` bits rather than exposing AppKit's enum representation.
Screen rectangles are global AppKit coordinates and may have negative origins.
An absent screen has a zero identifier and zero rectangles; a present screen
has a positive identifier and positive dimensions.

The event poster is injected internally by the Runner. No AppKit delegate enters
an isolate or invokes a Dart closure synchronously. A post that cannot be queued
is dropped; it never blocks AppKit waiting for Dart.
