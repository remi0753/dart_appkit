#include "dart_appkit.h"

_Static_assert(sizeof(DaHandle) == 8, "DaHandle must be 64-bit");
_Static_assert(DA_ABI_VERSION == 1, "unexpected ABI version");

int da_header_compiles_as_c(void) {
  DaRect rect = {0.0, 0.0, 640.0, 480.0};
  return rect.width == 640.0 ? DA_STATUS_OK : DA_STATUS_INTERNAL_ERROR;
}
