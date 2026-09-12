#include "dart_appkit.h"
#include "dart_appkit_native_extension.h"

_Static_assert(sizeof(DaHandle) == 8, "DaHandle must be 64-bit");
_Static_assert(sizeof(DaViewConfiguration) == 24,
               "unexpected DaViewConfiguration layout");
_Static_assert(sizeof(DaTextViewColorConfiguration) == 40,
               "unexpected DaTextViewColorConfiguration layout");
_Static_assert(sizeof(DaTextViewConfiguration) == 160,
               "unexpected DaTextViewConfiguration layout");
_Static_assert(sizeof(DaDefinitionPresentationConfiguration) == 48,
               "unexpected DaDefinitionPresentationConfiguration layout");
_Static_assert(sizeof(DaMenuConfiguration) == 16,
               "unexpected DaMenuConfiguration layout");
_Static_assert(sizeof(DaScreenSnapshot) == 88,
               "unexpected DaScreenSnapshot layout");
_Static_assert(sizeof(DaWindowPresentationConfiguration) == 24,
               "unexpected DaWindowPresentationConfiguration layout");
_Static_assert(sizeof(DaSecureEventInputSnapshot) == 24,
               "unexpected DaSecureEventInputSnapshot layout");
_Static_assert(DA_ABI_VERSION == 1, "unexpected ABI version");
_Static_assert(DA_EVENT_PROTOCOL_VERSION_MIN == 1,
               "unexpected minimum event protocol version");
_Static_assert(DA_EVENT_PROTOCOL_VERSION_CURRENT == 9,
               "unexpected current event protocol version");
_Static_assert(DA_NATIVE_EXTENSION_ABI_VERSION == 1,
               "unexpected native extension ABI version");

int da_header_compiles_as_c(void) {
  DaRect rect = {0.0, 0.0, 640.0, 480.0};
  uint32_t selected_version = 0;
  int32_t (*versioned_registration)(int64_t, uint32_t, uint32_t, uint32_t*) =
      da_application_set_event_port_versioned;
  int32_t (*termination_reply)(int64_t, int32_t) =
      da_application_reply_to_termination_request;
  int32_t (*external_url_open)(const char*, size_t, int32_t*) =
      da_application_open_external_url;
  int32_t (*external_url_open_with_policy)(const char*, size_t, const char*,
                                           size_t, uint64_t, int32_t*) =
      da_application_open_external_url_with_policy;
  int32_t (*close_reply)(DaHandle, int64_t, int32_t) =
      da_window_reply_to_close_request;
  int32_t (*key_event_routing)(DaHandle, int32_t) =
      da_window_set_key_event_routing;
  int32_t (*global_hot_key_register)(uint16_t, uint64_t, DaHandle*) =
      da_global_hot_key_register;
  int32_t (*secure_event_input_create)(DaHandle*) =
      da_secure_event_input_create;
  int32_t (*secure_event_input_set_desired)(DaHandle, int32_t) =
      da_secure_event_input_set_desired;
  int32_t (*secure_event_input_snapshot)(DaHandle,
                                         DaSecureEventInputSnapshot*) =
      da_secure_event_input_get_snapshot;
  int32_t (*secure_input_indicator)(DaHandle, int32_t) =
      da_view_set_secure_input_indicator;
  int32_t (*view_context_menu)(DaHandle, DaHandle) =
      da_view_set_context_menu;
  int32_t (*quick_look_enabled)(DaHandle, int32_t) =
      da_view_set_quick_look_request_enabled;
  int32_t (*show_definition)(
      DaHandle, const char*, size_t,
      const DaDefinitionPresentationConfiguration*, const char*, size_t) =
      da_view_show_definition;
  int32_t (*screen_resolve)(int32_t, DaScreenSnapshot*) =
      da_application_resolve_screen;
  int32_t (*window_present)(DaHandle, DaRect, DaRect, double, int32_t) =
      da_window_present;
  int32_t (*window_hide)(DaHandle, DaRect, double) = da_window_hide;
  int32_t (*window_presentation_configuration)(
      DaHandle, const DaWindowPresentationConfiguration*) =
      da_window_set_presentation_configuration;
  int32_t (*pasteboard_read)(DaPasteboardText*) = da_pasteboard_read_text;
  int32_t (*menu_create)(const char*, size_t, DaHandle*) = da_menu_create;
  int32_t (*configured_menu_create)(const char*, size_t,
                                    const DaMenuConfiguration*, DaHandle*) =
      da_menu_create_configured;
  int32_t (*menu_item_create)(const char*, size_t, const char*, size_t,
                              uint64_t, DaHandle*) = da_menu_item_create;
  int32_t (*menu_item_set_checked)(DaHandle, int32_t) =
      da_menu_item_set_checked;
  int32_t (*custom_view_create)(const char*, size_t, DaHandle*) =
      da_view_create_custom;
  int32_t (*configured_view_create)(const DaViewConfiguration*, DaHandle*) =
      da_view_create_configured;
  int32_t (*configured_text_view_create)(const DaTextViewConfiguration*,
                                         const char*, size_t, DaHandle*) =
      da_text_view_create_configured;
  int32_t (*custom_view_operation)(DaHandle, const uint8_t*, size_t) =
      da_view_perform_custom_operation;
  int32_t (*window_tab_add)(DaHandle, DaHandle) =
      da_window_add_tabbed_window;
  int32_t (*first_responder)(DaHandle, DaHandle) =
      da_window_make_first_responder;
  int32_t (*split_create)(int32_t, DaHandle*) = da_split_view_create;
  int32_t (*split_children)(DaHandle, DaHandle, DaHandle) =
      da_split_view_set_children;
  int32_t (*split_position)(DaHandle, double, double, double) =
      da_split_view_set_position;
  const da_native_extension_services_v1* (*extension_services)(uint32_t) =
      da_native_extension_services;
  return rect.width == 640.0 && versioned_registration != 0 &&
                 termination_reply != 0 && close_reply != 0 &&
                 external_url_open != 0 &&
                 external_url_open_with_policy != 0 &&
                 key_event_routing != 0 &&
                 global_hot_key_register != 0 &&
                 secure_event_input_create != 0 &&
                 secure_event_input_set_desired != 0 &&
                 secure_event_input_snapshot != 0 &&
                 secure_input_indicator != 0 &&
                 view_context_menu != 0 &&
                 quick_look_enabled != 0 && show_definition != 0 &&
                 screen_resolve != 0 && window_present != 0 &&
                 window_hide != 0 && window_presentation_configuration != 0 &&
                 pasteboard_read != 0 && menu_create != 0 &&
                 configured_menu_create != 0 &&
                 menu_item_create != 0 && custom_view_create != 0 &&
                 menu_item_set_checked != 0 &&
                 configured_view_create != 0 &&
                 configured_text_view_create != 0 &&
                 custom_view_operation != 0 &&
                 window_tab_add != 0 && first_responder != 0 &&
                 split_create != 0 && split_children != 0 &&
                 split_position != 0 &&
                 extension_services != 0 && selected_version == 0
             ? DA_STATUS_OK
             : DA_STATUS_INTERNAL_ERROR;
}
