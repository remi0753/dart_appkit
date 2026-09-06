#include <type_traits>

#include "dart_appkit.h"
#include "dart_appkit_native_extension.h"

static_assert(sizeof(DaHandle) == 8);
static_assert(std::is_standard_layout_v<DaRect>);
static_assert(std::is_standard_layout_v<DaError>);
static_assert(std::is_standard_layout_v<DaPasteboardText>);
static_assert(DA_EVENT_PROTOCOL_VERSION_MIN == 1);
static_assert(DA_EVENT_PROTOCOL_VERSION_CURRENT == 5);
static_assert(DA_KEY_EVENT_ROUTING_DART_AND_APPKIT == 0);
static_assert(DA_KEY_EVENT_ROUTING_DART_ONLY == 1);
static_assert(std::is_standard_layout_v<da_native_extension_services_v1>);
static_assert(DA_NATIVE_EXTENSION_ABI_VERSION == 1);

int da_header_compiles_as_cpp() {
  const DaRect rect{0.0, 0.0, 640.0, 480.0};
  auto* custom_view_create = &da_view_create_custom;
  auto* custom_view_operation = &da_view_perform_custom_operation;
  auto* external_url_open = &da_application_open_external_url;
  auto* key_event_routing = &da_window_set_key_event_routing;
  auto* extension_services = &da_native_extension_services;
  return rect.height == 480.0 && custom_view_create != nullptr &&
                 custom_view_operation != nullptr &&
                 external_url_open != nullptr &&
                 key_event_routing != nullptr &&
                 extension_services != nullptr
             ? DA_STATUS_OK
             : DA_STATUS_INTERNAL_ERROR;
}
