#include "dart_appkit.h"

_Static_assert(sizeof(DaHandle) == 8, "DaHandle must be 64-bit");
_Static_assert(DA_ABI_VERSION == 1, "unexpected ABI version");
_Static_assert(DA_EVENT_PROTOCOL_VERSION_MIN == 1,
               "unexpected minimum event protocol version");
_Static_assert(DA_EVENT_PROTOCOL_VERSION_CURRENT == 2,
               "unexpected current event protocol version");

int da_header_compiles_as_c(void) {
  DaRect rect = {0.0, 0.0, 640.0, 480.0};
  uint32_t selected_version = 0;
  int32_t (*versioned_registration)(int64_t, uint32_t, uint32_t, uint32_t*) =
      da_application_set_event_port_versioned;
  return rect.width == 640.0 && versioned_registration != 0 &&
                 selected_version == 0
             ? DA_STATUS_OK
             : DA_STATUS_INTERNAL_ERROR;
}
