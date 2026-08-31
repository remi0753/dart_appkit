# C ABI and Event Protocol

The public contract is `native/bridge/include/dart_appkit.h`. It contains plain C
types only and compiles as both C11 and C++20. Objective-C/Swift object layouts
never cross the boundary.

## Calls and errors

All UI and registry calls are main-thread-only. They return a `DaStatus` integer
and never throw across the ABI. `da_get_last_error` exposes thread-local detail;
its message is borrowed until the next bridge call on that thread.

Strings are an explicit UTF-8 pointer plus byte length. A null pointer is valid
only for a zero-length string. The bridge validates and copies the bytes before
returning and never retains Dart-owned memory.

Output pointers are mandatory. On failure, the bridge leaves them in a safe zero
state. Handles are opaque 64-bit values; zero is always invalid. Generated
handles stay within positive signed 64-bit range so the same value is preserved
in both FFI `Uint64` calls and the event protocol's signed integer slot.

## Handle ownership

- Successful create calls return one registry-owned handle.
- `da_window_set_content_view` borrows both handles and consumes neither.
- `da_window_close` performs a window action but does not release ownership.
- `da_release` invalidates exactly one live handle. A second release reports
  `DA_STATUS_INVALID_HANDLE`.
- `da_release_finalizer` accepts a handle encoded as a pointer token and queues a
  best-effort main-thread release. It is the only lifecycle entry point intended
  for an arbitrary finalizer thread.

## Event envelope

Every event sent to the registered Dart native port is a fixed-position list:

```text
[protocolVersion, eventType, windowHandle, monotonicMicros, ...payload]
```

- `protocolVersion` is `DA_ABI_VERSION` (`1`).
- `eventType` is a `DaEventType` integer.
- `windowHandle` is the stable registry handle of the originating window.
- `monotonicMicros` is a monotonic timestamp, not wall-clock time.

Payloads:

| Event | Payload after slot 3 |
|---|---|
| `WINDOW_CLOSED` | none |
| `WINDOW_RESIZED` | `width: double, height: double` |
| mouse down/up/moved/dragged | `x: double, y: double, button: int, modifiers: int, clickCount: int` |
| key down/up | `keyCode: int, modifiers: int, isRepeat: bool, characters: string, charactersIgnoringModifiers: string` |

Coordinates use the content view's top-left origin. Modifier values use stable
`DaModifier` bits rather than exposing AppKit's enum representation.

The event poster is injected internally by the Runner. No AppKit delegate enters
an isolate or invokes a Dart closure synchronously. A post that cannot be queued
is dropped; it never blocks AppKit waiting for Dart.
