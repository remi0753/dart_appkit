#include "TerminalRendererPlugin.h"

int main(void) {
  uint32_t (*version)(void) = dtr_abi_version;
  int32_t (*initialize)(const da_native_extension_services_v1*) =
      dtr_initialize;
  int32_t (*live_count)(void) = dtr_debug_live_view_count;
  return version == 0 || initialize == 0 || live_count == 0;
}
