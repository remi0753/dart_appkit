#include "dart_appkit.h"
#include "dart_appkit_native_extension.h"

_Static_assert(sizeof(DaHandle) == 8, "DaHandle must be 64-bit");
_Static_assert(DA_ABI_VERSION == 1, "unexpected ABI version");
_Static_assert(DA_EVENT_PROTOCOL_VERSION_MIN == 1,
               "unexpected minimum event protocol version");
_Static_assert(DA_EVENT_PROTOCOL_VERSION_CURRENT == 4,
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
  int32_t (*close_reply)(DaHandle, int64_t, int32_t) =
      da_window_reply_to_close_request;
  int32_t (*pasteboard_read)(DaPasteboardText*) = da_pasteboard_read_text;
  int32_t (*menu_create)(const char*, size_t, DaHandle*) = da_menu_create;
  int32_t (*menu_item_create)(const char*, size_t, const char*, size_t,
                              uint64_t, DaHandle*) = da_menu_item_create;
  int32_t (*custom_view_create)(const char*, size_t, DaHandle*) =
      da_view_create_custom;
  const da_native_extension_services_v1* (*extension_services)(uint32_t) =
      da_native_extension_services;
  return rect.width == 640.0 && versioned_registration != 0 &&
                 termination_reply != 0 && close_reply != 0 &&
                 pasteboard_read != 0 && menu_create != 0 &&
                 menu_item_create != 0 && custom_view_create != 0 &&
                 extension_services != 0 && selected_version == 0
             ? DA_STATUS_OK
             : DA_STATUS_INTERNAL_ERROR;
}
