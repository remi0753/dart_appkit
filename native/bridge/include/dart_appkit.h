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

/** ABI version returned by da_abi_version. */
#define DA_ABI_VERSION ((uint32_t)1)

/** Supported native event protocol range. Independent from DA_ABI_VERSION. */
#define DA_EVENT_PROTOCOL_VERSION_MIN ((uint32_t)1)
#define DA_EVENT_PROTOCOL_VERSION_CURRENT ((uint32_t)6)

/** Maximum UTF-8 text copied from the general pasteboard into a client. */
#define DA_PASTEBOARD_TEXT_MAX_UTF8_BYTES ((size_t)(64u * 1024u * 1024u))

/** Maximum UTF-8 bytes accepted by the external-URL opening boundary. */
#define DA_EXTERNAL_URL_MAX_UTF8_BYTES ((size_t)4096u)

/** Opaque, generation-checked native object identifier. Zero is invalid. */
typedef uint64_t DaHandle;

typedef struct DaRect {
  double x;
  double y;
  double width;
  double height;
} DaRect;

/** Stable bits for immutable window creation style. */
typedef enum DaWindowStyle {
  DA_WINDOW_STYLE_TITLED = 1u << 0,
  DA_WINDOW_STYLE_CLOSABLE = 1u << 1,
  DA_WINDOW_STYLE_MINIATURIZABLE = 1u << 2,
  DA_WINDOW_STYLE_RESIZABLE = 1u << 3
} DaWindowStyle;

/**
 * Size-prefixed window creation configuration.
 *
 * style_mask may contain only DaWindowStyle bits. A zero mask creates a
 * borderless window. Callers must initialize struct_size to the version size.
 */
typedef struct DaWindowConfiguration {
  uint64_t struct_size;
  uint64_t style_mask;
} DaWindowConfiguration;

#define DA_WINDOW_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaWindowConfiguration))
#define DA_WINDOW_STYLE_DEFAULT                                           \
  ((uint64_t)(DA_WINDOW_STYLE_TITLED | DA_WINDOW_STYLE_CLOSABLE |         \
              DA_WINDOW_STYLE_MINIATURIZABLE | DA_WINDOW_STYLE_RESIZABLE))

/** Hard logical-point bound for one native-tab accessory dimension. */
#define DA_WINDOW_TAB_ACCESSORY_MAX_EXTENT 256.0

/** Stable simple shapes for the built-in tab accessory mechanism. */
typedef enum DaWindowTabAccessoryShape {
  DA_WINDOW_TAB_ACCESSORY_SHAPE_RECTANGLE = 0,
  DA_WINDOW_TAB_ACCESSORY_SHAPE_ELLIPSE = 1
} DaWindowTabAccessoryShape;

/** Size-prefixed immutable native-tab accessory configuration. */
typedef struct DaWindowTabAccessoryConfiguration {
  uint64_t struct_size;
  int32_t shape;
  int32_t reserved;
  double width;
  double height;
  double red;
  double green;
  double blue;
  double alpha;
} DaWindowTabAccessoryConfiguration;

#define DA_WINDOW_TAB_ACCESSORY_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaWindowTabAccessoryConfiguration))

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

/**
 * Plain-text pasteboard snapshot.
 *
 * text is borrowed from thread-local bridge storage until the next pasteboard
 * read on the same thread. It is not NUL-termination-dependent. has_text is 1
 * for a present string (including empty), otherwise 0 with null/zero text.
 */
typedef struct DaPasteboardText {
  const char* text;
  size_t text_length;
  int32_t has_text;
  int64_t change_count;
} DaPasteboardText;

typedef enum DaStatus {
  DA_STATUS_OK = 0,
  DA_STATUS_INVALID_ARGUMENT = 1,
  DA_STATUS_INVALID_UTF8 = 2,
  DA_STATUS_INVALID_HANDLE = 3,
  DA_STATUS_WRONG_HANDLE_TYPE = 4,
  DA_STATUS_WRONG_THREAD = 5,
  DA_STATUS_EVENT_PORT_UNAVAILABLE = 6,
  DA_STATUS_INTERNAL_ERROR = 7,
  DA_STATUS_UNSUPPORTED_VERSION = 8,
  DA_STATUS_SHUTTING_DOWN = 9,
  DA_STATUS_LIMIT_EXCEEDED = 10
} DaStatus;

/** Event list slot 1; slot 0 is the negotiated event protocol version. */
typedef enum DaEventType {
  DA_EVENT_WINDOW_CLOSED = 1,
  DA_EVENT_WINDOW_RESIZED = 2,
  DA_EVENT_WINDOW_FOCUS_CHANGED = 3,
  DA_EVENT_WINDOW_VISIBILITY_CHANGED = 4,
  DA_EVENT_WINDOW_OCCLUSION_CHANGED = 5,
  DA_EVENT_WINDOW_BACKING_SCALE_CHANGED = 6,
  DA_EVENT_WINDOW_SCREEN_CHANGED = 7,
  DA_EVENT_WINDOW_CLOSE_REQUESTED = 8,
  DA_EVENT_WINDOW_FRAME_CHANGED = 9,
  DA_EVENT_MOUSE_DOWN = 10,
  DA_EVENT_MOUSE_UP = 11,
  DA_EVENT_MOUSE_MOVED = 12,
  DA_EVENT_MOUSE_DRAGGED = 13,
  DA_EVENT_SCROLL_WHEEL = 14,
  DA_EVENT_WINDOW_FULLSCREEN_CHANGED = 15,
  DA_EVENT_KEY_DOWN = 20,
  DA_EVENT_KEY_UP = 21,
  DA_EVENT_APPLICATION_ACTIVE_CHANGED = 30,
  DA_EVENT_APPLICATION_REOPEN_REQUESTED = 31,
  DA_EVENT_APPLICATION_TERMINATE_REQUESTED = 32,
  DA_EVENT_MENU_ITEM_INVOKED = 40
} DaEventType;

/** Stable scroll gesture phase values used by protocol version 5. */
typedef enum DaScrollPhase {
  DA_SCROLL_PHASE_NONE = 0,
  DA_SCROLL_PHASE_BEGAN = 1,
  DA_SCROLL_PHASE_STATIONARY = 2,
  DA_SCROLL_PHASE_CHANGED = 4,
  DA_SCROLL_PHASE_ENDED = 8,
  DA_SCROLL_PHASE_CANCELLED = 16,
  DA_SCROLL_PHASE_MAY_BEGIN = 32
} DaScrollPhase;

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

/** Per-window key routing after native menu key-equivalent arbitration. */
typedef enum DaKeyEventRouting {
  /** Post to Dart, then continue through AppKit's normal responder path. */
  DA_KEY_EVENT_ROUTING_DART_AND_APPKIT = 0,
  /** Post non-menu keys to Dart without normal AppKit responder dispatch. */
  DA_KEY_EVENT_ROUTING_DART_ONLY = 1,
  /** Deliver keys only through AppKit's first-responder/input-client path. */
  DA_KEY_EVENT_ROUTING_APPKIT_ONLY = 2
} DaKeyEventRouting;

/** Stable two-child split directions. */
typedef enum DaSplitAxis {
  /** Places the first child to the left of the second child. */
  DA_SPLIT_AXIS_HORIZONTAL = 0,
  /** Places the first child above the second child. */
  DA_SPLIT_AXIS_VERTICAL = 1
} DaSplitAxis;

/** Stable split zoom selection. */
typedef enum DaSplitZoomedChild {
  DA_SPLIT_ZOOM_NONE = -1,
  DA_SPLIT_ZOOM_FIRST = 0,
  DA_SPLIT_ZOOM_SECOND = 1
} DaSplitZoomedChild;

/** Safe on any thread. */
DA_EXPORT uint32_t da_abi_version(void);

/** Safe on any thread. Returns a static status name. */
DA_EXPORT const char* da_status_name(int32_t status);

/** Safe on any thread. Does not clear or replace the current error. */
DA_EXPORT void da_get_last_error(DaError* out_error);

/**
 * Main thread only. A positive Dart SendPort.nativePort is required.
 *
 * Legacy registration that always selects event protocol version 1. New
 * callers should use da_application_set_event_port_versioned.
 */
DA_EXPORT int32_t da_application_set_event_port(int64_t dart_port);

/**
 * Main thread only. Negotiates the highest mutually supported event version.
 *
 * min_version and max_version are inclusive and must describe a nonempty
 * positive range. out_selected_version is set to zero before validation and
 * receives the selected version only on success. Failed negotiation clears
 * any existing event-port registration.
 */
DA_EXPORT int32_t da_application_set_event_port_versioned(
    int64_t dart_port, uint32_t min_version, uint32_t max_version,
    uint32_t* out_selected_version);

/** Main thread only. Requests normal NSApplication termination. */
DA_EXPORT int32_t da_application_terminate(void);

/** Main thread only. Enables or disables asynchronous user-quit decisions. */
DA_EXPORT int32_t
da_application_set_termination_request_deferral(int32_t enabled);

/**
 * Main thread only. Completes the one pending user-quit request.
 *
 * operation_id must match the positive ID carried by the corresponding
 * DA_EVENT_APPLICATION_TERMINATE_REQUESTED event. allow must be 0 or 1.
 */
DA_EXPORT int32_t da_application_reply_to_termination_request(
    int64_t operation_id, int32_t allow);

/**
 * Main thread only. Opens an absolute http, https, or mailto URL.
 *
 * The copied UTF-8 input must be nonempty, no larger than
 * DA_EXTERNAL_URL_MAX_UTF8_BYTES, free of control/invisible/ambiguous
 * characters, and structurally valid. Web URLs require a host and reject
 * credentials. out_opened is initialized to zero and is one only when
 * NSWorkspace accepted the request.
 */
DA_EXPORT int32_t da_application_open_external_url(
    const char* url, size_t url_length, int32_t* out_opened);

/**
 * Main thread only. Reads one bounded general-pasteboard plain-text snapshot.
 * Returns DA_STATUS_LIMIT_EXCEEDED without copying text when its UTF-8 form is
 * larger than DA_PASTEBOARD_TEXT_MAX_UTF8_BYTES.
 */
DA_EXPORT int32_t da_pasteboard_read_text(DaPasteboardText* out_snapshot);

/** Main thread only. Replaces general-pasteboard contents with copied UTF-8. */
DA_EXPORT int32_t da_pasteboard_write_text(const char* text, size_t text_length,
                                           int64_t* out_change_count);

/** Main thread only. Clears the general pasteboard. */
DA_EXPORT int32_t da_pasteboard_clear(int64_t* out_change_count);

/** Main thread only. Reads the general pasteboard change count. */
DA_EXPORT int32_t da_pasteboard_get_change_count(int64_t* out_change_count);

/** Main thread only. Creates a menu and copies its UTF-8 title. */
DA_EXPORT int32_t da_menu_create(const char* title, size_t title_length,
                                 DaHandle* out_menu);

/**
 * Main thread only. Creates an actionable menu item and copies both strings.
 *
 * modifiers must contain only DaModifier bits. key_equivalent may be empty.
 */
DA_EXPORT int32_t da_menu_item_create(const char* title, size_t title_length,
                                      const char* key_equivalent,
                                      size_t key_equivalent_length,
                                      uint64_t modifiers, DaHandle* out_item);

/** Main thread only. Creates a separator menu item. */
DA_EXPORT int32_t da_menu_item_create_separator(DaHandle* out_item);

/** Main thread only. Appends an item and consumes neither handle. */
DA_EXPORT int32_t da_menu_add_item(DaHandle menu, DaHandle item);

/** Main thread only. Attaches a submenu, or clears it when submenu is zero. */
DA_EXPORT int32_t da_menu_item_set_submenu(DaHandle item, DaHandle submenu);

/** Main thread only. enabled must be 0 or 1. */
DA_EXPORT int32_t da_menu_item_set_enabled(DaHandle item, int32_t enabled);

/** Main thread only. Attaches the main menu, or clears it when menu is zero. */
DA_EXPORT int32_t da_application_set_main_menu(DaHandle menu);

/** Main thread only. Performs one non-separator item's registered action. */
DA_EXPORT int32_t da_menu_item_perform_action(DaHandle item);

/** Main thread only. UTF-8 bytes are copied before return. */
DA_EXPORT int32_t da_window_create(DaRect frame, const char* title,
                                   size_t title_length, DaHandle* out_window);

/**
 * Main thread only. Creates a window from copied UTF-8 and immutable style.
 *
 * configuration must provide at least DA_WINDOW_CONFIGURATION_VERSION_1_SIZE
 * bytes and may contain only the currently declared DaWindowStyle bits.
 */
DA_EXPORT int32_t da_window_create_configured(
    DaRect frame, const char* title, size_t title_length,
    const DaWindowConfiguration* configuration, DaHandle* out_window);

/** Main thread only. Replaces the finite positive outer window frame. */
DA_EXPORT int32_t da_window_set_frame(DaHandle window, DaRect frame);

/**
 * Main thread only. Requests native AppKit fullscreen entry or exit.
 *
 * enabled must be 0 or 1. Completion is asynchronous and is reported by
 * DA_EVENT_WINDOW_FULLSCREEN_CHANGED under event protocol version 6.
 */
DA_EXPORT int32_t da_window_set_fullscreen(DaHandle window, int32_t enabled);

/** Main thread only. */
DA_EXPORT int32_t da_window_show(DaHandle window);

/** Main thread only. Closing does not release the handle. */
DA_EXPORT int32_t da_window_close(DaHandle window);

/** Main thread only. Performs the user-facing close action. */
DA_EXPORT int32_t da_window_request_close(DaHandle window);

/** Main thread only. Enables or disables asynchronous user-close decisions. */
DA_EXPORT int32_t da_window_set_close_request_deferral(DaHandle window,
                                                       int32_t enabled);

/**
 * Main thread only. Configures per-window key-event routing.
 *
 * routing must be a DaKeyEventRouting value. The default is
 * DA_KEY_EVENT_ROUTING_DART_AND_APPKIT. In DART_ONLY mode, main-menu key
 * equivalents retain priority; remaining key events are posted to Dart and
 * are not sent through the ordinary AppKit responder chain. In APPKIT_ONLY
 * mode, key events are not posted to the window's Dart stream and enter only
 * the AppKit responder chain.
 */
DA_EXPORT int32_t da_window_set_key_event_routing(DaHandle window,
                                                  int32_t routing);

/**
 * Main thread only. Completes the one pending user-close request.
 *
 * operation_id must match the positive ID carried by the corresponding
 * DA_EVENT_WINDOW_CLOSE_REQUESTED event. allow must be 0 or 1.
 */
DA_EXPORT int32_t da_window_reply_to_close_request(DaHandle window,
                                                   int64_t operation_id,
                                                   int32_t allow);

/** Main thread only. UTF-8 bytes are copied before return. */
DA_EXPORT int32_t da_window_set_title(DaHandle window, const char* title,
                                      size_t title_length);

/**
 * Main thread only. Sets an absolute local path as the window's represented
 * file, enabling the standard proxy icon/path menu. An empty path clears it.
 * Non-empty UTF-8 bytes are copied before return and capped at 4096 bytes.
 */
DA_EXPORT int32_t da_window_set_represented_file_path(DaHandle window,
                                                      const char* path,
                                                      size_t path_length);

/**
 * Main thread only. Sets or clears the standard native-tab color marker.
 * has_color must be zero or one. Present components must be finite in [0, 1].
 * The accessory is retained by AppKit and creates no registry handle.
 */
DA_EXPORT int32_t da_window_set_tab_color(DaHandle window,
                                          int32_t has_color, double red,
                                          double green, double blue,
                                          double alpha);

/**
 * Main thread only. Sets or clears a parameterized native-tab accessory.
 *
 * has_accessory must be zero or one. When present, configuration must provide
 * the version-1 prefix, zero reserved fields, a declared shape, dimensions in
 * (0, DA_WINDOW_TAB_ACCESSORY_MAX_EXTENT], and finite sRGB components in
 * [0, 1]. Clearing permits a null configuration.
 */
DA_EXPORT int32_t da_window_set_tab_accessory(
    DaHandle window, int32_t has_accessory,
    const DaWindowTabAccessoryConfiguration* configuration);

/** Main thread only. Appends tabbed_window to window's native tab group. */
DA_EXPORT int32_t da_window_add_tabbed_window(DaHandle window,
                                              DaHandle tabbed_window);

/** Main thread only. Removes window from its native tab group if necessary. */
DA_EXPORT int32_t da_window_remove_from_tab_group(DaHandle window);

/** Main thread only. Selects window in its native tab group and brings it forward. */
DA_EXPORT int32_t da_window_select_tab(DaHandle window);

/**
 * Main thread only. Makes an attached generic or specialized view the
 * window's first responder. Consumes neither handle.
 */
DA_EXPORT int32_t da_window_make_first_responder(DaHandle window,
                                                 DaHandle view);

/** Main thread only. Creates a generic AppKit view. */
DA_EXPORT int32_t da_view_create(DaHandle* out_view);

/** Main thread only. Creates a native two-child split view. */
DA_EXPORT int32_t da_split_view_create(int32_t axis, DaHandle* out_view);

/**
 * Main thread only. Replaces a split view's two ordered children. The children
 * must be distinct generic or specialized views. Consumes no handle.
 */
DA_EXPORT int32_t da_split_view_set_children(DaHandle split_view,
                                             DaHandle first_view,
                                             DaHandle second_view);

/**
 * Main thread only. Sets the first-child fraction and non-negative minimum
 * extents along the split axis. fraction must be finite and in (0, 1).
 */
DA_EXPORT int32_t da_split_view_set_position(
    DaHandle split_view, double fraction, double first_minimum_extent,
    double second_minimum_extent);

/** Main thread only. Sets the first-child fraction to one half. */
DA_EXPORT int32_t da_split_view_equalize(DaHandle split_view);

/** Main thread only. Shows both children or zooms exactly one child. */
DA_EXPORT int32_t da_split_view_set_zoomed_child(DaHandle split_view,
                                                 int32_t child);

/**
 * Main thread only. Creates a generic view from a registered native provider.
 *
 * provider_identifier is copied UTF-8 and must identify an NSView subclass
 * registered through the Objective-C++ custom-view extension surface.
 */
DA_EXPORT int32_t da_view_create_custom(const char* provider_identifier,
                                        size_t provider_identifier_length,
                                        DaHandle* out_view);

/**
 * Main thread only. Invokes the opaque operation registered by the native
 * provider that created this custom view. The payload is borrowed only for the
 * synchronous call. Generic and specialized non-provider views are rejected.
 */
DA_EXPORT int32_t da_view_perform_custom_operation(
    DaHandle view, const uint8_t* payload, size_t payload_length);

/** Main thread only. */
DA_EXPORT int32_t da_text_view_create(DaHandle* out_view);

/** Main thread only. UTF-8 bytes are copied before return. */
DA_EXPORT int32_t da_text_view_set_text(DaHandle view, const char* text,
                                        size_t text_length);

/**
 * Main thread only. Accepts a generic or specialized view and consumes
 * neither handle.
 */
DA_EXPORT int32_t da_window_set_content_view(DaHandle window, DaHandle view);

/** Main thread only. Invalidates this handle exactly once. */
DA_EXPORT int32_t da_release(DaHandle handle);

/**
 * Safe on any thread. Invalidates a live handle before returning.
 *
 * Native teardown is enqueued on the handle's owning domain. A successful
 * return means that this call exclusively claimed the handle; it does not mean
 * that native destruction has completed.
 */
DA_EXPORT int32_t da_release_async(DaHandle handle);

/**
 * NativeFinalizer entry point. Safe on any thread.
 *
 * token is a DaHandle encoded as a pointer-sized integer. The finalizer uses
 * the same exclusive asynchronous-release path and ignores its status.
 */
DA_EXPORT void da_release_finalizer(void* token);

/** Safe on any thread. Writes 1 on the process main thread, otherwise 0. */
DA_EXPORT int32_t da_debug_is_main_thread(int32_t* out_is_main_thread);

/** Main thread only. Returns the number of live registry handles. */
DA_EXPORT int32_t da_debug_live_object_count(uint64_t* out_count);

/**
 * Main thread only. Test hook that enters the ordinary deferred application
 * termination decision without terminating the host process.
 */
DA_EXPORT int32_t da_debug_request_application_termination(void);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // DART_APPKIT_BRIDGE_INCLUDE_DART_APPKIT_H_
