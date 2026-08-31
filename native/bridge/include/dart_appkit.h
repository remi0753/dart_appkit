#ifndef DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_H_
#define DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_H_

#include <stddef.h>
#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

#if defined(__GNUC__)
#define DA_EXPORT __attribute__((visibility("default")))
#else
#define DA_EXPORT
#endif

/** ABI version returned by da_abi_version and sent with every event. */
#define DA_ABI_VERSION ((uint32_t)1)

/** Opaque, generation-checked native object identifier. Zero is invalid. */
typedef uint64_t DaHandle;

typedef struct DaRect {
  double x;
  double y;
  double width;
  double height;
} DaRect;

/**
 * Error detail borrowed from thread-local storage.
 *
 * message is not NUL-termination-dependent and remains valid until the next
 * bridge call on the same thread. The caller must not retain or free it.
 */
typedef struct DaError {
  int32_t code;
  const char* message;
  size_t message_length;
} DaError;

typedef enum DaStatus {
  DA_STATUS_OK = 0,
  DA_STATUS_INVALID_ARGUMENT = 1,
  DA_STATUS_INVALID_UTF8 = 2,
  DA_STATUS_INVALID_HANDLE = 3,
  DA_STATUS_WRONG_HANDLE_TYPE = 4,
  DA_STATUS_WRONG_THREAD = 5,
  DA_STATUS_EVENT_PORT_UNAVAILABLE = 6,
  DA_STATUS_INTERNAL_ERROR = 7
} DaStatus;

/** Event list slot 1; slot 0 is always DA_ABI_VERSION. */
typedef enum DaEventType {
  DA_EVENT_WINDOW_CLOSED = 1,
  DA_EVENT_WINDOW_RESIZED = 2,
  DA_EVENT_MOUSE_DOWN = 10,
  DA_EVENT_MOUSE_UP = 11,
  DA_EVENT_MOUSE_MOVED = 12,
  DA_EVENT_MOUSE_DRAGGED = 13,
  DA_EVENT_KEY_DOWN = 20,
  DA_EVENT_KEY_UP = 21
} DaEventType;

/** Stable modifier bits used by mouse and keyboard events. */
typedef enum DaModifier {
  DA_MODIFIER_CAPS_LOCK = 1 << 0,
  DA_MODIFIER_SHIFT = 1 << 1,
  DA_MODIFIER_CONTROL = 1 << 2,
  DA_MODIFIER_OPTION = 1 << 3,
  DA_MODIFIER_COMMAND = 1 << 4,
  DA_MODIFIER_NUMERIC_PAD = 1 << 5,
  DA_MODIFIER_FUNCTION = 1 << 6
} DaModifier;

/** Safe on any thread. */
DA_EXPORT uint32_t da_abi_version(void);

/** Safe on any thread. Returns a static status name. */
DA_EXPORT const char* da_status_name(int32_t status);

/** Safe on any thread. Does not clear or replace the current error. */
DA_EXPORT void da_get_last_error(DaError* out_error);

/** Main thread only. A positive Dart SendPort.nativePort is required. */
DA_EXPORT int32_t da_application_set_event_port(int64_t dart_port);

/** Main thread only. Requests normal NSApplication termination. */
DA_EXPORT int32_t da_application_terminate(void);

/** Main thread only. UTF-8 bytes are copied before return. */
DA_EXPORT int32_t da_window_create(DaRect frame, const char* title,
                                   size_t title_length, DaHandle* out_window);

/** Main thread only. */
DA_EXPORT int32_t da_window_show(DaHandle window);

/** Main thread only. Closing does not release the handle. */
DA_EXPORT int32_t da_window_close(DaHandle window);

/** Main thread only. UTF-8 bytes are copied before return. */
DA_EXPORT int32_t da_window_set_title(DaHandle window, const char* title,
                                      size_t title_length);

/** Main thread only. */
DA_EXPORT int32_t da_text_view_create(DaHandle* out_view);

/** Main thread only. UTF-8 bytes are copied before return. */
DA_EXPORT int32_t da_text_view_set_text(DaHandle view, const char* text,
                                        size_t text_length);

/** Main thread only. Does not consume either handle. */
DA_EXPORT int32_t da_window_set_content_view(DaHandle window, DaHandle view);

/** Main thread only. Invalidates this handle exactly once. */
DA_EXPORT int32_t da_release(DaHandle handle);

/**
 * NativeFinalizer entry point. Safe on any thread.
 *
 * token is a DaHandle encoded as a pointer-sized integer. Release is enqueued
 * on the main queue and ignored if the process is already shutting down.
 */
DA_EXPORT void da_release_finalizer(void* token);

/** Safe on any thread. Writes 1 on the process main thread, otherwise 0. */
DA_EXPORT int32_t da_debug_is_main_thread(int32_t* out_is_main_thread);

/** Main thread only. Returns the number of live registry handles. */
DA_EXPORT int32_t da_debug_live_object_count(uint64_t* out_count);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_H_
