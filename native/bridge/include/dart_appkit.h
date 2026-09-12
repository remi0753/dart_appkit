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
#define DA_EVENT_PROTOCOL_VERSION_CURRENT ((uint32_t)13)

/** Maximum UTF-8 text copied from the general pasteboard into a client. */
#define DA_PASTEBOARD_TEXT_MAX_UTF8_BYTES ((size_t)(64u * 1024u * 1024u))

/** Maximum UTF-8 bytes accepted by the external-URL opening boundary. */
#define DA_EXTERNAL_URL_MAX_UTF8_BYTES ((size_t)4096u)

/** Maximum UTF-8 bytes accepted for one application policy scheme. */
#define DA_EXTERNAL_URL_SCHEME_MAX_UTF8_BYTES ((size_t)64u)

/** Hard copied-input bounds for application user notifications. */
#define DA_USER_NOTIFICATION_IDENTIFIER_MAX_UTF8_BYTES ((size_t)128u)
#define DA_USER_NOTIFICATION_TEXT_MAX_UTF8_BYTES ((size_t)4096u)

/** Hard copied-input bound for the short application Dock badge label. */
#define DA_DOCK_BADGE_LABEL_MAX_UTF8_BYTES ((size_t)32u)

/** Stable application-selected conditions for one external URL scheme. */
typedef enum DaExternalUrlPolicyFlag {
  DA_EXTERNAL_URL_POLICY_REQUIRE_AUTHORITY = 1u << 0,
  DA_EXTERNAL_URL_POLICY_FORBID_AUTHORITY = 1u << 1,
  DA_EXTERNAL_URL_POLICY_REQUIRE_HOST = 1u << 2,
  DA_EXTERNAL_URL_POLICY_FORBID_CREDENTIALS = 1u << 3,
  DA_EXTERNAL_URL_POLICY_REQUIRE_PATH = 1u << 4
} DaExternalUrlPolicyFlag;

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

/** Current-screen selectors resolved afresh by the application. */
typedef enum DaScreenSelection {
  /** Screen containing the keyboard-focus window; falls back to the first. */
  DA_SCREEN_SELECTION_MAIN = 0,
  /** Screen containing the global mouse location; falls back to main. */
  DA_SCREEN_SELECTION_MOUSE = 1,
  /** First AppKit screen, which owns the menu bar; falls back to main. */
  DA_SCREEN_SELECTION_MENU_BAR = 2
} DaScreenSelection;

/** Size-prefixed immutable current screen geometry and backing scale. */
typedef struct DaScreenSnapshot {
  uint64_t struct_size;
  uint64_t display_id;
  DaRect frame;
  DaRect visible_frame;
  double backing_scale_factor;
} DaScreenSnapshot;

#define DA_SCREEN_SNAPSHOT_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaScreenSnapshot))

/** Stable native window levels for reusable presentation policy. */
typedef enum DaWindowLevel {
  DA_WINDOW_LEVEL_NORMAL = 0,
  DA_WINDOW_LEVEL_FLOATING = 1,
  DA_WINDOW_LEVEL_STATUS = 2
} DaWindowLevel;

/** Stable bits projected to NSWindowCollectionBehavior. */
typedef enum DaWindowCollectionBehavior {
  DA_WINDOW_COLLECTION_BEHAVIOR_CAN_JOIN_ALL_SPACES = 1u << 0,
  DA_WINDOW_COLLECTION_BEHAVIOR_FULL_SCREEN_AUXILIARY = 1u << 1,
  DA_WINDOW_COLLECTION_BEHAVIOR_STATIONARY = 1u << 2,
  DA_WINDOW_COLLECTION_BEHAVIOR_TRANSIENT = 1u << 3
} DaWindowCollectionBehavior;

/** Size-prefixed generic window level and Spaces presentation policy. */
typedef struct DaWindowPresentationConfiguration {
  uint64_t struct_size;
  int32_t level;
  int32_t reserved;
  uint64_t collection_behavior_mask;
} DaWindowPresentationConfiguration;

#define DA_WINDOW_PRESENTATION_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaWindowPresentationConfiguration))
#define DA_WINDOW_PRESENTATION_ANIMATION_MAX_SECONDS 5.0

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

/** Stable autoresizing bits for package-created base and simple text views. */
typedef enum DaViewAutoresizing {
  DA_VIEW_AUTORESIZE_WIDTH = 1u << 0,
  DA_VIEW_AUTORESIZE_HEIGHT = 1u << 1
} DaViewAutoresizing;

/** Size-prefixed immutable base-view creation configuration. */
typedef struct DaViewConfiguration {
  uint64_t struct_size;
  uint64_t autoresizing_mask;
  int32_t accepts_first_responder;
  int32_t reserved;
} DaViewConfiguration;

#define DA_VIEW_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaViewConfiguration))
#define DA_VIEW_AUTORESIZE_DEFAULT \
  ((uint64_t)(DA_VIEW_AUTORESIZE_WIDTH | DA_VIEW_AUTORESIZE_HEIGHT))

#define DA_TEXT_VIEW_FONT_MAX_SIZE 512.0
#define DA_TEXT_VIEW_FONT_FAMILY_MAX_UTF8_BYTES ((size_t)256u)
#define DA_TEXT_VIEW_PADDING_MAX_EXTENT 4096.0
#define DA_DEFINITION_TEXT_MAX_UTF8_BYTES ((size_t)4096u)
#define DA_SERVICES_TEXT_MAX_UTF8_BYTES DA_PASTEBOARD_TEXT_MAX_UTF8_BYTES
#define DA_DROP_TEXT_MAX_UTF8_BYTES DA_PASTEBOARD_TEXT_MAX_UTF8_BYTES
#define DA_DROP_FILE_URL_MAX_COUNT ((uint64_t)256u)
#define DA_DROP_FILE_URL_MAX_UTF8_BYTES ((uint64_t)(1024u * 1024u))
#define DA_DROP_FILE_URL_TOTAL_MAX_UTF8_BYTES \
  ((uint64_t)DA_PASTEBOARD_TEXT_MAX_UTF8_BYTES)
#define DA_DROP_FILE_URL_PACKET_MAX_BYTES                              \
  ((size_t)(DA_DROP_FILE_URL_TOTAL_MAX_UTF8_BYTES + sizeof(uint32_t) + \
            DA_DROP_FILE_URL_MAX_COUNT * sizeof(uint32_t)))
#define DA_FOLDER_SERVICE_FILE_URL_MAX_COUNT DA_DROP_FILE_URL_MAX_COUNT
#define DA_FOLDER_SERVICE_FILE_URL_MAX_UTF8_BYTES \
  DA_DROP_FILE_URL_MAX_UTF8_BYTES
#define DA_FOLDER_SERVICE_FILE_URL_TOTAL_MAX_UTF8_BYTES \
  DA_DROP_FILE_URL_TOTAL_MAX_UTF8_BYTES
#define DA_FOLDER_SERVICE_FILE_URL_PACKET_MAX_BYTES \
  DA_DROP_FILE_URL_PACKET_MAX_BYTES
#define DA_FOLDER_SERVICE_PRIMARY_MESSAGE "performPrimaryFolderService"
#define DA_FOLDER_SERVICE_SECONDARY_MESSAGE "performSecondaryFolderService"

typedef enum DaTextViewFontKind {
  DA_TEXT_VIEW_FONT_SYSTEM = 0,
  DA_TEXT_VIEW_FONT_MONOSPACED_SYSTEM = 1,
  DA_TEXT_VIEW_FONT_NAMED = 2
} DaTextViewFontKind;

typedef enum DaTextViewFontWeight {
  DA_TEXT_VIEW_FONT_WEIGHT_ULTRA_LIGHT = 0,
  DA_TEXT_VIEW_FONT_WEIGHT_THIN = 1,
  DA_TEXT_VIEW_FONT_WEIGHT_LIGHT = 2,
  DA_TEXT_VIEW_FONT_WEIGHT_REGULAR = 3,
  DA_TEXT_VIEW_FONT_WEIGHT_MEDIUM = 4,
  DA_TEXT_VIEW_FONT_WEIGHT_SEMIBOLD = 5,
  DA_TEXT_VIEW_FONT_WEIGHT_BOLD = 6,
  DA_TEXT_VIEW_FONT_WEIGHT_HEAVY = 7,
  DA_TEXT_VIEW_FONT_WEIGHT_BLACK = 8
} DaTextViewFontWeight;

/** Size-prefixed font and baseline geometry for definition presentation. */
typedef struct DaDefinitionPresentationConfiguration {
  uint64_t struct_size;
  int32_t font_kind;
  int32_t font_weight;
  int32_t reserved_0;
  int32_t reserved_1;
  double font_size;
  double baseline_x;
  double baseline_y;
} DaDefinitionPresentationConfiguration;

#define DA_DEFINITION_PRESENTATION_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaDefinitionPresentationConfiguration))

/** Size-prefixed cached plain-text Services requestor state. */
typedef struct DaServicesTextRequestorConfiguration {
  uint64_t struct_size;
  uint64_t maximum_returned_text_utf8_bytes;
  int32_t has_selection;
  int32_t accepts_returned_text;
  int32_t reserved_0;
  int32_t reserved_1;
} DaServicesTextRequestorConfiguration;

#define DA_SERVICES_TEXT_REQUESTOR_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaServicesTextRequestorConfiguration))

/** Size-prefixed immutable text/file-URL drop-destination policy. */
typedef struct DaDropDestinationConfiguration {
  uint64_t struct_size;
  uint64_t maximum_text_utf8_bytes;
  uint64_t maximum_file_url_count;
  uint64_t maximum_file_url_utf8_bytes;
  uint64_t maximum_total_file_url_utf8_bytes;
  int32_t accepts_plain_text;
  int32_t accepts_file_urls;
  int32_t reserved_0;
  int32_t reserved_1;
} DaDropDestinationConfiguration;

#define DA_DROP_DESTINATION_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaDropDestinationConfiguration))

typedef enum DaDropContentKind {
  DA_DROP_CONTENT_PLAIN_TEXT = 0,
  DA_DROP_CONTENT_FILE_URLS = 1
} DaDropContentKind;

/** Size-prefixed immutable application folder Services policy. */
typedef struct DaFolderServicesProviderConfiguration {
  uint64_t struct_size;
  uint64_t maximum_file_url_count;
  uint64_t maximum_file_url_utf8_bytes;
  uint64_t maximum_total_file_url_utf8_bytes;
  int32_t reserved_0;
  int32_t reserved_1;
} DaFolderServicesProviderConfiguration;

#define DA_FOLDER_SERVICES_PROVIDER_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaFolderServicesProviderConfiguration))

typedef enum DaFolderServiceAction {
  DA_FOLDER_SERVICE_ACTION_PRIMARY = 0,
  DA_FOLDER_SERVICE_ACTION_SECONDARY = 1
} DaFolderServiceAction;

typedef enum DaTextViewColorKind {
  DA_TEXT_VIEW_COLOR_LABEL = 0,
  DA_TEXT_VIEW_COLOR_WINDOW_BACKGROUND = 1,
  DA_TEXT_VIEW_COLOR_SRGB = 2
} DaTextViewColorKind;

typedef struct DaTextViewColorConfiguration {
  int32_t kind;
  int32_t reserved;
  double red;
  double green;
  double blue;
  double alpha;
} DaTextViewColorConfiguration;

/** Size-prefixed immutable display-only text-view creation configuration. */
typedef struct DaTextViewConfiguration {
  uint64_t struct_size;
  DaViewConfiguration view;
  int32_t font_kind;
  int32_t font_weight;
  double font_size;
  double padding_top;
  double padding_right;
  double padding_bottom;
  double padding_left;
  DaTextViewColorConfiguration foreground_color;
  DaTextViewColorConfiguration background_color;
} DaTextViewConfiguration;

#define DA_TEXT_VIEW_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaTextViewConfiguration))

#define DA_TEXT_EDITOR_MAX_TEXT_UTF8_BYTES ((size_t)(16u * 1024u * 1024u))
#define DA_TEXT_EDITOR_MAX_STYLE_RUNS ((size_t)(64u * 1024u))

typedef enum DaTextEditorUnderlineStyle {
  DA_TEXT_EDITOR_UNDERLINE_NONE = 0,
  DA_TEXT_EDITOR_UNDERLINE_SINGLE = 1
} DaTextEditorUnderlineStyle;

/** Size-prefixed immutable multiline editor creation configuration. */
typedef struct DaTextEditorConfiguration {
  uint64_t struct_size;
  DaTextViewConfiguration presentation;
  int32_t initially_editable;
  int32_t reserved;
} DaTextEditorConfiguration;

#define DA_TEXT_EDITOR_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaTextEditorConfiguration))

/** One ordered, non-overlapping UTF-16 attributed range. */
typedef struct DaTextEditorStyleRun {
  uint64_t location;
  uint64_t length;
  DaTextViewColorConfiguration foreground_color;
  int32_t underline_style;
  int32_t reserved;
  DaTextViewColorConfiguration underline_color;
} DaTextEditorStyleRun;

/**
 * Current multiline editor state.
 *
 * text is borrowed from thread-local bridge storage until the next snapshot
 * call on the same thread. It is not NUL-termination-dependent. Selection
 * coordinates use NSString-compatible UTF-16 code units.
 */
typedef struct DaTextEditorSnapshot {
  const char* text;
  size_t text_length;
  uint64_t selection_location;
  uint64_t selection_length;
  int32_t is_editable;
  int32_t has_marked_text;
} DaTextEditorSnapshot;

/** Size-prefixed immutable menu creation configuration. */
typedef struct DaMenuConfiguration {
  uint64_t struct_size;
  int32_t auto_enables_items;
  int32_t reserved;
} DaMenuConfiguration;

#define DA_MENU_CONFIGURATION_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaMenuConfiguration))

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

/**
 * Size-prefixed, content-free Secure Event Input ownership snapshot.
 *
 * desired records the client's retained request. owned_enabled is true only
 * when this bridge successfully acquired one balanced system reference.
 * system_enabled is observational and may also reflect another process.
 */
typedef struct DaSecureEventInputSnapshot {
  uint64_t struct_size;
  int32_t desired;
  int32_t owned_enabled;
  int32_t system_enabled;
  int32_t last_os_status;
} DaSecureEventInputSnapshot;

#define DA_SECURE_EVENT_INPUT_SNAPSHOT_VERSION_1_SIZE \
  ((uint64_t)sizeof(DaSecureEventInputSnapshot))

/** Non-interactive secure-input indication rendered over a view. */
typedef enum DaSecureInputIndicatorState {
  DA_SECURE_INPUT_INDICATOR_HIDDEN = 0,
  DA_SECURE_INPUT_INDICATOR_AUTOMATIC = 1,
  DA_SECURE_INPUT_INDICATOR_MANUAL = 2
} DaSecureInputIndicatorState;

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
  DA_STATUS_LIMIT_EXCEEDED = 10,
  DA_STATUS_GLOBAL_HOT_KEY_CONFLICT = 11,
  DA_STATUS_GLOBAL_HOT_KEY_REGISTRATION_FAILED = 12,
  DA_STATUS_SECURE_EVENT_INPUT_FAILED = 13
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
  DA_EVENT_APPLICATION_APPEARANCE_CHANGED = 33,
  DA_EVENT_MENU_ITEM_INVOKED = 40,
  DA_EVENT_GLOBAL_HOT_KEY_PRESSED = 41,
  DA_EVENT_VIEW_QUICK_LOOK_REQUESTED = 42,
  DA_EVENT_VIEW_SERVICES_TEXT_RECEIVED = 43,
  DA_EVENT_VIEW_DROP_PERFORMED = 44,
  DA_EVENT_APPLICATION_FOLDER_SERVICE_REQUESTED = 45,
  DA_EVENT_APPLICATION_USER_NOTIFICATION_CHANGED = 46
} DaEventType;

/** Stable UserNotifications authorization values used by protocol version 13. */
typedef enum DaUserNotificationAuthorizationStatus {
  DA_USER_NOTIFICATION_AUTHORIZATION_NOT_DETERMINED = 0,
  DA_USER_NOTIFICATION_AUTHORIZATION_DENIED = 1,
  DA_USER_NOTIFICATION_AUTHORIZATION_AUTHORIZED = 2,
  DA_USER_NOTIFICATION_AUTHORIZATION_PROVISIONAL = 3,
  DA_USER_NOTIFICATION_AUTHORIZATION_EPHEMERAL = 4,
  DA_USER_NOTIFICATION_AUTHORIZATION_UNKNOWN = 5
} DaUserNotificationAuthorizationStatus;

/** Stable lifecycle results carried by one notification event. */
typedef enum DaUserNotificationEventKind {
  DA_USER_NOTIFICATION_EVENT_SETTINGS = 0,
  DA_USER_NOTIFICATION_EVENT_AUTHORIZATION = 1,
  DA_USER_NOTIFICATION_EVENT_DELIVERY = 2,
  DA_USER_NOTIFICATION_EVENT_DEFAULT_RESPONSE = 3
} DaUserNotificationEventKind;

/** Content-free failure classification for notification lifecycle events. */
typedef enum DaUserNotificationFailure {
  DA_USER_NOTIFICATION_FAILURE_NONE = 0,
  DA_USER_NOTIFICATION_FAILURE_DENIED = 1,
  DA_USER_NOTIFICATION_FAILURE_SYSTEM = 2,
  DA_USER_NOTIFICATION_FAILURE_CANCELLED = 3
} DaUserNotificationFailure;

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
 * Main thread only. Opens a structurally safe URL under application policy.
 *
 * expected_scheme is a copied lowercase ASCII scheme selected from the
 * application's immutable allowlist. policy_flags may contain only
 * DaExternalUrlPolicyFlag bits and must not both require and forbid authority.
 * The URL's actual scheme must exactly match expected_scheme.
 */
DA_EXPORT int32_t da_application_open_external_url_with_policy(
    const char* url, size_t url_length, const char* expected_scheme,
    size_t expected_scheme_length, uint64_t policy_flags,
    int32_t* out_opened);

/**
 * Main thread only. Submits one immediate alert-only local notification.
 *
 * All UTF-8 inputs are copied before return. identifier must be nonempty,
 * bounded ASCII suitable for later cancellation, and title/body must contain
 * safe display text with at least one nonempty field. Authorization and final
 * scheduling complete asynchronously; this call reports synchronous admission.
 */
DA_EXPORT int32_t da_application_post_user_notification(
    const char* identifier, size_t identifier_length, const char* title,
    size_t title_length, const char* body, size_t body_length);

/** Asynchronously reads settings and later posts a version-13 settings event.
 */
DA_EXPORT int32_t
da_application_get_user_notification_settings(int64_t* out_request_token);

/** Explicitly requests alert authorization and later posts its exact status. */
DA_EXPORT int32_t da_application_request_user_notification_authorization(
    int64_t* out_request_token);

/**
 * Submits one tracked alert. response_token must be positive and opaque.
 * Exactly one delivery event follows unless shutdown suppresses late callbacks;
 * a default selection later emits response_token. Inputs are copied on return.
 */
DA_EXPORT int32_t da_application_post_tracked_user_notification(
    const char* identifier, size_t identifier_length, const char* title,
    size_t title_length, const char* body, size_t body_length,
    int64_t response_token, int64_t* out_request_token);

/** Main thread only. Cancels pending and delivered notification identity. */
DA_EXPORT int32_t da_application_remove_user_notification(
    const char* identifier, size_t identifier_length);

/**
 * Main thread only. Sets a copied short Dock badge, or clears it for zero bytes.
 */
DA_EXPORT int32_t da_application_set_dock_badge_label(
    const char* label, size_t label_length);

/**
 * Main thread only. Registers one exclusive system-wide physical-key chord.
 *
 * key_code is a macOS virtual key code in the inclusive range 0 through 127.
 * modifiers must contain at least one of Shift, Control, Option, or Command
 * and no other DaModifier bits. On success out_handle owns the registration;
 * da_release unregisters it. A collision reports
 * DA_STATUS_GLOBAL_HOT_KEY_CONFLICT without allocating a handle.
 */
DA_EXPORT int32_t da_global_hot_key_register(uint16_t key_code,
                                             uint64_t modifiers,
                                             DaHandle* out_handle);

/**
 * Main thread only. Creates the bridge-wide Secure Event Input owner.
 *
 * At most one owner may exist. The returned resource starts undesired and
 * disabled; da_release balances any reference acquired by this owner.
 */
DA_EXPORT int32_t da_secure_event_input_create(DaHandle* out_handle);

/**
 * Main thread only. Retains a desired state and applies it while the app is
 * active. Activation changes automatically yield and reacquire the owned
 * reference. Repeating a state is idempotent.
 */
DA_EXPORT int32_t da_secure_event_input_set_desired(DaHandle handle,
                                                    int32_t desired);

/** Main thread only. Reads desired, owned, system, and last OSStatus state. */
DA_EXPORT int32_t da_secure_event_input_get_snapshot(
    DaHandle handle, DaSecureEventInputSnapshot* out_snapshot);

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

/** Main thread only. Creates a configured menu and copies its UTF-8 title. */
DA_EXPORT int32_t da_menu_create_configured(
    const char* title, size_t title_length,
    const DaMenuConfiguration* configuration, DaHandle* out_menu);

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

/** Main thread only. checked must be 0 or 1. Separators are rejected. */
DA_EXPORT int32_t da_menu_item_set_checked(DaHandle item, int32_t checked);

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

/**
 * Main thread only. Resolves current screen geometry without caching it.
 *
 * selection must be a DaScreenSelection. out_snapshot must provide at least
 * DA_SCREEN_SNAPSHOT_VERSION_1_SIZE bytes in struct_size.
 */
DA_EXPORT int32_t da_application_resolve_screen(
    int32_t selection, DaScreenSnapshot* out_snapshot);

/** Main thread only. Replaces the finite positive outer window frame. */
DA_EXPORT int32_t da_window_set_frame(DaHandle window, DaRect frame);

/** Main thread only. Copies the current native content layout rectangle. */
DA_EXPORT int32_t da_window_get_content_layout_rect(DaHandle window,
                                                    DaRect* out_rect);

/**
 * Main thread only. Requests native AppKit fullscreen entry or exit.
 *
 * enabled must be 0 or 1. Completion is asynchronous and is reported by
 * DA_EVENT_WINDOW_FULLSCREEN_CHANGED under event protocol version 6.
 */
DA_EXPORT int32_t da_window_set_fullscreen(DaHandle window, int32_t enabled);

/** Main thread only. Replaces generic window level and Spaces behavior. */
DA_EXPORT int32_t da_window_set_presentation_configuration(
    DaHandle window,
    const DaWindowPresentationConfiguration* configuration);

/**
 * Main thread only. Shows a window from start_frame toward target_frame.
 *
 * duration_seconds must be finite and in [0, 5]. make_key must be 0 or 1.
 * A zero duration applies the target atomically.
 */
DA_EXPORT int32_t da_window_present(DaHandle window, DaRect start_frame,
                                    DaRect target_frame,
                                    double duration_seconds,
                                    int32_t make_key);

/**
 * Main thread only. Hides a window toward target_frame without closing it.
 * duration_seconds must be finite and in [0, 5].
 */
DA_EXPORT int32_t da_window_hide(DaHandle window, DaRect target_frame,
                                 double duration_seconds);

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

/** Main thread only. Creates a generic AppKit view with compatibility defaults. */
DA_EXPORT int32_t da_view_create(DaHandle* out_view);

/** Main thread only. Creates a configured generic AppKit view. */
DA_EXPORT int32_t da_view_create_configured(
    const DaViewConfiguration* configuration, DaHandle* out_view);

/**
 * Main thread only. Shows or removes a non-interactive secure-input badge.
 * The overlay does not participate in the target view's layout or resize it.
 */
DA_EXPORT int32_t da_view_set_secure_input_indicator(DaHandle view,
                                                     int32_t state);

/**
 * Main thread only. Attaches a menu for view-local context presentation, or
 * clears it when menu is zero. Consumes neither handle.
 */
DA_EXPORT int32_t da_view_set_context_menu(DaHandle view, DaHandle menu);

/**
 * Main thread only. Enables or disables asynchronous stage-2 pressure
 * requests for this view. enabled must be zero or one.
 */
DA_EXPORT int32_t da_view_set_quick_look_request_enabled(DaHandle view,
                                                         int32_t enabled);

/**
 * Main thread only. Presents a copied bounded term through AppKit definition
 * lookup at one finite baseline point in the receiver's coordinates.
 */
DA_EXPORT int32_t da_view_show_definition(
    DaHandle view, const char* text, size_t text_length,
    const DaDefinitionPresentationConfiguration* configuration,
    const char* font_family, size_t font_family_length);

/**
 * Main thread only. Replaces one View's copied plain-text Services requestor
 * state. A null configuration disables the requestor and requires empty input.
 */
DA_EXPORT int32_t da_view_set_services_text_requestor(
    DaHandle view, const char* selection_text, size_t selection_text_length,
    const DaServicesTextRequestorConfiguration* configuration);

/**
 * Main thread only. Replaces one View's bounded copy-only drop destination.
 * A null configuration disables the destination.
 */
DA_EXPORT int32_t da_view_set_drop_destination(
    DaHandle view, const DaDropDestinationConfiguration* configuration);

/**
 * Main thread only. Replaces the application's bounded local-folder Services
 * provider. A null configuration disables the provider.
 */
DA_EXPORT int32_t da_application_set_folder_services_provider(
    const DaFolderServicesProviderConfiguration* configuration);

/**
 * Main thread only. Creates the two-pane helper: two children, one thin
 * non-collapsible divider, and optional binary child zoom.
 */
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

/**
 * Main thread only. Returns the current first-child fraction after native
 * divider constraints and user interaction. The result is finite in [0, 1].
 */
DA_EXPORT int32_t da_split_view_get_fraction(DaHandle split_view,
                                             double* out_fraction);

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

/** Main thread only. Uses the display-text compatibility defaults. */
DA_EXPORT int32_t da_text_view_create(DaHandle* out_view);

/**
 * Main thread only. Creates a configured display-only text view.
 * font_family is required only for DA_TEXT_VIEW_FONT_NAMED and is copied.
 */
DA_EXPORT int32_t da_text_view_create_configured(
    const DaTextViewConfiguration* configuration, const char* font_family,
    size_t font_family_length, DaHandle* out_view);

/** Main thread only. UTF-8 bytes are copied before return. */
DA_EXPORT int32_t da_text_view_set_text(DaHandle view, const char* text,
                                        size_t text_length);

/**
 * Main thread only. Creates one scrollable native multiline text editor.
 * font_family follows da_text_view_create_configured's ownership contract.
 */
DA_EXPORT int32_t da_text_editor_create_configured(
    const DaTextEditorConfiguration* configuration, const char* font_family,
    size_t font_family_length, DaHandle* out_editor);

/**
 * Main thread only. Atomically replaces text, attributed runs, and selection.
 * Text and runs are copied. Ranges and selection use UTF-16 code units and
 * must not split a surrogate pair.
 */
DA_EXPORT int32_t da_text_editor_set_document(
    DaHandle editor, const char* text, size_t text_length,
    const DaTextEditorStyleRun* style_runs, size_t style_run_count,
    uint64_t selection_location, uint64_t selection_length);

/**
 * Main thread only. Replaces attributed runs without replacing editor text.
 * This preserves the native editing/IME surface and current selection.
 */
DA_EXPORT int32_t da_text_editor_set_style_runs(
    DaHandle editor, const DaTextEditorStyleRun* style_runs,
    size_t style_run_count);

/**
 * Main thread only. Sets one full-width logical-line background at a checked
 * UTF-16 location. The color is copied; null clears the current highlight.
 */
DA_EXPORT int32_t da_text_editor_set_line_highlight(
    DaHandle editor, uint64_t location,
    const DaTextViewColorConfiguration* color);

/** Main thread only. Enables or disables native text editing in place. */
DA_EXPORT int32_t da_text_editor_set_editable(DaHandle editor,
                                              int32_t editable);

/** Main thread only. Sets a checked UTF-16 selection without replacing text. */
DA_EXPORT int32_t da_text_editor_set_selection(DaHandle editor,
                                               uint64_t location,
                                               uint64_t length);

/**
 * Main thread only. Scrolls the current checked selection into the visible
 * text-editor viewport without changing text, selection, or attributes.
 */
DA_EXPORT int32_t da_text_editor_scroll_selection_to_visible(DaHandle editor);

/** Main thread only. Returns a borrowed plain-text and selection snapshot. */
DA_EXPORT int32_t da_text_editor_get_snapshot(
    DaHandle editor, DaTextEditorSnapshot* out_snapshot);

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
