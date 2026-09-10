#include <type_traits>

#include "dart_appkit.h"
#include "dart_appkit_native_extension.h"

static_assert(sizeof(DaHandle) == 8);
static_assert(std::is_standard_layout_v<DaRect>);
static_assert(std::is_standard_layout_v<DaError>);
static_assert(std::is_standard_layout_v<DaPasteboardText>);
static_assert(std::is_standard_layout_v<DaViewConfiguration>);
static_assert(std::is_standard_layout_v<DaTextViewColorConfiguration>);
static_assert(std::is_standard_layout_v<DaTextViewConfiguration>);
static_assert(sizeof(DaViewConfiguration) == 24);
static_assert(sizeof(DaTextViewColorConfiguration) == 40);
static_assert(sizeof(DaTextViewConfiguration) == 160);
static_assert(std::is_standard_layout_v<DaMenuConfiguration>);
static_assert(sizeof(DaMenuConfiguration) == 16);
static_assert(DA_EVENT_PROTOCOL_VERSION_MIN == 1);
static_assert(DA_EVENT_PROTOCOL_VERSION_CURRENT == 7);
static_assert(DA_KEY_EVENT_ROUTING_DART_AND_APPKIT == 0);
static_assert(DA_KEY_EVENT_ROUTING_DART_ONLY == 1);
static_assert(DA_SPLIT_AXIS_HORIZONTAL == 0);
static_assert(DA_SPLIT_AXIS_VERTICAL == 1);
static_assert(DA_SPLIT_ZOOM_NONE == -1);
static_assert(std::is_standard_layout_v<da_native_extension_services_v1>);
static_assert(DA_NATIVE_EXTENSION_ABI_VERSION == 1);

int da_header_compiles_as_cpp() {
  const DaRect rect{0.0, 0.0, 640.0, 480.0};
  auto* custom_view_create = &da_view_create_custom;
  auto* configured_view_create = &da_view_create_configured;
  auto* configured_text_view_create = &da_text_view_create_configured;
  auto* configured_menu_create = &da_menu_create_configured;
  auto* custom_view_operation = &da_view_perform_custom_operation;
  auto* external_url_open = &da_application_open_external_url;
  auto* external_url_open_with_policy =
      &da_application_open_external_url_with_policy;
  auto* key_event_routing = &da_window_set_key_event_routing;
  auto* window_tab_add = &da_window_add_tabbed_window;
  auto* first_responder = &da_window_make_first_responder;
  auto* split_create = &da_split_view_create;
  auto* split_children = &da_split_view_set_children;
  auto* extension_services = &da_native_extension_services;
  return rect.height == 480.0 && custom_view_create != nullptr &&
                 configured_view_create != nullptr &&
                 configured_text_view_create != nullptr &&
                 configured_menu_create != nullptr &&
                 custom_view_operation != nullptr &&
                 external_url_open != nullptr &&
                 external_url_open_with_policy != nullptr &&
                 key_event_routing != nullptr &&
                 window_tab_add != nullptr && first_responder != nullptr &&
                 split_create != nullptr && split_children != nullptr &&
                 extension_services != nullptr
             ? DA_STATUS_OK
             : DA_STATUS_INTERNAL_ERROR;
}
