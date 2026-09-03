#include <type_traits>

#include "dart_appkit.h"

static_assert(sizeof(DaHandle) == 8);
static_assert(std::is_standard_layout_v<DaRect>);
static_assert(std::is_standard_layout_v<DaError>);
static_assert(std::is_standard_layout_v<DaPasteboardText>);
static_assert(DA_EVENT_PROTOCOL_VERSION_MIN == 1);
static_assert(DA_EVENT_PROTOCOL_VERSION_CURRENT == 4);

int da_header_compiles_as_cpp() {
  const DaRect rect{0.0, 0.0, 640.0, 480.0};
  auto* custom_view_create = &da_view_create_custom;
  return rect.height == 480.0 && custom_view_create != nullptr
             ? DA_STATUS_OK
             : DA_STATUS_INTERNAL_ERROR;
}
