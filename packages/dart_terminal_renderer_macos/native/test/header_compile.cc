#include <type_traits>

#include "TerminalRendererPlugin.h"

static_assert(std::is_standard_layout_v<da_native_extension_services_v1>);

int main() {
  auto* version = &dtr_abi_version;
  auto* initialize = &dtr_initialize;
  auto* live_count = &dtr_debug_live_view_count;
  return version == nullptr || initialize == nullptr || live_count == nullptr;
}
